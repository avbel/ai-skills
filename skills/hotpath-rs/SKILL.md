---
name: hotpath-rs
description: Use when profiling Rust applications with pawurb/hotpath-rs: timing, allocations, CPU sampling, Tokio runtime metrics, async channels/streams/futures, static reports, live TUI, MCP server integration, or AI-assisted performance analysis.
---

# Hotpath Rust

Use these conventions for Rust performance profiling with `pawurb/hotpath-rs`.

## Source Baseline

- Prefer current docs from `hotpath.rs`, docs.rs, crates.io, and the matching GitHub release.
- Current baseline checked for this skill: `hotpath 0.16.1`.
- `hotpath` instruments Rust code for wall-clock timing, allocations, CPU samples, thread stats, async data flow, Tokio runtime metrics, static reports, live TUI dashboards, and MCP access for AI agents.
- Keep profiling behind local crate features. With the main `hotpath` feature disabled, instrumentation macros are noops.
- Treat JSON report formats, TUI internals, MCP internals, and advanced configuration as evolving surfaces.

## Cargo

Keep `hotpath` optional and expose profiling as explicit application features:

```toml
[dependencies]
hotpath = "0.16.1"

[features]
hotpath = ["hotpath/hotpath"]
hotpath-alloc = ["hotpath/hotpath-alloc"]
hotpath-cpu = ["hotpath/hotpath-cpu"]
hotpath-mcp = ["hotpath/hotpath-mcp"]
hotpath-tokio = ["hotpath/hotpath", "hotpath/tokio"]
```

For Tokio applications, keep the normal Tokio dependency explicit:

```toml
[dependencies]
tokio = { version = "1", features = ["macros", "rt-multi-thread", "sync", "time"] }
hotpath = "0.16.1"
```

Add channel-family features only for the channel APIs actually used:

```toml
[features]
hotpath-data-flow = ["hotpath/hotpath", "hotpath/tokio", "hotpath/futures"]
```

## Basic Function Profiling

Use `#[hotpath::main]` to create the profiling guard and `#[hotpath::measure]` for the functions worth observing.

```rust
use std::time::Duration;

#[hotpath::measure]
fn parse_batch(items: &[String]) -> usize {
    std::thread::sleep(Duration::from_millis(2));
    items.iter().map(String::len).sum()
}

#[hotpath::measure(log = true, label = "load_user")]
async fn load_user(id: u64) -> String {
    tokio::time::sleep(Duration::from_millis(5)).await;
    format!("user-{id}")
}

#[tokio::main]
#[hotpath::main(percentiles = [50, 95, 99], report = "functions-timing,functions-alloc,threads")]
async fn main() {
    let items = vec!["alpha".to_owned(), "beta".to_owned()];

    for id in 0..100 {
        let _bytes = parse_batch(&items);
        let _user = load_user(id).await;

        hotpath::measure_block!("serialize_response", {
            std::hint::black_box(format!("response-{id}"));
        });
    }
}
```

Run static timing reports with:

```bash
cargo run --features=hotpath
```

Run allocation reports with:

```bash
cargo run --features='hotpath,hotpath-alloc'
```

Use `HOTPATH_OUTPUT_FORMAT=json` and `HOTPATH_OUTPUT_PATH=report.json` when a test, benchmark, CI job, or AI agent should parse the result.

## Tokio Runtime Profiling

For Tokio services, add runtime sampling near the start of async `main`.

```rust
use tokio::{sync::mpsc, time::{sleep, Duration}};

#[hotpath::measure]
async fn handle_job(job: u64) {
    sleep(Duration::from_millis(job % 10)).await;
}

#[tokio::main]
#[hotpath::main(report = "functions-timing,channels,tokio_runtime,threads")]
async fn main() {
    hotpath::tokio_runtime!();

    let (tx, mut rx) = hotpath::channel!(
        mpsc::channel::<u64>(128),
        label = "jobs",
        log = true
    );

    let producer = tokio::spawn(async move {
        for job in 0..1_000 {
            tx.send(job).await.expect("jobs receiver alive");
        }
    });

    let consumer = tokio::spawn(async move {
        while let Some(job) = rx.recv().await {
            hotpath::future!(
                handle_job(job),
                label = "job_future",
                log = true
            )
            .await;
        }
    });

    producer.await.expect("producer task");
    consumer.await.expect("consumer task");
}
```

