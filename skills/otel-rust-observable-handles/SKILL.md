---
name: otel-rust-observable-handles
description: Use when registering OpenTelemetry observable instruments (gauge, counter, up-down counter) in Rust with opentelemetry-sdk 0.27+. Dropping the handle returned by `.build()` unregisters the instrument and causes a monotonic memory leak in the SDK pipeline. This skill enforces the keep-alive pattern.
origin: project:sui-node-power-tools
---

# OpenTelemetry Rust observable-instrument handle leak

## The bug

In `opentelemetry-sdk` 0.27 through (at least) 0.31, calling `.build()` on
a meter's observable-instrument builder returns a handle. **Dropping the
handle calls `unregister()` on the pipeline**. The next `Pipeline::produce()`
cycle then re-allocates a new aggregator entry in
`Inserter::cached_aggregator`'s HashMap. Over hundreds of 30-second export
cycles this grows the HashMap without bound — a real, monotonic leak that
heap profilers attribute to `Pipeline::produce`.

This applies to **all** observable instruments, not just gauges:
- `u64_observable_gauge` / `f64_observable_gauge` / `i64_observable_gauge`
- `u64_observable_counter` / `f64_observable_counter`
- `i64_observable_up_down_counter` / `f64_observable_up_down_counter`

It does **not** apply to synchronous instruments (counter, histogram,
up-down counter) — those record values directly and own no
unregister-on-drop handle.

## Smell test

If you see code like this, it leaks:

```rust
// LEAK: handle is dropped at end of statement → unregister → next produce()
// cycle re-allocates the aggregator → HashMap grows forever.
meter
    .u64_observable_gauge("my.metric")
    .with_callback(move |obs| obs.observe(value(), &[]))
    .build();
```

The compiler does not warn. You need `#[must_use]` on the registration
function (see below) and code review to catch it.

## The fix

Collect handles into `Vec<Box<dyn std::any::Any>>` and bind them in `main()`
for the entire process lifetime:

```rust
/// Register observable instruments.
///
/// The returned handles **must be kept alive** for the entire process
/// lifetime. Dropping them unregisters the instruments and causes a
/// monotonic memory leak in the OTel SDK pipeline (Inserter::cached_aggregator
/// re-allocates an aggregator entry on every export cycle).
#[must_use]
pub fn register(meter: &Meter, state: Arc<AppState>) -> Vec<Box<dyn std::any::Any>> {
    let mut handles: Vec<Box<dyn std::any::Any>> = Vec::new();

    handles.push(Box::new(
        meter
            .u64_observable_gauge("rpc_node.status")
            .with_description("Operational status (0=unavailable, 1=degraded, 2=ok)")
            .with_callback({
                let state = state.clone();
                move |obs| obs.observe(state.status_code(), &[])
            })
            .build(),
    ));

    handles.push(Box::new(
        meter
            .u64_observable_gauge("rpc_node.epoch")
            .with_description("Current chain epoch")
            .with_callback({
                let state = state.clone();
                move |obs| obs.observe(state.epoch(), &[])
            })
            .build(),
    ));

    handles
}
```

In `main()`:

```rust
let telemetry = init_telemetry(&config)?;

// Bind for process lifetime. Underscore prefix prevents unused-variable
// warnings; the `_` is NOT `_` (which would drop immediately).
let _gauge_handles = telemetry::observer::register(&telemetry.metrics.meter, state.clone());

// ... run app ...

telemetry.shutdown(Duration::from_secs(5)).await;
// `_gauge_handles` drops here, AFTER provider shutdown — safe, no
// produce() cycle can fire against unregistered instruments.
drop(_gauge_handles);
```

## Critical details

1. **Bind to `_name`, not `_`.** `let _ = register(...)` drops immediately
   and reproduces the bug. Use `_gauge_handles` (any leading-underscore
   identifier).

2. **Drop AFTER `provider.shutdown()`**, not before. The shutdown call
   flushes a final export cycle; if handles are already dropped, that
   final cycle re-allocates the leaking aggregator entry one last time.

3. **Mark `register()` `#[must_use]`.** If a future refactor accidentally
   discards the return value, the compiler will flag it.

4. **Use `Vec<Box<dyn Any>>`, not a struct.** The handle types from
   `opentelemetry-sdk` are not part of the public API and change between
   versions; `dyn Any` decouples the registration site from version churn.
   You never call methods on the handles — only `Drop` matters.

5. **One vec per `register()` function is fine.** No need to thread it
   through multiple modules. If you have several observer modules
   (`observer::register`, `mem_observer::register_proc_gauges`, etc.),
   each returns its own `Vec` and `main` binds each to its own
   `_handles_<name>` variable.

## Verification

Without the fix, on a process that exports every 30s, expect ~30–100 MB
of net-retained heap growth per few hours — concentrated in
`Pipeline::produce` → `Inserter::cached_aggregator`.

Diagnose with `jeprof --base=first.heap last.heap` (differential mode,
not hotspot mode). Hotspot mode shows what allocates *most*; differential
shows what is allocated and *never freed* — that's the leak signal.

With the fix, jemalloc-allocated bytes attributable to `Pipeline::produce`
stay flat across multi-hour runs.

## Why differential heap profiling matters here

The leak is invisible in standard hotspot profiles because each
`produce()` cycle's allocation is tiny (one HashMap entry per dropped
gauge per cycle). The cumulative growth only shows up when you compare
two heap snapshots taken hours apart. If you only ever profile hotspots,
you will chase larger but bounded allocators (request handlers, caches)
and miss the actual unbounded growth.

## Found-in-the-wild example

`crates/rpc-node/src/telemetry/observer.rs::register` and
`crates/rpc-node/src/telemetry/mem_observer.rs::register_*` in the
sui-node-power-tools repo had 17 sites of this bug. All fixed in a
single commit (2d1b2ca, 2026-05-02). Symptom before the fix: jemalloc
RSS grew ~30 MB/hr against a stable workload; afterwards: flat over 5h
soak.

## Quick checklist when reviewing OTel code

- [ ] Every `.observable_*().build()` call site captures the return value.
- [ ] Capture target is a `Vec<Box<dyn Any>>` (or equivalent long-lived
      collection), not `let _ = ...`.
- [ ] Registration function returns the vec and is marked `#[must_use]`.
- [ ] In `main`, the bound name has a leading underscore but is **not**
      a bare `_` (which is a discard pattern, not a binding).
- [ ] The handles vec is dropped *after* `telemetry.shutdown()` returns.
- [ ] No instrument is built inside a callback or short-lived scope.
