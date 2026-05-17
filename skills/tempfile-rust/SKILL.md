---
name: tempfile-rust
description: Use when creating or managing temporary files and directories in Rust with tempfile — NamedTempFile, TempDir, SpooledTempFile, Builder, persist, and secure cleanup patterns.
---

# Tempfile Rust

Use these conventions for managing temporary files and directories with [`Stebalien/tempfile`](https://github.com/Stebalien/tempfile). This crate provides secure, cross-platform temporary file/directory creation with automatic cleanup on drop.

## Source Baseline

- Prefer released docs from `docs.rs/tempfile`, crates.io, and the matching GitHub release.
- Current stable: `tempfile 3.25`.
- MSRV: 1.63.0.
- Supported platforms: Linux, macOS, Windows, FreeBSD, Android, RedoxOS, WASI P1/P2.

## Cargo.toml

```toml
[dependencies]
tempfile = "3"
```

No features to enable. The crate works out of the box.

## Choosing the Right Type

| Need | Use |
|------|-----|
| Anonymous temp file (no path needed) | `tempfile()` |
| Named temp file (need path, e.g., for external process) | `NamedTempFile::new()` |
| Temporary directory (auto-deleted on drop) | `tempdir()` |
| In-memory buffer that spills to disk | `spooled_tempfile()` |
| Custom prefix/suffix/location | `Builder::new()` |

## `tempfile()` — Anonymous File

Returns a `std::fs::File`. The OS deletes the file when the last handle is closed. **No path, no filename.**

```rust
use tempfile::tempfile;
use std::io::{Write, Read, Seek, SeekFrom};

let mut file = tempfile()?;
write!(file, "Hello World!")?;
file.seek(SeekFrom::Start(0))?;
let mut s = String::new();
file.read_to_string(&mut s)?;
assert_eq!("Hello World!", s);
```

- File is unnamed (Linux: `O_TMPFILE`; other platforms: immediately unlinked).
- No path accessible via filesystem.

## `NamedTempFile` — Named File with Path

Creates a file in the temp directory with a unique name. Provides both a `File` handle and a `Path` reference.

```rust
use tempfile::NamedTempFile;
use std::io::{Write, BufWriter};

let mut tmp = NamedTempFile::new()?;
write!(tmp, "temporary data")?;

// Get the path (useful for passing to external processes)
let path = tmp.path();
println!("Temp file at: {}", path.display());

// Persist to a permanent location
tmp.persist("/data/important.txt")?;

// Or persist but keep the temp file handle on error
// tmp.persist_noclobber("/data/important.txt")?;
```

### Persist and Keep

```rust
let tmp = NamedTempFile::new()?;
// persist() — moves file to destination, consumes temp file
tmp.persist("/path/to/destination")?;

// persist_noclobber() — fails if destination already exists
let tmp = NamedTempFile::new()?;
match tmp.persist_noclobber("/path/to/destination") {
    Ok(_) => {},
    Err(e) => {
        // e.error is the io::Error
        // e.file is the NamedTempFile back (not deleted on failure)
        eprintln!("persist failed: {}", e.error);
    }
}

// keep() — turns NamedTempFile into a regular (Path, File), no auto-cleanup
let (file, path) = NamedTempFile::new()?.keep()?;
```

## `TempDir` — Temporary Directory

```rust
use tempfile::tempdir;
use std::fs::File;
use std::io::Write;

let dir = tempdir()?;
let file_path = dir.path().join("my-note.txt");
let mut file = File::create(&file_path)?;
writeln!(file, "Brian was here. Briefly.")?;

// Close explicitly to check deletion succeeded
dir.close()?;
// If not closed explicitly, directory is cleaned up when dir goes out of scope
// but you won't know if the cleanup succeeded.
```

- `dir.path()` returns `&Path` to the temporary directory.
- Directory is recursively deleted on drop.
- `dir.close()` returns `Result<()>` so you can detect cleanup failures.

## `SpooledTempFile` — In-Memory Buffer with Disk Overflow

```rust
use tempfile::spooled_tempfile;
use std::io::{Write, Read, Seek, SeekFrom};

// Max 1 KB in memory before spilling to disk
let mut tmp = spooled_tempfile(1024);
write!(tmp, "small data")?;

// Check if data is still in memory
if tmp.is_rolled_over() {
    println!("Data spilled to disk");
}

tmp.seek(SeekFrom::Start(0))?;
let mut s = String::new();
tmp.read_to_string(&mut s)?;
```

- `spooled_tempfile(max_size)` — creates in-memory buffer; spills to disk when data exceeds `max_size`.
- `spooled_tempfile_in(max_size, dir)` — same but uses a specific directory for the backing file.
- `is_rolled_over()` — checks if data has been written to disk.
- Useful for request/response bodies that are usually small but may be large.

## `Builder` — Custom Configuration

```rust
use tempfile::Builder;

// Custom prefix and suffix
let tmp = Builder::new()
    .prefix("myapp-")
    .suffix(".tmp")
    .tempdir()?;

// In a specific directory
let tmp = Builder::new()
    .prefix("myapp-")
    .tempdir_in("/var/data/tmp")?;

// Named temp file with custom config
let tmp = Builder::new()
    .prefix("myapp-")
    .rand_bytes(12)
    .make_in("/var/data/tmp")?;
```

- `.prefix("...")` — set filename prefix (default: `.tmp` or no prefix).
- `.suffix("...")` — set filename suffix/extension.
- `.rand_bytes(n)` — number of random bytes in filename (default: platform-dependent).
- `.tempdir()` / `.tempdir_in(dir)` — create a temporary directory.
- `.make()` / `.make_in(dir)` — create a named temp file.

## Error Handling

```rust
use tempfile::persist::PersistError;

match tmp.persist("/target/path") {
    Ok(_) => {},
    Err(PersistError { error, file }) => {
        // `error` is the io::Error
        // `file` is the NamedTempFile back — not deleted
        eprintln!("Failed to persist: {error}");
        // You can retry or inspect
    }
}
```

- `PersistError` gives you back the original `NamedTempFile` on failure.
- `PathPersistError` is the equivalent for `TempPath`.

## `env` Module — Override Temp Directory

```rust
// Override the temp directory for the current thread
tempfile::env::override_temp_dir(std::path::PathBuf::from("/custom/tmp"))?;

// Reset to system default
tempfile::env::override_temp_dir(std::path::PathBuf::from(""))?;
```

- On WASI P1/P2, you **must** call `override_temp_dir` because WASI has no default temp directory.
- On Android, you may need to override to point at the app's cache directory.

## Testing Patterns

```rust
#[test]
fn test_with_temp_dir() -> Result<(), Box<dyn std::error::Error>> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("test.txt");
    std::fs::write(&path, "test data")?;
    // ... test code ...
    Ok(()) // dir cleaned up on drop
}

#[test]
fn test_with_named_temp() -> Result<(), Box<dyn std::error::Error>> {
    let mut tmp = tempfile::NamedTempFile::new()?;
    writeln!(tmp, "test")?;
    tmp.seek(std::io::SeekFrom::Start(0))?;
    // ... test code ...
    Ok(())
}
```

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Using `tempfile()` when you need a path | Switch to `NamedTempFile::new()` |
| Not persisting `NamedTempFile` before drop | Call `.persist()` or `.keep()` explicitly |
| Ignoring `TempDir::close()` errors | Use `dir.close()?` instead of relying on drop |
| SpooledTempFile always rolling over | Increase `max_size`; `spooled_tempfile(1024)` is very small |
| Filename collisions in custom temp dirs | Use `Builder::rand_bytes()` to increase randomness |
| Android/WASI crashes | Call `tempfile::env::override_temp_dir()` before use |

## Review Checklist

- [ ] Correct type chosen: `tempfile()` vs `NamedTempFile` vs `TempDir` vs `SpooledTempFile`.
- [ ] `NamedTempFile` persisted or explicitly kept when needed past drop.
- [ ] `TempDir::close()` called when cleanup success matters (not just drop).
- [ ] No hardcoded `/tmp` path — use `Builder::tempdir_in()` or `env::temp_dir()` for custom locations.
- [ ] `spooled_tempfile` `max_size` is appropriate for the use case (not accidentally too small).