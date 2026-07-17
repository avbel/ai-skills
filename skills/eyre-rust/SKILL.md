---
name: eyre-rust
description: Use when writing or reviewing Rust error handling with eyre/eyre — Report, WrapErr trait, eyre! macro, custom handlers, error chaining, backtraces, and the eyre vs anyhow migration.
---

# Eyre Rust

Use these conventions for Rust error handling with [`eyre-rs/eyre`](https://github.com/eyre-rs/eyre). Eyre is a fork of `anyhow` with support for customized error report handlers. It provides `eyre::Report`, a trait-object error type for idiomatic error handling and reporting in Rust applications.

## Source Baseline

- Prefer released docs from `docs.rs/eyre`, crates.io, and the matching GitHub release over older snippets.
- Current stable: `eyre 0.6.12`.
- Eyre is **for applications and binaries**, not libraries. Library crates should use `thiserror` or hand-written error enums.

## Cargo.toml

```toml
[dependencies]
eyre = "0.6"
```

For custom handlers (e.g., `color-eyre`):
```toml
[dependencies]
eyre = "0.6"
color-eyre = "0.6"
```

For anyhow compatibility (migrating from anyhow):
```toml
[dependencies]
eyre = { version = "0.6", features = ["anyhow"] }
```

## Core Types

- `eyre::Report` — trait-object wrapper around any `std::error::Error + Send + Sync + 'static`. The primary error type.
- `eyre::Result<T>` — alias for `Result<T, Report>`. Prefer in function signatures.
- `eyre::Result<T, E>` — also works for custom error types; `E` must impl `std::error::Error`.

```rust
use eyre::Result;

fn load_config(path: &str) -> Result<Config> {
    let bytes = std::fs::read(path)?;
    let cfg: Config = toml::from_slice(&bytes)?;
    Ok(cfg)
}
```

## WrapErr Trait (eyre's Context)

Eyre uses `WrapErr` instead of anyhow's `Context`. This is the key ergonomics feature:

```rust
use eyre::{WrapErr, Result};

fn load_config(path: &str) -> Result<Config> {
    let bytes = std::fs::read(path)
        .wrap_err_with(|| format!("reading config from {path}"))?;
    let cfg: Config = toml::from_slice(&bytes)
        .wrap_err_with(|| format!("parsing TOML in {path}"))?;
    Ok(cfg)
}
```

- Use `.wrap_err("static message")` for cheap, static strings.
- Use `.wrap_err_with(|| format!(...))` when the message allocates — the closure runs **only on error**.
- `WrapErr` is **only implemented for `Result`**, not `Option`. This is intentional: `wrap_err` implies wrapping a source error, which `Option` doesn't have.

## The `eyre!` Macro

- `eyre!("message")` — construct a Report from a string.
- `eyre!("formatted {} message", val)` — format string version.
- `eyre!(some_error_value)` — wrap any `std::error::Error` or `Debug + Display` type.

```rust
use eyre::{eyre, Result};

fn check_permission(user: &User, resource: &str) -> Result<()> {
    if !user.has_permission(resource) {
        return Err(eyre!("permission denied for {resource}"));
    }
    Ok(())
}
```

## `bail!` and `ensure!`

- `bail!(...)` — equivalent to `return Err(eyre!(...))`.
- `ensure!(cond, ...)` — conditional bail; returns early if condition is false.

```rust
use eyre::{bail, ensure, Result};

fn process(depth: usize) -> Result<()> {
    ensure!(depth <= MAX_DEPTH, "recursion limit {MAX_DEPTH} exceeded (depth = {depth})");
    if invalid_state() {
        bail!("invalid state detected");
    }
    Ok(())
}
```

## Custom Report Handlers

Eyre's distinguishing feature over anyhow. Swap the handler to change what information errors carry and how they format:

```rust
// Set a custom handler early in main
fn main() -> eyre::Result<()> {
    // Use default handler (minimal, like anyhow)
    eyre::set_hook(Box::new(|_| Box::new(eyre::DefaultHandler::default())))?;

    // Or use color-eyre for colorful backtraces and span traces
    // color_eyre::install()?;

    run()?;
    Ok(())
}
```

Known handler crates:
- **`stable-eyre`** — uses `std::backtrace::Backtrace`; captures backtraces only, no span information.
- **`color-eyre`** — colorful backtraces, `tracing_error::SpanTrace`, `Section` trait for custom error sections.
- **`simple-eyre`** — minimal handler that only formats the error chain.
- **`jane-eyre`** — combines `color-eyre` features with additional customization.

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

- `{:?}` (debug-format) on `Report` prints full chain + backtrace if available.

## Backtraces

- Eyre captures `std::backtrace::Backtrace` at error construction when the handler supports it.
- Control via env vars: `RUST_BACKTRACE=1`, `RUST_LIB_BACKTRACE=1`.
- Default handler does **not** print backtraces. Use `color-eyre` or a custom handler to display them.

## Migration from anyhow

Key differences:
- `Context` → `WrapErr` (trait name)
- `.context(...)` → `.wrap_err(...)` (method name)  
- `.with_context(...)` → `.wrap_err_with(...)` (lazy method name)
- `anyhow!` → `eyre!` (macro name, also available as alias)
- `anyhow::Error` → `eyre::Report` (type name)
- `anyhow::Result<T>` → `eyre::Result<T>` (type alias)
- `WrapErr` is **not** implemented for `Option` (use `ok_or_eyre!` or `.ok_or_else(|| eyre!(...))`)

Enable the `anyhow` feature for drop-in compatibility:
```rust
use eyre::{anyhow, bail, ensure, Context, Result};
// Context is re-exported as an alias for WrapErr
```

## What NOT to Do

- **Do not** return `eyre::Report` from a public library API. Use `thiserror` or custom error enums for libraries.
- **Do not** stringify errors prematurely with `format!("{e}")` — it collapses the chain. Pass the `Report` itself.
- **Do not** use `.unwrap()` or `.expect()` on `eyre::Report` in non-test code. Propagate with `?`.
- **Do not** mix `eyre::Report` and `Box<dyn Error>` in the same function.
- **Do not** implement `WrapErr` for `Option` — use `.ok_or_else()` instead.

## Review Checklist

- [ ] Library crates use `thiserror`, not `eyre`.
- [ ] Binaries and integration glue return `eyre::Result<_>`; `main` returns `eyre::Result<()>`.
- [ ] Every `?` at an interesting boundary has `.wrap_err(...)` or `.wrap_err_with(|| ...)`.
- [ ] `.wrap_err(...)` used for static strings; `.wrap_err_with(|| ...)` for format strings.
- [ ] No `format!("{e}")` flattening when the whole chain should be preserved — use `{:?}` or `.chain()`.
- [ ] No `eyre::Report` leaking through `pub` API of a library crate.
- [ ] Custom handler installed in `main` via `eyre::set_hook` or `color_eyre::install()`.