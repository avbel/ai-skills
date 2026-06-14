---
name: rxrust-rust
description: Use when working with rxRust reactive programming in Rust — Observables, Local/Shared contexts, Subjects, schedulers, async interop with Tokio/smol, iterators, streams, and choosing Rx vs simpler primitives.
---

# rxRust Reactive Programming

Use these conventions for [`rxRust/rxRust`](https://github.com/rxRust/rxRust), the Rust ReactiveX implementation. Target the latest published release-candidate line unless the project pins something else.

## Source Baseline

- Current verified crate: `rxrust 1.0.0-rc.5`.
- Primary APIs: `Local`, `Shared`, `Observable`, `Subject`, `Subscription`, `from_iter`, `from_future`, `from_stream`, `into_future`, `into_stream`, scheduler operators.
- Use versioned docs for rc APIs: `https://docs.rs/rxrust/1.0.0-rc.5/rxrust/`.
- The guide at `https://rxrust.github.io/rxRust/latest/` is useful, but verify against crates.io/docs.rs because book examples can lag the latest rc.
- `docs.rs/rxrust/latest` points at the latest stable release, not necessarily the latest rc.

```toml
[dependencies]
rxrust = "1.0.0-rc.5"

# For async interop examples
futures = "0.3"
tokio = { version = "1", features = ["macros", "rt-multi-thread", "time"] }
```

## Mental Model

- `Observable` is push-based: producers emit `next`, `error`, and `complete` events to subscribers.
- `Iterator` and `Stream` are pull-based: consumers poll/ask for the next item.
- rxRust chains are lazy until `.subscribe(...)`, `.into_stream()`, or `.into_future()` subscribes.
- Operators consume and wrap the previous observable, like iterator adaptors; rely on type inference and use `box_it()` only at API/storage boundaries.
- A `Subscription` is explicit cancellation. Dropping a raw subscription does not guarantee RAII cancellation; call `.unsubscribe()` or hold the guard returned by `unsubscribe_when_dropped()`.

## When rxRust Is Excellent

Use rxRust when event orchestration is the problem:

- GUI/WASM/UI-main-thread events where `Local` avoids `Arc<Mutex<_>>` overhead.
- Typeahead/search/autosave flows: `debounce` → `distinct_until_changed` → `switch_map`.
- Multicast event buses with `Subject` / `BehaviorSubject` and multiple subscribers.
- Time/rate/window logic: `debounce`, `throttle_time`, `buffer_time`, `sample`, `delay`, `retry`.
- Combining independent event sources: `merge`, `zip`, `combine_latest`, `with_latest_from`.
- Cancellation as a first-class concept: unsubscribe cancels timers, current inner streams, and scheduled work.
- Converting pull sources (`Iterator`, `Stream`, `Future`) into push pipelines temporarily, then converting back.

## When rxRust Is a Bad Choice

Prefer simpler primitives when Rx is not buying real composition:

- One pass over local data: use `Iterator`.
- One async result: use `Future` / `async fn`.
- One producer and one consumer: use `tokio::sync::mpsc`, `async_channel`, or `crossbeam`.
- Database/file cursors and demand-driven APIs: use `Stream`; push observables have no natural backpressure contract.
- CPU-heavy data parallelism: use `rayon` or explicit worker pools.
- Library public APIs: expose `Future`/`Stream`/callbacks unless consumers already standardize on rxRust.
- Hard real-time or ultra-low-latency paths: avoid scheduler indirection and heap/type-erasure boundaries.
- Teams unfamiliar with Rx: reactive pipelines can hide control flow and error/completion behavior.
- Stable-only dependency policies: the v1 API is still release-candidate; pin exact rc and retest on upgrades.

## Context Selection

| Context | Use for | Backing strategy |
|---|---|---|
| `Local` | WASM, GUI threads, single-threaded event loops, `Rc`/DOM objects | `Rc` / `RefCell`, `!Send`, no locking |
| `Shared` | Tokio/server/background work, cross-thread streams | `Arc` / `Mutex`, `Send + Sync` |

Rules:

- Start with `Shared` if the stream may cross threads or use `SharedScheduler`.
- Do not create `Local` streams and then try to move them to thread-pool schedulers; Rust will reject `!Send` state.
- `Shared` enables thread safety; it does not automatically parallelize every operator. Use `observe_on`, `subscribe_on`, async sources, or schedulers intentionally.

## Iterators to Observables

Use `from_iter` for synchronous, finite sources. This is useful when you want Rx operators around an otherwise ordinary collection.

```rust
use rxrust::prelude::*;

fn main() {
    let mut seen = Vec::new();

    Local::from_iter(0..=5)
        .filter(|v| v % 2 == 0)
        .map(|v| v * 10)
        .subscribe(|v| seen.push(v));

    assert_eq!(seen, vec![0, 20, 40]);
}
```

Do not convert iterators to Observables just for `map/filter/collect`; stay with iterators unless you need multicast, scheduler, cancellation, or time-based operators.

## Subjects and Subscription Lifecycle

Use `Subject` for imperative event sources. Explicitly type subjects when inference is unclear.

```rust
use std::{cell::RefCell, convert::Infallible, rc::Rc};

use rxrust::prelude::*;

fn main() {
    let mut subject = Local::subject::<i32, Infallible>();
    let seen = Rc::new(RefCell::new(Vec::new()));
    let seen_in_subscriber = Rc::clone(&seen);

    let subscription = subject
        .clone()
        .map(|v| v * 2)
        .subscribe(move |v| seen_in_subscriber.borrow_mut().push(v));

    subject.next(1);
    subject.next(2);
    subscription.unsubscribe();
    subject.next(3);

    assert_eq!(*seen.borrow(), vec![2, 4]);
}
```

Patterns:

- Keep a `Subscription` or drop guard at the same lifecycle level as the UI component/task that owns the subscription.
- Prefer `BehaviorSubject` when new subscribers need the latest state immediately.
- Avoid global subjects as hidden mutable state; wrap them behind domain APIs.

## Tokio Integration

rxRust’s default `scheduler` feature uses Tokio-backed schedulers on native targets. For async/timer operators in a Tokio app, use `Shared` unless you intentionally run `Local` inside a current-thread local context.

### Stream → Observable → Stream

`from_stream` accepts a `futures_core::Stream`. `into_stream` yields `Result<T, E>` items and unsubscribes when the stream is dropped.

```rust
use futures::{StreamExt, stream};
use rxrust::prelude::*;

#[tokio::main]
async fn main() {
    let source = stream::iter([1, 2, 3, 4]);

    let mut stream = Shared::from_stream(source)
        .filter(|v| v % 2 == 0)
        .map(|v| v * 10)
        .into_stream();

    let mut seen = Vec::new();
    while let Some(item) = stream.next().await {
        seen.push(item.expect("from_stream is infallible"));
    }

    assert_eq!(seen, vec![20, 40]);
}
```

Use `_result` variants for fallible pull sources:

- `from_future_result(Future<Output = Result<T, E>>)` routes `Err(E)` to the observable error channel.
- `from_stream_result(Stream<Item = Result<T, E>>)` emits `Ok(T)` and terminates on `Err(E)`.

### Typeahead / Latest-Wins Work

Use `debounce` for quiet periods, `distinct_until_changed` for duplicate suppression, and `switch_map` when new input should cancel older in-flight work.

```rust
use std::{
    convert::Infallible,
    sync::{Arc, Mutex},
};

use rxrust::{prelude::*, scheduler::Duration};

#[tokio::main]
async fn main() {
    let mut input = Shared::subject::<String, Infallible>();
    let seen = Arc::new(Mutex::new(Vec::new()));
    let seen_in_subscriber = Arc::clone(&seen);

    let subscription = input
        .clone()
        .debounce(Duration::from_millis(25))
        .distinct_until_changed()
        .switch_map(|query| Shared::from_future(async move { format!("result:{query}") }))
        .subscribe(move |result| seen_in_subscriber.lock().unwrap().push(result));

    input.next("r".to_owned());
    input.next("rx".to_owned());
    input.next("rx".to_owned());
    input.next("rxrust".to_owned());

    tokio::time::sleep(Duration::from_millis(80)).await;
    subscription.unsubscribe();

    assert_eq!(&*seen.lock().unwrap(), &["result:rxrust".to_owned()]);
}
```

## smol / async-std / Other Runtime Integration

- Tokio is the built-in native scheduler path in the default feature set.
- smol/async-std can consume `into_stream()` for synchronous/local Observable sources because the returned type implements `futures_core::Stream`.
- Do not assume `timer`, `interval`, `debounce`, `from_future`, or `from_stream` are smol-native under the default scheduler; those scheduled tasks are Tokio-oriented unless you inject a custom scheduler.
- For non-Tokio applications, either keep rxRust at synchronous/local boundaries, bridge through a Tokio compatibility layer deliberately, or define aliases with `LocalCtx<T, MyScheduler>` / `SharedCtx<T, MyScheduler>` and implement the scheduler traits.

```rust
use futures_lite::StreamExt;
use rxrust::prelude::*;

fn main() {
    smol::block_on(async {
        let mut stream = Local::from_iter([1, 2, 3]).map(|v| v + 1).into_stream();

        let mut seen = Vec::new();
        while let Some(item) = stream.next().await {
            seen.push(item.expect("from_iter is infallible"));
        }

        assert_eq!(seen, vec![2, 3, 4]);
    });
}
```

## Futures and Single Values

- `from_future(fut)` emits the future output as one `next` value and completes.
- `from_future_result(fut)` uses the observable error channel for `Result::Err`.
- `into_future()` expects exactly one value and resolves as `Result<Result<T, E>, IntoFutureError>`:
  - `Ok(Ok(value))` — one value.
  - `Ok(Err(error))` — observable error.
  - `Err(IntoFutureError::Empty)` — no values.
  - `Err(IntoFutureError::MultipleValues)` — more than one value.
- Apply `.take(1)`, `.last()`, or a reducing operator before `.into_future()` when the source may emit multiple values.

## Scheduler Operators

- `observe_on(scheduler)` moves downstream observation from that point onward.
- `subscribe_on(scheduler)` moves subscription/source setup.
- `delay`, `debounce`, `throttle_time`, `timer`, and `interval` depend on the context scheduler.
- Prefer `_with` variants (`debounce_with`, `timer_with`, `from_stream_with`, etc.) only when you have a concrete scheduler reason.
- Use `TestScheduler` / virtual time for deterministic time-operator tests where available instead of sleeping in unit tests.

## Type and Ownership Pitfalls

| Pitfall | Fix |
|---|---|
| Choosing `Local` then needing thread-pool execution | Start with `Shared` and `Send` data |
| Capturing non-`Send` state in `Shared` pipelines | Use `Local`, or wrap in thread-safe types intentionally |
| Treating Observable as backpressured | Keep demand-driven parts as `Stream` or channels |
| Forgetting to keep/cancel subscriptions | Store `Subscription`, call `unsubscribe()`, or hold `unsubscribe_when_dropped()` guard |
| Returning huge concrete Observable types | Return `impl Observable` internally; use `box_it()` at branch/storage/API boundaries |
| Converting everything to Rx | Keep simple iterator/future/stream code simple |
| Trusting guide snippets blindly | Compile samples against pinned `rxrust` rc before adding them |

## Review Checklist

- [ ] Pinned `rxrust` version matches the project policy (`1.0.0-rc.5` for latest rc as of this skill).
- [ ] `Local` vs `Shared` choice matches thread movement and captured state.
- [ ] Push/pull boundary is explicit: `from_iter`, `from_stream`, `into_stream`, `from_future`, `into_future`.
- [ ] Async runtime assumptions are explicit; Tokio-backed scheduler is not silently used in smol/async-std code.
- [ ] Subscriptions are owned and cancelled at the correct lifecycle boundary.
- [ ] Time-based logic is tested deterministically where practical.
- [ ] `box_it()` is used only where type erasure is needed.
- [ ] All Rust code samples compile against the pinned crate.