Run:

```bash
cargo run --features='hotpath-tokio'
```

For extra Tokio metrics, build with Tokio unstable cfg:

```bash
RUSTFLAGS="--cfg tokio_unstable" cargo run --features='hotpath-tokio'
```

- Put `#[tokio::main]` above `#[hotpath::main]`.
- Use `hotpath::tokio_runtime!(&handle)` when profiling a runtime through an explicit `tokio::runtime::Handle`.
- Use `HOTPATH_TOKIO_RUNTIME_INTERVAL_MS` to tune runtime sampling cadence.
- Include `tokio_runtime` in `HOTPATH_REPORT` or `#[hotpath::main(report = "...")]` when generating static reports.

## Async Data Flow

Use `channel!`, `stream!`, `future!`, and `#[future_fn]` when queue pressure, stream throughput, or future polling behavior is the suspected bottleneck.

```rust
use futures::{stream, StreamExt};

#[hotpath::future_fn(log = true)]
async fn fetch_page(page: u64) -> Vec<u8> {
    tokio::time::sleep(std::time::Duration::from_millis(page % 5)).await;
    vec![page as u8; 16]
}

#[tokio::main]
#[hotpath::main(report = "streams,futures")]
async fn main() {
    let pages = hotpath::stream!(
        stream::iter(1..=100),
        label = "pages",
        log = true
    );

    let total: usize = pages
        .then(|page| hotpath::future!(fetch_page(page), label = "fetch_page"))
        .map(|bytes| bytes.len())
        .sum()
        .await;

    std::hint::black_box(total);
}
```

- Label high-value channels, streams, and futures so the TUI and MCP tools are easy to query.
- Use `log = true` only when values implement `Debug` and logs are safe to expose.
- `futures` bounded channels require an explicit `capacity = N`; Tokio channels do not.
- Remember that monitored channels add a proxy on the receive side and can subtly affect edge-case channel behavior such as `try_send`.

## AI via MCP

Use MCP for long-running services or load tests where an AI agent should query live profiling data while the app runs.

1. Instrument functions, Tokio runtime, channels, streams, or futures.
2. Run the app with MCP enabled:

```bash
HOTPATH_OUTPUT_FORMAT=none \
HOTPATH_MCP_PORT=6771 \
cargo run --features='hotpath,hotpath-alloc,hotpath-mcp,hotpath-tokio'
```

3. Connect the AI agent over HTTP MCP:

```bash
claude mcp add --transport http hotpath http://localhost:6771/mcp
```

With auth:

```bash
HOTPATH_MCP_AUTH_TOKEN=secret123 \
cargo run --features='hotpath,hotpath-mcp'

claude mcp add --transport http hotpath http://localhost:6771/mcp \
  --header "Authorization: secret123"
```

Equivalent MCP config:

```json
{
  "mcpServers": {
    "hotpath": {
      "type": "http",
      "url": "http://localhost:6771/mcp",
      "headers": {
        "Authorization": "secret123"
      }
    }
  }
}
```

Ask targeted questions that map to hotpath tools:

- "Which functions dominate total execution time right now?"
- "Where are allocations concentrated?"
- "Which channel has the highest queue pressure?"
- "Show the last 10 timing events for handle_job."
- "Are Tokio workers saturated or building up queue depth?"
- "Compare latency and allocation behavior for parse_batch and load_user."

Useful MCP summary tools include `functions_timing`, `functions_alloc`, `channels`, `streams`, `futures`, `threads`, `tokio_runtime`, `gauges`, `dbg_entries`, `val_entries`, and `profiler_status`.

Useful log tools include `function_timing_logs`, `function_alloc_logs`, `channel_logs`, `stream_logs`, `future_logs`, `gauge_logs`, `dbg_logs`, and `val_logs`.

## Live TUI

Install the dashboard separately:

```bash
cargo install hotpath --features=tui --version '^0.16.1'
```

