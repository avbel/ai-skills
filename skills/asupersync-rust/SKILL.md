---
name: asupersync-rust
description: Use when building or reviewing Rust with Asupersync/asupersync_rust: Cx, Scope, regions, Outcome, cancellation, two-phase channels, sync primitives, timers, lab tests, HTTP servers, or migrations from Tokio or smol.
---

# Asupersync Rust

Use these conventions for `Dicklesworthstone/asupersync`, a spec-first async runtime for Rust focused on structured concurrency, explicit capabilities, cancellation protocols, and deterministic testing.

## Source Baseline

- Prefer the upstream repository and matching docs over old snippets: `https://github.com/Dicklesworthstone/asupersync`.
- Baseline checked for this skill: upstream `main` at `bd6e0a3d`, package version `0.3.3`, Rust edition `2024`.
- Asupersync is a `0.x` crate and its own `src/lib.rs` says public items should be treated as unstable unless documented otherwise.
- Current core crate uses nightly-only Rust features such as `try_trait_v2`; do not present it as stable-toolchain drop-in code.
- Default builds include `proc-macros`; if default features are disabled, enable `proc-macros` for `scope!`, `spawn!`, `join!`, `join_all!`, and `race!`.

## When to Choose It

Choose Asupersync when correctness under cancellation matters more than ecosystem convenience:

- every task should be owned by a region and close to quiescence;
- cancellation must be observed, drained, and finalized rather than silently dropping futures;
- channel sends, locks, and request handlers need explicit cancel-safe protocols;
- concurrency bugs should be tested under deterministic scheduling or cancellation injection;
- application effects should flow through an explicit `Cx` capability context.

Do not treat Asupersync as a transparent Tokio executor replacement. Rewrite application seams around `&Cx`, region-owned tasks, `Outcome`, cancel-aware primitives, and deterministic tests.

## Install

For current upstream work, prefer the Git dependency until a release policy is clear:

```toml
[dependencies]
asupersync = { git = "https://github.com/Dicklesworthstone/asupersync" }
```

If you need the macro DSL with default features disabled:

```toml
[dependencies]
asupersync = { git = "https://github.com/Dicklesworthstone/asupersync", default-features = false, features = ["proc-macros"] }
```

Use optional features intentionally:

- `tracing-integration` for tracing hooks.
- `debug-server` for runtime inspection server support.
- `config-file` for TOML runtime configuration.
- `tls`, `tls-native-roots`, and `tls-webpki-roots` for native TLS.
- `sqlite`, `postgres`, `mysql`, and `kafka` only when the app needs those native integrations.
- `compression` for HTTP response compression.
- `test-internals` only for tests that need private helpers; never require it for production users.

## Mental Model

- `Cx` is the explicit capability and cancellation context. Thread `&Cx` through async APIs you own.
- `Scope` owns spawned work. Spawn into a scope or child region; avoid detached background work.
- Regions close to quiescence. When a region returns, its children have completed, cancelled, or drained.
- `Outcome<T, E>` is not just `Result<T, E>`. It distinguishes `Ok`, `Err`, `Cancelled`, and `Panicked`.
- Cancellation is a protocol: request, drain, finalize, complete.
- Cancel-safe effects use two phases: reserve first, then commit in a non-ambiguous step.
- Lab tests use deterministic scheduling, virtual time, traces, and cancellation injection.

## Comparison

| Need | Tokio | smol | Asupersync |
|---|---|---|---|
| Ecosystem compatibility | Best default for Rust services | Small runtime with async-io ecosystem | Narrower ecosystem; prefer native surfaces or explicit compat boundaries |
| Spawn | `tokio::spawn` can outlive caller unless joined/aborted | `smol::spawn` returns a task that can detach if ignored | spawned work is owned by a `Scope` or region |
| Cancellation model | dropping a future or aborting a task is conventional | dropping a future is cancellation | cancellation is request -> drain -> finalize with `Cx` checkpoints |
| Channel send | `send().await` is common; cancellation safety depends on primitive | normal async channel conventions | `reserve(&cx).await` then `permit.send(value)` |
| Time | ambient Tokio timer | smol/async-io timers | explicit time primitives, virtual-time friendly |
| Testing schedules | mostly nondeterministic without extra tools | mostly nondeterministic without extra tools | lab runtime supports deterministic scheduling and injection |
| Best fit | production web stacks and library compatibility | lightweight async apps | systems where cancellation, cleanup, and reproducibility are core requirements |

Migration rule: move from Tokio or smol only when you are willing to change the application model, not just the runtime attribute.

## Basic Operations

### Runtime Bootstrap

