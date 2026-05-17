---
name: walkdir-rust
description: Use when recursively walking directories in Rust with walkdir — WalkDir iterator, DirEntry, filter_entry, depth control, symlink following, and error handling.
---

# Walkdir Rust

Use these conventions for directory traversal with [`BurntSushi/walkdir`](https://github.com/BurntSushi/walkdir). Walkdir provides a cross-platform, efficient, recursive directory iterator.

## Source Baseline

- Prefer released docs from `docs.rs/walkdir`, crates.io, and the matching GitHub release.
- Current stable: `walkdir 2.5`.
- No external dependencies (zero-dep crate).
- Cross-platform: Linux, macOS, Windows.

## Cargo.toml

```toml
[dependencies]
walkdir = "2"
```

No features to enable. The crate works as-is.

## Basic Usage

```rust
use walkdir::WalkDir;

// Recursively walk a directory
for entry in WalkDir::new("src") {
    let entry = entry?;
    println!("{}", entry.path().display());
}
```

- Yields `Result<DirEntry, Error>` — handle errors per-entry (e.g., permission denied).
- `DirEntry` provides path, file type, depth, metadata.

## WalkDir Builder — Configuration

```rust
use walkdir::WalkDir;
use std::path::Path;

let mut walker = WalkDir::new("project")
    .max_depth(3)               // Limit recursion depth (0 = just the root)
    .follow_links(true)         // Follow symbolic links
    .sort_by(|a, b| a.file_name().cmp(b.file_name()));  // Sort entries

for entry in walker {
    let entry = entry?;
    println!("{} (depth {})", entry.path().display(), entry.depth());
}
```

### Key Configuration Methods

| Method | Default | Description |
|--------|---------|-------------|
| `.max_depth(n)` | None (unlimited) | Limit recursion depth (0 = root only) |
| `.min_depth(n)` | 0 | Skip entries at depth < n |
| `.follow_links(bool)` | `false` | Follow symbolic links |
| `.sort_by(cmp)` | Unsorted | Sort entries within each directory |
| `.contents_first(bool)` | `false` | Yield directory contents before the directory itself |

## DirEntry — Inspecting Entries

```rust
use walkdir::DirEntry;

fn process(entry: &DirEntry) {
    // Path (borrowed, not owned)
    let path = entry.path();

    // File name (OsStr)
    let file_name = entry.file_name();

    // Depth (root = 0)
    let depth = entry.depth();

    // File type (no syscalls — cached from readdir)
    let file_type = entry.file_type();
    if file_type.is_dir() { }
    if file_type.is_file() { }
    if file_type.is_symlink() { }

    // Full metadata (syscalls)
    if let Ok(meta) = entry.metadata() {
        let len = meta.len();
        let modified = meta.modified().ok();
    }
}
```

- `file_type()` is **free** — cached from `readdir`/`FindFirstFile`. No extra syscalls.
- `metadata()` makes a **syscall**. Use only when needed.
- `path()` returns `&Path` — borrow, no allocation.

## Filtering — filter_entry and filter_map

### filter_entry — Skip Directories Efficiently

`filter_entry` prunes entire subtrees. If the closure returns `false` for a directory, the directory **and all its contents** are skipped.

```rust
use walkdir::{DirEntry, WalkDir};
use std::ffi::OsStr;

fn is_hidden(entry: &DirEntry) -> bool {
    entry.file_name()
        .to_str()
        .map(|s| s.starts_with('.'))
        .unwrap_or(false)
}

// Skip hidden files AND directories (won't even recurse into .git, etc.)
for entry in WalkDir::new("project").into_iter().filter_entry(|e| !is_hidden(e)) {
    let entry = entry?;
    println!("{}", entry.path().display());
}
```

### filter_map — Handle Errors Gracefully

```rust
use walkdir::WalkDir;

// Silently skip entries with errors (e.g., permission denied)
for entry in WalkDir::new("project").into_iter().filter_map(|e| e.ok()) {
    println!("{}", entry.path().display());
}
```

### Combined — Filter and Handle Errors

```rust
use walkdir::{DirEntry, WalkDir};

let files: Vec<path::PathBuf> = WalkDir::new("src")
    .into_iter()
    .filter_entry(|e| !is_hidden(e))
    .filter_map(|e| e.ok())
    .filter(|e| e.file_type().is_file())
    .map(|e| e.into_path())
    .collect();
```

## Depth Control — min_depth and max_depth

```rust
use walkdir::WalkDir;

// Skip the root entry itself, only yield children
// min_depth(1) excludes the root directory
for entry in WalkDir::new("src").min_depth(1) {
    let entry = entry?;
    // Never yields the "src" directory itself
}

// Only walk two levels deep
for entry in WalkDir::new("project").max_depth(2) {
    let entry = entry?;
    // Yields: project/, project/src/, project/src/main.rs
    // But NOT: project/src/deep/nested.rs (depth 3)
}

// Combine: only entries at depth 1 and 2 (immediate children and grandchildren)
for entry in WalkDir::new("project").min_depth(1).max_depth(2) {
    let entry = entry?;
}
```

## Sorting

```rust
use walkdir::WalkDir;

// Sort by file name (deterministic order)
for entry in WalkDir::new("src").sort_by(|a, b| a.file_name().cmp(b.file_name())) {
    let entry = entry?;
    println!("{}", entry.path().display());
}

// Sort by path for full-path ordering
for entry in WalkDir::new("src").sort_by(|a, b| a.path().cmp(b.path())) {
    let entry = entry?;
}
```

- Sorting is per-directory, not global. Parent directories are always yielded before their children.
- There is a small performance cost: directory entries are buffered to sort them.

## Symlink Handling

```rust
use walkdir::WalkDir;

// Default: does NOT follow symlinks
// Symlinks appear as DirEntry with is_symlink() == true

// Follow symlinks (detect cycles automatically)
for entry in WalkDir::new("project").follow_links(true) {
    let entry = entry?;
    // Cycles are detected and reported as Error with cycle_detected() == true
}
```

- Without `follow_links`, symlinks are reported but not traversed.
- With `follow_links(true)`, walkdir detects cycles and returns an error with `Error::cycle_detected()`.
- Always check error types when following symlinks:

```rust
use walkdir::WalkDir;

for result in WalkDir::new("project").follow_links(true) {
    match result {
        Ok(entry) => println!("{}", entry.path().display()),
        Err(e) => {
            if e.cycle_detected() {
                eprintln!("cycle detected: {}", e.path().display());
                continue; // skip and keep walking
            }
            eprintln!("error: {e}");
        }
    }
}
```

## Error Handling

```rust
use walkdir::{Error, WalkDir};

for result in WalkDir::new("/root-owned") {
    match result {
        Ok(entry) => process(&entry),
        Err(e) => {
            if e.io_error().is_some() {
                // I/O error (permission denied, not found, etc.)
                eprintln!("I/O error at {}: {}", e.path().display(), e);
            }
            if e.cycle_detected() {
                eprintln!("cycle detected at: {}", e.path().display());
            }
            // Continue walking — errors don't stop iteration
            continue;
        }
    }
}
```

- `Error::io_error()` — returns `Option<&io::Error>`.
- `Error::path()` — the path that caused the error.
- `Error::cycle_detected()` — true if a symlink cycle was found.
- Errors are yielded inline; subsequent entries are still iterated.

## contents_first — Yield Children Before Parents

```rust
use walkdir::WalkDir;

// Post-order traversal: yield files first, then their containing directory
for entry in WalkDir::new("src").contents_first(true) {
    let entry = entry?;
    println!("{} (depth {})", entry.path().display(), entry.depth());
}
// Output:
// src/main.rs (depth 1)
// src/lib.rs (depth 1)
// src (depth 0)
```

## Common Patterns

### Find All Rust Source Files

```rust
use walkdir::WalkDir;
use std::path::PathBuf;

let rust_files: Vec<PathBuf> = WalkDir::new("src")
    .into_iter()
    .filter_map(|e| e.ok())
    .filter(|e| e.path().extension().map_or(false, |ext| ext == "rs"))
    .map(|e| e.into_path())
    .collect();
```

### Count Files by Extension

```rust
use walkdir::WalkDir;
use std::collections::HashMap;

let mut counts: HashMap<String, usize> = HashMap::new();
for entry in WalkDir::new("project").into_iter().filter_map(|e| e.ok()) {
    if entry.file_type().is_file() {
        let ext = entry.path()
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("none")
            .to_string();
        *counts.entry(ext).or_insert(0) += 1;
    }
}
```

### Parallel Walk with rayon

```rust
use walkdir::WalkDir;
use rayon::prelude::*;

let entries: Vec<_> = WalkDir::new("src")
    .into_iter()
    .filter_map(|e| e.ok())
    .collect();

entries.par_iter().for_each(|entry| {
    // Process each entry in parallel
    process(entry);
});
```

## Note on same_file

Walkdir depends on `same_file` for detecting same-file relationships. This is used internally for cycle detection and is not part of the public API.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Using `.filter()` to skip directories | Use `.filter_entry()` — `.filter()` still recurses into skipped dirs |
| Not handling I/O errors | Always handle `Err` entries in the iterator |
| Calling `metadata()` unnecessarily | Use `file_type()` for type checks — it's free (cached from readdir) |
| Forgetting `into_iter()` | `WalkDir` is the builder; call `.into_iter()` to get the iterator |
| Using `follow_links` without cycle detection | Always check `Error::cycle_detected()` when `follow_links(true)` |
| Sorting has a cost | Remove `.sort_by()` if order doesn't matter |

## Review Checklist

- [ ] `filter_entry` used to skip directories (not `.filter()` which still recurses).
- [ ] I/O errors handled per-entry, not unwrap'd.
- [ ] `file_type()` used for type checks instead of `metadata()` where possible.
- [ ] `follow_links(true)` accompanied by `Error::cycle_detected()` checks.
- [ ] `max_depth` used when deep recursion is not needed.
- [ ] `contents_first(true)` used for post-order traversal patterns.
- [ ] No unnecessary `.into_path()` allocations unless ownership is needed past the iterator.