Run the console in one terminal:

```bash
hotpath console
```

Run the instrumented app in another terminal:

```bash
cargo run --features='hotpath,hotpath-alloc,hotpath-tokio'
```

- Use TUI for HTTP servers, queue workers, and other long-running processes.
- Use `HOTPATH_TUI_TAB=6` to start on the Tokio tab.
- Use `HOTPATH_METRICS_PORT` and `HOTPATH_METRICS_HOST` when the console needs non-default connection settings.

## CPU Sampling

Use CPU sampling when wall-clock timing alone cannot distinguish CPU-bound work from I/O waits.

```toml
[profile.profiling]
inherits = "release"
debug = true
```

```bash
cargo install samply --locked
cargo install hotpath --bin hotpath-samply --version '^0.16.1'
cargo run --features='hotpath,hotpath-alloc,hotpath-cpu' --profile profiling
```

On Linux, CPU profiling may need temporary kernel profiling permissions and `setsid -w`:

```bash
setsid -w cargo run --features='hotpath,hotpath-alloc,hotpath-cpu' --profile profiling
```

- Ensure `samply` and `hotpath-samply` are in `PATH`, or set `HOTPATH_SAMPLY_BIN` and `HOTPATH_SAMPLY_WRAPPER_BIN`.
- For methods in `impl` blocks, use `#[hotpath::measure(impl_type = "TypeName")]` or `#[hotpath::measure_all]` so CPU attribution matches demangled method names.
- `hotpath-cpu` rewrites measured functions to `#[inline(never)]` for better attribution unless `HOTPATH_KEEP_INLINE=1` is set before macro expansion.

## Reporting and Configuration

Common environment variables:

- `HOTPATH_OUTPUT_FORMAT`: `table`, `json`, `json-pretty`, or `none`.
- `HOTPATH_OUTPUT_PATH`: write report to a file.
- `HOTPATH_REPORT`: comma-separated sections such as `functions-timing`, `functions-alloc`, `channels`, `streams`, `futures`, `threads`, `tokio_runtime`, `debug`, or `all`.
- `HOTPATH_FOCUS`: substring or `/regex/` filter for function names.
- `HOTPATH_LIMIT`, `HOTPATH_FUNCTIONS_LIMIT`, `HOTPATH_CHANNELS_LIMIT`, `HOTPATH_STREAMS_LIMIT`, `HOTPATH_FUTURES_LIMIT`, `HOTPATH_THREADS_LIMIT`: cap report rows.
- `HOTPATH_MCP_PORT` and `HOTPATH_MCP_AUTH_TOKEN`: configure MCP access.
- `HOTPATH_SHUTDOWN_MS`: force shutdown and report generation after a fixed profiling window.
- `HOTPATH_LOGS_LIMIT` and `HOTPATH_MAX_LOG_LEN`: control retained debug/log payloads.

## Guidance

- Start with the smallest instrumentation that can answer the question: a few functions and one queue before `measure_all` across a module.
- Prefer static JSON reports for repeatable benchmarks and CI comparisons.
- Prefer live TUI or MCP for services whose bottlenecks depend on runtime load.
- Keep logged return values and channel payloads free of secrets or personal data.
- Disable or omit profiling features in production builds unless the deployment intentionally needs live profiling.
- Do not create more than one `HotpathGuard` at a time; `#[hotpath::main]` and manual `HotpathGuardBuilder` are mutually exclusive for a profiling lifetime.

## Helper Script

Generate starter snippets without loading extra context:

```bash
bash /mnt/skills/user/hotpath-rs/scripts/hotpath-rs-bootstrap.sh basic
bash /mnt/skills/user/hotpath-rs/scripts/hotpath-rs-bootstrap.sh tokio
bash /mnt/skills/user/hotpath-rs/scripts/hotpath-rs-bootstrap.sh data-flow
bash /mnt/skills/user/hotpath-rs/scripts/hotpath-rs-bootstrap.sh mcp
bash /mnt/skills/user/hotpath-rs/scripts/hotpath-rs-bootstrap.sh cpu
```

The script prints JSON with a `scenario`, `cargo`, `command`, and `snippet` field.