```rust
use asupersync::runtime::RuntimeBuilder;

fn main() -> Result<(), asupersync::Error> {
    let runtime = RuntimeBuilder::current_thread().build()?;

    runtime.block_on(async {
        println!("running on Asupersync");
    });

    Ok(())
}
```

Common builders:

- `RuntimeBuilder::new()` for normal defaults.
- `RuntimeBuilder::current_thread()` for deterministic tests and small demos.
- `RuntimeBuilder::high_throughput()` plus `blocking_threads(min, max)` for server-heavy workloads.
- `RuntimeBuilder::low_latency()` plus lower `poll_budget(...)` for fairness-sensitive workloads.

### Context and Outcomes

```rust
use asupersync::{Cx, Outcome};

async fn do_work(cx: &Cx) -> Outcome<&'static str, &'static str> {
    if let Err(reason) = cx.checkpoint() {
        return Outcome::cancelled(reason);
    }

    Outcome::ok("done")
}
```

Use `Outcome` at concurrency boundaries. Convert to local `Result` only at edges that genuinely cannot represent cancellation or panic separately.

### Spawn Owned Work

Use a scope or explicit child region. The exact manual API is more authoritative than the macro DSL while Asupersync is still moving.

```rust
use asupersync::{Cx, Outcome, Scope};
use asupersync::runtime::RuntimeState;

async fn parent(scope: &Scope<'_>, state: &mut RuntimeState, cx: &Cx) -> Outcome<(), String> {
    let handle = match scope.spawn(state, cx, |task_cx| async move {
        task_cx.checkpoint()?;
        Outcome::<i32, String>::ok(42)
    }) {
        Ok(handle) => handle,
        Err(err) => return Outcome::err(err.to_string()),
    };

    match handle.join(cx).await {
        Ok(value) => {
            let _ = value;
            Outcome::ok(())
        }
        Err(err) => Outcome::err(err.to_string()),
    }
}
```

Do not drop handles casually. If the work matters, join it or make the region responsible for draining it.

### Channels

Use reserve/commit for sends. This is one of the main differences from Tokio and smol.

```rust
use asupersync::{Cx, Outcome, channel::mpsc};

async fn send_one(cx: &Cx) -> Result<(), String> {
    let (tx, mut rx) = mpsc::channel::<String>(16);

    let permit = tx.reserve(cx).await.map_err(|err| err.to_string())?;
    match permit.send("hello".to_owned()) {
        Outcome::Ok(()) => {}
        Outcome::Err(err) => return Err(err.to_string()),
        Outcome::Cancelled(reason) => return Err(reason.to_string()),
        Outcome::Panicked(payload) => return Err(payload.to_string()),
    }

    let message = rx.recv(cx).await.map_err(|err| err.to_string())?;
    assert_eq!(message, "hello");

    Ok(())
}
```

Rules:

- Await `reserve(&cx)` before committing a send.
- Treat a dropped permit as an abort, not as a partial send.
- Surface `Disconnected`, `Cancelled`, and `Full` distinctly when the caller can act differently.

### Locks and Semaphores

```rust
use asupersync::sync::Mutex;

async fn increment(cx: &asupersync::Cx, counter: &Mutex<u64>) -> Result<(), String> {
    let mut guard = counter.lock(cx).await.map_err(|err| err.to_string())?;
    *guard += 1;
    Ok(())
}
```

Rules:

- Prefer `Mutex::with_name("domain", value)` for lock-order diagnostics.
- Do not hold non-Asupersync blocking locks across `.await`.
- Treat lock acquisition errors as real control flow: cancelled, timed out, poisoned, or already completed.

### Time

```rust
use asupersync::time::{sleep, timeout, wall_now};
use std::future::Future;
use std::time::Duration;

async fn retry_delay() {
    sleep(wall_now(), Duration::from_millis(50)).await;
}

async fn bounded<T>(future: impl Future<Output = T>) -> Result<T, asupersync::time::Elapsed> {
    timeout(wall_now(), Duration::from_secs(2), future).await
}
```

Use Asupersync time helpers rather than ambient Tokio or smol timers. They are designed to compose with virtual time in lab tests.

### Race and Join

- Use `Scope::race` when loser tasks must be cancelled and drained correctly.
- Be cautious with `race!`: current macro docs say losers are dropped, not drained.
- Current `join!` and `join_all!` macro docs say they await sequentially today; do not use them to claim parallel polling.
- For critical orchestration, prefer explicit scope APIs until macro semantics stabilize.

## Cancellation Rules

Cancellation bugs are usually caused by pretending `drop` is cleanup. In Asupersync, write cancellation as visible protocol.

Checklist:

