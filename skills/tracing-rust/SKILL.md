---
name: tracing-rust
description: Use when instrumenting Rust code with tracing — spans, events, macros, subscribers, layers, structured logging, and tokio-console integration. Covers tracing, tracing-subscriber, and tracing-core.
---

# Tracing Rust

Use these conventions for instrumenting Rust applications with [`tokio-rs/tracing`](https://github.com/tokio-rs/tracing). Tracing provides structured, event-based diagnostic information through spans, events, and subscribers.

## Source Baseline

- Prefer released docs from `docs.rs/tracing`, crates.io, and the matching GitHub release.
- Current stable: `tracing 0.1.41`, `tracing-subscriber 0.3.19`, `tracing-core 0.1.34`.
- MSRV: Rust 1.65+.

## Cargo.toml

```toml
[dependencies]
tracing = "0.1"

# For subscribers and formatting — almost always needed
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }

# Optional: for tokio-console debugging
console-subscriber = "0.4"

# Optional: JSON layer for structured logging
# Already covered by tracing-subscriber's "json" feature
```

## Core Concepts

**Spans** represent a period of time. **Events** represent a moment in time. **Subscribers** collect and process span/event data.

```rust
use tracing::{info, instrument, span, Level};

// A span represents a unit of work
let span = span!(Level::INFO, "request", request_id = %id);
let _enter = span.enter();
info!("processing started");
// _enter dropped → span exits
```

## Macros — Events

```rust
use tracing::{trace, debug, info, warn, error};

trace!("very noisy detail");
debug!("debugging info");
info!("something happened");                        // no fields
info!(user_id = %id, "user logged in");             // with fields (% = Display)
info!(user_id = ?id, "user logged in");             // with fields (? = Debug)
info!(count = count, "processed items");            // with fields (no sigil = Display for number types)
warn!(status = %resp.status(), "slow response");    // warn level
error!(error = %e, "database connection failed");   // error level
```

### Level Semantics

| Level | Use For |
|-------|---------|
| `TRACE` | Very low-level internals; expect high volume |
| `DEBUG` | Diagnostic info useful during development |
| `INFO` | Normal operational events (startup, shutdown, connections) |
| `WARN` | Degraded but recoverable states |
| `ERROR` | Failures requiring attention |

## The `#[instrument]` Attribute

```rust
use tracing::instrument;

// Basic: auto-creates a span from function name and arguments
#[instrument]
async fn handle_request(user_id: u64, path: String) -> Result<(), Error> {
    // span: "handle_request", fields: user_id, path
    info!("processing request");
    Ok(())
}

// Skip arguments (too large or sensitive)
#[instrument(skip(large_body, secret))]
fn process(large_body: Vec<u8>, secret: String, id: u64) {
    // Only `id` is recorded; large_body and secret are skipped
}

// Custom span name and level
#[instrument(name = "db_query", level = "debug", skip(raw_sql))]
fn query_db(raw_sql: String, table: &str) -> Vec<Row> { ... }

// Record return value
#[instrument(ret, err)]
fn compute(input: i32) -> Result<i32, ComputeError> {
    // Both Ok value and Err are recorded as span fields
}

// Fields on the span
#[instrument(fields(db.query = query.as_str()))]
fn execute(query: Query) -> Result<(), Error> { ... }
```

### `#[instrument]` Options

- `skip(...)` — don't record these params as fields.
- `fields(...)` — add extra fields to the span.
- `ret` / `ret(Debug)` / `ret(Display)` — record the return value.
- `err` / `err(Debug)` / `err(Display)` — record the error on Err return.
- `level = "debug"` / `level = Level::TRACE` — set span level.
- `name = "custom"` — override span name (default is function name).

## Spans — Manual Creation

```rust
use tracing::{span, Level, info, Instrument};

// Create and enter a span
let span = span!(Level::INFO, "database_query", query_id = %id);
let _enter = span.enter();

// Or enter explicitly for a block
span.in_scope(|| {
    info!("inside span");
});

// With async: use .instrument()
async fn do_work() { /* ... */ }
tokio::spawn(do_work().instrument(span!(Level::INFO, "background_job")))
    .await?;
```

### Span Fields

```rust
// Display formatting (% sigil)
span!(Level::INFO, "http_request", method = %req.method(), path = %req.path());

// Debug formatting (? sigil)
span!(Level::DEBUG, "data_received", payload = ?data);

// Automatic (no sigil — uses Display, falls back to Debug)
span!(Level::INFO, "connection", port = 8080);

// Bool shorthand
span!(Level::INFO, "cache", hit = true);
```

## Subscriber Setup

### Basic — `fmt` Subscriber

```rust
use tracing_subscriber;

fn main() {
    tracing_subscriber::fmt::init();
    // Default: writes to stderr, uses RUST_LOG env var, pretty format
}
```

### With Env Filter

```rust
use tracing_subscriber::{fmt, EnvFilter};

fn main() {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    fmt()
        .with_env_filter(filter)
        .init();
}
```

### Directed — Per-Module Filtering

```rust
use tracing_subscriber::{fmt, EnvFilter};

fn main() {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("my_app=info,sqlx=warn"));

    fmt()
        .with_env_filter(filter)
        .init();
}
```

### JSON Output

```rust
use tracing_subscriber::fmt;

fn main() {
    fmt()
        .json()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
}
```

### Layered Subscriber (Multiple Outputs)

```rust
use tracing_subscriber::{fmt, layer, EnvFilter, Registry};
use tracing_subscriber::util::SubscriberInitExt;

fn main() {
    let fmt_layer = fmt::layer()
        .with_target(false)
        .with_thread_ids(true);

    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    Registry::default()
        .with(filter)
        .with(fmt_layer)
        .init();
}
```

## Structured Logging with Fields

Fields are the structured data component of spans and events. They live in the span and are included in all events within that span:

```rust
use tracing::{info, span, Level};

let span = span!(Level::INFO, "http_request", method = "GET", path = "/api/users");
let _enter = span.enter();

info!("request started");          // includes method and path
info!(status_code = 200, "request completed");  // adds status_code
```

### Display vs Debug

```rust
info!(user = %user);      // % = Display formatting
info!(user = ?user);       // ? = Debug formatting
info!(user = %user, id = id);  // mixed
```

- `%` — calls `.fmt()` (Display). Good for strings, numbers.
- `?` — calls `.fmt()` (Debug). Good for structs, enums, complex types.
- No sigil — defaults to Display for numbers, Debug otherwise.

## Error Logging

```rust
use tracing::{error, warn};

// Log an error with source chain
match operation() {
    Ok(result) => info!(result = ?result, "operation succeeded"),
    Err(e) => {
        // Use % for Display, ? for Debug (includes backtrace with eyre/anyhow)
        error!(error = ?e, "operation failed");
    }
}

// Chain-friendly: makes full context visible
error!(error = ?err, "database connection failed");
// NOT: error!("database connection failed: {}", err) — loses structure
```

## Async Instrumentation

```rust
use tracing::Instrument;

// Instrument a future
let fut = async { do_work().await }.instrument(tracing::span!(Level::INFO, "do_work"));
tokio::spawn(fut);

// Instrument with #[instrument]
#[instrument(skip_all)]
async fn process_queue(queue: &Queue) -> Result<(), Error> {
    // span created automatically
    info!("starting queue processing");
    Ok(())
}
```

## tokio-console Integration

```rust
// In Cargo.toml:
// tracing = { version = "0.1", features = ["release_max_level_info"] }
// console-subscriber = "0.4"

 fn main() {
     console_subscriber::init();
     // ... tokio runtime starts
 }
```

- Enable `tracing`'s `release_max_level_info` feature in production to avoid overhead.
- tokio-console requires `tokio` with `tracing` feature.

## RUST_LOG Environment Variable

```bash
# Show info and above for all crates
RUST_LOG=info cargo run

# Per-module control
RUST_LOG=my_app=debug,sqlx=warn,tokio=off cargo run

# Trace everything
RUST_LOG=trace cargo run

# Multiple targets
RUST_LOG=my_app::db=trace,my_app::api=info cargo run
```

## Testing with tracing

```rust
// In tests, use tracing_subscriber to capture output
#[tracing::instrument]
#[tokio::test]
async fn test_authenticated_request() {
    // Initialize for tests (once)
    let _ = tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::new("debug"))
        .try_init();

    // Spans and events visible in test output
    info!("test starting");
}

// Use tracing-test for capturing assertions
// tracing-test = "0.2" in [dev-dependencies]
// fn test_something() {
//     // ...
//     assert!(logs_contain("expected message"));
// }
```

## What NOT to Do

- **Do not** use `span.enter()` across `.await` points — use `.instrument()` instead.
- **Do not** stringify errors in log calls (`error!("failed: {}", e)`) — use structured fields (`error!(error = ?e, "failed")`).
- **Do not** set `RUST_LOG=trace` in production without `release_max_level_*` features.
- **Do not** create spans with high-cardinality fields in hot loops (each unique field value creates a new span identity).
- **Do not** skip `.init()` — without a subscriber, all tracing is no-op (zero overhead but invisible).

## Review Checklist

- [ ] Subscriber initialized early in `main` with `init()` or `try_init()`.
- [ ] `#[instrument]` used on public functions and async handlers; `skip` for large/sensitive args.
- [ ] Spans entered with `.instrument()` for async code, not `span.enter()` across `.await`.
- [ ] Error logging uses structured fields (`error = ?e`), not string formatting.
- [ ] `RUST_LOG` env filter configured with sensible defaults.
- [ ] `release_max_level_info` or similar feature enabled in production builds.
- [ ] No high-cardinality span fields in hot paths (e.g., per-request IDs in span-level fields).