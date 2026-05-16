---
name: anyhow-rust
description: Use when writing or reviewing Rust error handling with dtolnay/anyhow — anyhow::Error, anyhow::Result, Context trait, anyhow!/bail!/ensure! macros, error chaining and root cause, downcasting, backtraces, no-std mode, and the application/binary vs library (thiserror) split.
---

# Anyhow Rust

Use these conventions for Rust error handling with [`dtolnay/anyhow`](https://github.com/dtolnay/anyhow). Anyhow provides `anyhow::Error`, a trait-object error type that wraps anything implementing `std::error::Error`, plus ergonomic context, chaining, and downcasting.

## Source Baseline

- Prefer released docs from `docs.rs/anyhow`, crates.io, and the matching GitHub release over older blog snippets.
- Latest 1.x release line. Add to `Cargo.toml`:
  ```toml
  [dependencies]
  anyhow = "1"
  ```
- For no-std: `anyhow = { version = "1", default-features = false }`. A global allocator is still required.

## Application vs Library Split

This is the most important rule. Pick the right tool at the right boundary:

- **Applications, binaries, integration tests, scripts → `anyhow`.** The caller of `main` doesn't pattern-match on your errors; they want a clear chain of context.
- **Library crates → `thiserror` (or a hand-written enum implementing `std::error::Error`).** Consumers must be able to match on specific variants. Returning `anyhow::Error` from a library forces every downstream caller to either accept it as opaque or downcast.
- Workspaces with internal crates can mix: lower-level crates use `thiserror`, the top-level binary uses `anyhow`. `anyhow::Error: From<E> where E: std::error::Error` makes the boundary seamless — `?` just works.

## Core Types

- `anyhow::Error` — a trait-object wrapper around any `std::error::Error + Send + Sync + 'static`. Size of two pointers (vs `Box<dyn Error>`'s one) because it stores a vtable for context.
- `anyhow::Result<T>` — alias for `Result<T, anyhow::Error>`. Prefer this in function signatures.
- `anyhow::Chain` — iterator over the source-error chain (used by `.chain()`).

```rust
use anyhow::Result;

fn load_config(path: &str) -> Result<Config> {
    let bytes = std::fs::read(path)?;        // io::Error -> anyhow::Error
    let cfg: Config = toml::from_slice(&bytes)?;  // toml::de::Error -> anyhow::Error
    Ok(cfg)
}
```

## The `Context` Trait

`Context` is what makes anyhow worth using over `Box<dyn Error>`. Attach a human-readable layer at each call site so the error chain reads top-down like a stack trace.

```rust
use anyhow::{Context, Result};

fn load_config(path: &str) -> Result<Config> {
    let bytes = std::fs::read(path)
        .with_context(|| format!("reading config from {path}"))?;
    let cfg: Config = toml::from_slice(&bytes)
        .with_context(|| format!("parsing TOML in {path}"))?;
    Ok(cfg)
}
```

- Use `.context("static message")` for cheap, static strings.
- Use `.with_context(|| format!(...))` when the message allocates — the closure runs **only on error**, so this is the right form for any format string.
- Context layers are stacked: `Display` shows the outermost message; `.chain()` walks all the way to the root.

Anti-pattern:

```rust
// WRONG — formatting always runs, even on success
foo().context(format!("loading {expensive_to_format}"))?
// CORRECT — lazy
foo().with_context(|| format!("loading {expensive_to_format}"))?
```

## The Macros

### `anyhow!` — construct an error
- `anyhow!("static message")`
- `anyhow!("formatted {} message", val)`
- `anyhow!(some_error_value)` — wraps any `std::error::Error` or `Debug + Display` type.
- `anyhow!(MyEnumVariant)` when paired with a `thiserror` enum.

### `bail!` — early return with an error
- Equivalent to `return Err(anyhow!(...))`. Function must return `Result<_, anyhow::Error>`.
- Use the format-string form like `anyhow!`:
  ```rust
  if !user.has_permission(&resource) {
      bail!("permission denied for accessing {resource}");
  }
  ```

### `ensure!` — conditional bail (`anyhow`'s `assert!`)
- `ensure!(cond, "message {}", arg);` — returns early if `cond` is false.
- Equivalent to `if !cond { bail!(...) }`.
- Prefer over `assert!`/`panic!` in fallible code paths — `ensure!` returns, doesn't panic.

```rust
ensure!(depth <= MAX_DEPTH, "recursion limit {MAX_DEPTH} exceeded (depth = {depth})");
```

## Error Chains and Display

```rust
match load_config("settings.toml") {
    Ok(cfg) => run(cfg),
    Err(err) => {
        eprintln!("error: {err}");                 // outermost layer only
        for cause in err.chain().skip(1) {
            eprintln!("  caused by: {cause}");
        }
        eprintln!("root cause: {}", err.root_cause());
    }
}
```

- `{:?}` (debug-format) on `anyhow::Error` already prints the full chain and the backtrace if available — useful in `main()`.
- For consistent end-of-program reporting, return `anyhow::Result<()>` from `main`:
  ```rust
  fn main() -> anyhow::Result<()> {
      run()?;
      Ok(())
  }
  ```
  Rust formats the error with `{:?}`, so you get the full chain automatically.

## Backtraces (Rust ≥ 1.65)

- Anyhow captures a `std::backtrace::Backtrace` at error construction when the inner error does not already carry one.
- Control via env vars (same conventions as `std::backtrace`):
  - `RUST_BACKTRACE=1` — backtraces for panics and errors.
  - `RUST_LIB_BACKTRACE=1` — backtraces for errors only.
  - `RUST_BACKTRACE=1 RUST_LIB_BACKTRACE=0` — backtraces for panics only.
- Backtraces are printed by `{:?}` formatting (i.e., by `main`'s default error reporting).

## Downcasting

When you need to handle a specific error type after it's been wrapped:

```rust
use anyhow::Error;

fn handle(err: Error) {
    if let Some(io_err) = err.downcast_ref::<std::io::Error>() {
        if io_err.kind() == std::io::ErrorKind::NotFound {
            // ...
            return;
        }
    }
    // fall through to generic handling
}
```

- `.downcast::<T>()` — by value, returns `Result<T, Error>`.
- `.downcast_ref::<T>()` — borrow.
- `.downcast_mut::<T>()` — mutable borrow.
- Downcasting works through context layers — it finds the *original* concrete type, not the context wrappers.
- Use downcasting sparingly. If you find yourself downcasting often, the boundary should be a `thiserror` enum instead.

## Combinator-Friendly: `Error::msg` and `Ok`

- `Error::msg("...")` constructs the same thing as `anyhow!("...")` but is a function — useful in `.map_err(Error::msg)` and stream/iterator chains.
- `anyhow::Ok(value)` — equivalent to `Ok::<_, anyhow::Error>(value)`. Avoids type-annotation noise inside closures.

```rust
items.iter()
    .map(|item| -> anyhow::Result<_> {
        let parsed: i32 = item.parse().context("parsing item")?;
        anyhow::Ok(parsed * 2)
    })
    .collect::<anyhow::Result<Vec<_>>>()?;
```

## Mixing with `thiserror`

The two crates are complementary, both by the same author. A typical workspace:

```rust
// lower-level crate (library)
#[derive(thiserror::Error, Debug)]
pub enum StorageError {
    #[error("blob {0} not found")]
    NotFound(String),
    #[error("io error")]
    Io(#[from] std::io::Error),
}

// higher-level crate (application)
use anyhow::{Context, Result};

fn handle_request(id: &str) -> Result<Vec<u8>> {
    storage::read(id).with_context(|| format!("loading blob {id}"))
}
```

- `?` lifts `StorageError` into `anyhow::Error` automatically (via `From`).
- The application can still recover specific variants with `.downcast_ref::<StorageError>()`.

## What NOT to Do

- **Do not** return `anyhow::Error` from a public library API.
- **Do not** use `anyhow!` to wrap an already-`std::error::Error` value when you actually mean to **preserve** the source — pass the error through `?`/`From`, or use `.context(...)`. `anyhow!(err)` *does* preserve the source (it is equivalent to `Error::new(err)`), but `.with_context(|| ...)` reads better and adds a layer.
- **Do not** stringify errors prematurely: `format!("{e}")` collapses the chain to a single line and discards the source. Pass the `Error` itself; let `{:?}` or your reporting layer expand it.
- **Do not** `.unwrap()` or `.expect()` on `anyhow::Error` in non-test code. Propagate with `?` or pattern-match.
- **Do not** mix `anyhow::Error` and `Box<dyn Error>` in the same function — pick one and stay there.

## no-std Mode

- Disable default features: `anyhow = { version = "1", default-features = false }`.
- Requires a global allocator (`alloc` is always needed).
- `std::error::Error` is replaced by `core::error::Error` (stable since 1.81). All macros and the `Context` trait work the same.
- Backtraces are unavailable in no-std.

## Logging Integration

When errors flow into a `tracing` or `log` event, log the whole chain — not just the outermost layer:

```rust
match do_work() {
    Ok(()) => {},
    Err(err) => tracing::error!(error = %format!("{err:?}"), "work failed"),
}
```

Or with `tracing`'s `Display`-of-`anyhow::Error` shortcut:

```rust
tracing::error!(error = ?err, "work failed");
```

The `?err` form invokes `Debug`, which on `anyhow::Error` prints the full chain and backtrace.

## Review Checklist

- [ ] Library crates use `thiserror` (or hand-rolled `Error` impls), not `anyhow`.
- [ ] Binaries and integration glue return `anyhow::Result<_>`; `main` returns `anyhow::Result<()>` for free chain-printing.
- [ ] Every `?` at an interesting boundary has a `.with_context(|| ...)` describing what was being attempted.
- [ ] `.context(...)` only used with static strings or pre-built `String`s — anything that allocates per call goes in `.with_context(|| ...)`.
- [ ] No `format!("{e}")` flattening when the whole chain should be preserved — use `{:?}` or iterate `.chain()`.
- [ ] No `anyhow::Error` leaking through a `pub` API of a library crate.
- [ ] `bail!` / `ensure!` used in fallible code; no `panic!`/`unwrap`/`expect` in error paths.

## Helper Script

Use `scripts/anyhow-rust-bootstrap.sh` when an agent needs a quick machine-readable scaffold for a specific anyhow pattern:

```bash
bash /mnt/skills/user/anyhow-rust/scripts/anyhow-rust-bootstrap.sh context
bash /mnt/skills/user/anyhow-rust/scripts/anyhow-rust-bootstrap.sh bail
bash /mnt/skills/user/anyhow-rust/scripts/anyhow-rust-bootstrap.sh ensure
bash /mnt/skills/user/anyhow-rust/scripts/anyhow-rust-bootstrap.sh downcast
bash /mnt/skills/user/anyhow-rust/scripts/anyhow-rust-bootstrap.sh main
bash /mnt/skills/user/anyhow-rust/scripts/anyhow-rust-bootstrap.sh thiserror-mix
```