- Call `cx.checkpoint()?` in loops, retry bodies, long handlers, and shutdown-sensitive work.
- Never commit half an effect before an `.await`. Reserve first, then commit.
- If an operation owns an external side effect, register cleanup/finalizer behavior or use an RAII obligation type.
- Preserve resume state before acknowledging cancellation in durable workflows.
- Return `Outcome::Cancelled(reason)` instead of hiding cancellation inside a generic error.
- For HTTP, map pre-handler request cancellation to `499 Client Closed Request`.
- If cancellation races after a handler produced a response, keep the completed response. Dropping it silently loses committed work.

Bad pattern:

```text
await side_effect_that_commits_external_state
await maybe_send_notification
check cancellation only after the work is already committed
```

Better pattern:

```rust
async fn better(
    cx: &asupersync::Cx,
    tx: asupersync::channel::mpsc::Sender<String>,
) -> asupersync::Outcome<(), String> {
    use asupersync::Outcome;

    cx.checkpoint()?;

    let permit = match tx.reserve(cx).await {
        Ok(permit) => permit,
        Err(err) => return Outcome::err(err.to_string()),
    };

    if let Err(err) = perform_cancel_safe_step(cx).await {
        return Outcome::err(err.to_string());
    }

    match permit.send("done".to_owned()) {
        Outcome::Ok(()) => Outcome::ok(()),
        Outcome::Err(err) => Outcome::err(err.to_string()),
        Outcome::Cancelled(reason) => Outcome::cancelled(reason),
        Outcome::Panicked(payload) => Outcome::panicked(payload),
    }
}
```

## HTTP Server Demo

This is a native HTTP/1 listener demo that routes through `web::Router`. Keep it as an orientation example and verify against the installed Asupersync version because the crate is still `0.x`.

```toml
[package]
name = "asupersync-http-demo"
version = "0.1.0"
edition = "2024"

[dependencies]
asupersync = { git = "https://github.com/Dicklesworthstone/asupersync" }
```

```rust
use asupersync::http::h1::listener::{Http1Listener, Http1ListenerConfig};
use asupersync::http::h1::server::{HostPolicy, Http1Config};
use asupersync::http::h1::types::{Request as H1Request, Response as H1Response, default_reason};
use asupersync::runtime::RuntimeBuilder;
use asupersync::web::extract::Request as WebRequest;
use asupersync::web::handler::{FnHandler, FnHandler1};
use asupersync::web::response::{Json, StatusCode};
use asupersync::web::router::{Router, get, post};
use std::sync::Arc;
use std::time::Duration;

fn health() -> &'static str {
    "ok"
}

fn create_item(
    asupersync::web::extract::Json(mut body): asupersync::web::extract::Json<serde_json::Value>,
) -> (StatusCode, Json<serde_json::Value>) {
    body["id"] = serde_json::json!(42);
    (StatusCode::CREATED, Json(body))
}

fn to_web_request(req: H1Request) -> WebRequest {
    let mut web = WebRequest::new(req.method.as_str(), req.uri);
    for (name, value) in req.headers {
        web = web.with_header(name, value);
    }
    web.with_body(req.body)
}

fn to_h1_response(resp: asupersync::web::response::Response) -> H1Response {
    let status = resp.status.as_u16();
    let mut out = H1Response::new(status, default_reason(status), resp.body.as_ref().to_vec());
    for (name, value) in resp.headers {
        out = out.with_header(name, value);
    }
    for cookie in resp.set_cookies {
        out = out.with_header("set-cookie", cookie);
    }
    out
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let runtime = RuntimeBuilder::high_throughput()
        .blocking_threads(2, 16)
        .build()?;
    let handle = runtime.handle();

    runtime.block_on(async move {
        let router = Arc::new(
            Router::new()
                .route("/health", get(FnHandler::new(health)))
                .route(
                    "/items",
                    post(FnHandler1::<
                        _,
                        asupersync::web::extract::Json<serde_json::Value>,
                    >::new(create_item)),
                ),
        );

        let http_config = Http1Config::default()
            .host_policy(HostPolicy::allow_list(vec!["127.0.0.1".to_owned(), "localhost".to_owned()]));

        let listener_config = Http1ListenerConfig::default()
            .http_config(http_config)
            .max_connections(Some(1024))
            .drain_timeout(Duration::from_secs(10));

        let listener = Http1Listener::bind_with_config(
            "127.0.0.1:8080",
            move |req| {
                let router = Arc::clone(&router);
                async move { to_h1_response(router.handle(to_web_request(req))) }
            },
            listener_config,
        )
        .await?;

        println!("listening on {}", listener.local_addr()?);
        listener.run(&handle).await?;
        Ok::<_, std::io::Error>(())
    })?;

    Ok(())
}
```

HTTP rules:

- Use `Http1Config::host_policy(HostPolicy::AllowList(...))` for non-test servers. `AllowAll` is explicitly insecure legacy compatibility.
- Bound request bodies, headers, max connections, and drain timeout.
- Put each request in a `RequestRegion` when writing lower-level handlers directly.
- Convert cancellation to `499` only when the request was cancelled before handler output committed.
- Preserve completed responses when cancellation races after completion.

## Deterministic Tests

Use the lab runtime for cancellation-sensitive code.

```rust
use asupersync::{LabConfig, LabRuntime};

#[test]
fn lab_reaches_quiescence() {
    let mut lab = LabRuntime::new(LabConfig::new(42));
    let report = lab.run_until_quiescent_with_report();

    assert!(report.oracle_report.all_passed());
    assert!(report.invariant_violations.is_empty());
}
```

For systematic cancellation injection, use the upstream lab APIs when available in the selected version:

```rust
use asupersync::lab::{InjectionStrategy, InstrumentedFuture, lab};

#[test]
fn operation_is_cancel_safe() {
    let report = lab(42)
        .with_cancellation_injection(InjectionStrategy::AllPoints)
        .with_all_oracles()
        .run(|injector| InstrumentedFuture::new(my_async_operation(), injector));

    assert!(report.all_passed(), "{report}");
}
```

## Migration From Tokio Or smol

1. Inventory `tokio`, `tokio-util`, `hyper`, `axum`, `tonic`, `reqwest`, `async-std`, `smol`, `async-channel`, and executor-specific I/O traits.
2. Replace top-level runtime bootstrap with `RuntimeBuilder`.
3. Thread `&Cx` through app-owned async APIs.
4. Replace detached spawns with scope-owned spawns or child regions.
5. Replace channels with two-phase Asupersync channels.
6. Replace timers and timeouts with Asupersync time primitives.
7. Replace request boundaries with `RequestRegion` or native web/gRPC surfaces.
8. Keep unavoidable Tokio-locked libraries behind `asupersync-tokio-compat` or an adapter module.
9. Add lab tests for cancellation, shutdown, and resource cleanup.
10. Remove compat once no core application logic depends on Tokio or smol semantics.

## Anti-Patterns

- `#[tokio::main]` plus Asupersync primitives in the same binary.
- Calling async functions without awaiting, spawning, or region-owning them.
- Using `tokio::spawn`, `smol::spawn`, or fire-and-forget tasks in core Asupersync code.
- Hiding cancellation as `Err(anyhow!("cancelled"))`.
- Using `race!` when loser cleanup or drain matters.
- Performing side effects before a cancel checkpoint and then awaiting before recording durable state.
- Using `Cx::for_testing()` in production code.
- Using `HostPolicy::AllowAll` outside a deliberate compatibility test.

## Helper Script

Generate starter snippets without loading extra context:

```bash
bash /mnt/skills/user/asupersync-rust/scripts/asupersync-rust-bootstrap.sh runtime
bash /mnt/skills/user/asupersync-rust/scripts/asupersync-rust-bootstrap.sh channel
bash /mnt/skills/user/asupersync-rust/scripts/asupersync-rust-bootstrap.sh http
bash /mnt/skills/user/asupersync-rust/scripts/asupersync-rust-bootstrap.sh test
```

The script prints JSON with `scenario`, `cargo`, and `snippet` fields.

## Review Checklist

- Is `&Cx` explicit at async APIs that perform runtime effects?
- Is every spawned task owned by a scope or region?
- Are cancellation checkpoints present in loops, long handlers, retry paths, and shutdown-sensitive code?
- Are sends and other side effects split into reserve/commit or guarded by durable state?
- Are `Outcome::Cancelled` and `Outcome::Panicked` preserved instead of collapsed into generic errors?
- Are HTTP requests bounded by host policy, body/header limits, connection limits, and graceful drain?
- Are cancellation-sensitive paths covered by lab tests or deterministic replay?
- Is any Tokio or smol dependency quarantined behind an adapter instead of leaking into core code?

## Sources

- `https://github.com/Dicklesworthstone/asupersync`
- `https://github.com/Dicklesworthstone/asupersync/blob/main/README.md`
- `https://github.com/Dicklesworthstone/asupersync/blob/main/docs/integration.md`
- `https://github.com/Dicklesworthstone/asupersync/blob/main/docs/macro-dsl.md`
- `https://github.com/Dicklesworthstone/asupersync/blob/main/docs/cancellation-testing.md`
- `https://github.com/Dicklesworthstone/asupersync/blob/main/src/http/h1/listener.rs`
- `https://github.com/Dicklesworthstone/asupersync/blob/main/src/web/request_region.rs`
