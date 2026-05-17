---
name: futures-util-rust
description: Use when working with async combinators from futures-util — StreamExt, FutureExt, TryFutureExt, TryStreamExt, select!, join, sink, and async I/O adapters. Covers the essential subset of futures-util for real projects.
---

# Futures-Util Rust

Use these conventions for working with [`rust-lang/futures`](https://github.com/rust-lang/futures) `futures-util` crate. It provides combinators and utilities for `Future`s, `Stream`s, `Sink`s, and async I/O traits.

## Source Baseline

- Prefer released docs from `docs.rs/futures-util`, crates.io, and the matching GitHub release.
- Current stable: `futures-util 0.3.32`.
- Part of the `futures` ecosystem (`futures-core`, `futures-util`, `futures-executor`, `futures-channel`, `futures-sink`).

## Cargo.toml

```toml
[dependencies]
# Minimal: just the combinators you need
futures-util = "0.3"

# Common feature selections:
# For StreamExt, FutureExt, select!, join, SinkExt
futures-util = { version = "0.3", features = ["std"] }

# For async I/O (AsyncRead, AsyncWrite, AsyncBufRead, AsyncSeek)
futures-util = { version = "0.3", features = ["std", "io"] }

# For sink combinators
futures-util = { version = "0.3", features = ["std", "sink"] }

# For select! and join macros
futures-util = { version = "0.3", features = ["std", "async-await"] }

# Full (all features)
futures-util = { version = "0.3", features = ["std", "async-await", "io", "sink", "compat"] }
```

The `std` feature (enabled by default) provides `StreamExt`, `FutureExt`, etc. Without it, only `core` traits are available.

## Key Imports

```rust
// Most commonly used
use futures_util::{StreamExt, FutureExt, TryStreamExt, TryFutureExt};
use futures_util::stream::{self, Stream, FuturesUnordered};
use futures_util::sink::SinkExt;
use futures_util::future::{join, select, try_join, select_all};
```

## FutureExt — Combinators on Future

```rust
use futures_util::FutureExt;

// Map the output of a future
let result = async { 42 }.map(|x| x * 2).await;

// Inspect without modifying
let result = async { 42 }
    .inspect(|&x| println!("got: {x}"))
    .await;

// Then chain — sequentially
let result = async { 1 }
    .then(|x| async move { x + 1 })
    .await;
```

## TryFutureExt — Combinators on Result-Returning Futures

```rust
use futures_util::TryFutureExt;

// Map the Ok value
let result = async { Ok::<_, Error>(42) }
    .map_ok(|x| x * 2)
    .await;

// Map the Err value
let result = async { Err::<i32, Error>(Error::NotFound) }
    .map_err(|e| format!("failed: {e}"))
    .await;

// And_then — chain fallible futures sequentially
let result = fetch_user(id)
    .and_then(|user| fetch_permissions(&user))
    .await;

// Or_else — handle error by trying an alternative
let result = primary_db.get(key)
    .or_else(|_| fallback_db.get(key))
    .await;
```

## StreamExt — Combinators on Stream

```rust
use futures_util::StreamExt;

// Consume a stream
while let Some(item) = stream.next().await {
    process(item);
}

// Transform items
let doubled = stream.map(|x| x * 2);

// Filter items
let evens = stream.filter(|x| futures::future::ready(x % 2 == 0));

// Take first N
let first_ten = stream.take(10);

// Collect into Vec
let items: Vec<i32> = stream.collect().await;

// ForEach — process each item
stream.for_each(|item| async move {
    process(item);
}).await;

// TryForEach — fallible processing
stream.try_for_each(|item| async move {
    process(item).await
}).await?;

// Fold into accumulator
let sum = stream.fold(0, |acc, x| async move { acc + x }).await;

// Buffer up to N concurrent futures
stream.buffer_unordered(10)  // process up to 10 items concurrently
    .for_each(|result| async move { handle(result); })
    .await;

// FuturesUnordered — collect futures, poll concurrently
use futures_util::stream::FuturesUnordered;
let mut futs = FuturesUnordered::new();
futs.push(future1());
futs.push(future2());
while let Some(result) = futs.next().await {
    handle(result);
}
```

## TryStreamExt — Fallible Stream Combinators

```rust
use futures_util::TryStreamExt;

// Map Ok items in a fallible stream
let names = db_stream.map_ok(|row| row.name);

// TryFilter — filter items that may fail
let valid = stream.try_filter(|x| async move { x.is_valid() });

// TryCollect — collect a TryStream into a Result<Vec>
let items: Result<Vec<Row>, Error> = stream.try_collect().await;

// TryForEachConcurrent — process fallible stream items concurrently
stream.try_for_each_concurrent(10, |item| async move {
    process(item).await
}).await?;
```

## SinkExt — Writing to Sinks

```rust
use futures_util::sink::SinkExt;
use futures_util::stream::StreamExt;

// Send items to a sink
sink.send(item).await?;
sink.flush().await?;
sink.close().await?;

// Send all items from a stream to a sink
stream.forward(&mut sink).await?;
```

## Join and Select — Concurrency

```rust
use futures_util::future::{join, join3, join4, join5};
use futures_util::future::{try_join, try_join3};

// Join: run futures concurrently, wait for all
let (a, b, c) = join3(fut_a(), fut_b(), fut_c()).await;

// TryJoin: same, but short-circuits on first error
let (a, b, c) = try_join3(fallible_a(), fallible_b(), fallible_c()).await?;

// Select: race two futures, return first to complete
use futures_util::future::select;
match select(fut_a(), fut_b()).await {
    Either::Left((result, remaining_b)) => { /* a won */ },
    Either::Right((result, remaining_a)) => { /* b won */ },
}

// SelectAll: race many futures
use futures_util::future::select_all;
let (result, _index, _remaining) = select_all(vec![fut1(), fut2(), fut3()]).await;
```

## Async I/O Adapters

```rust
use futures_util::io::{AsyncReadExt, AsyncWriteExt, AsyncBufReadExt};

// Read
let mut buf = vec![0u8; 1024];
let n = reader.read(&mut buf).await?;

// Write
writer.write_all(b"hello").await?;
writer.close().await?;

// Read lines
let mut lines = BufReader::new(reader).lines();
while let Some(line) = lines.next().await {
    let line = line?;
    process(&line);
}

// Copy
futures_util::io::copy(&mut reader, &mut writer).await?;
```

Note: `futures-util` async I/O uses the `futures` 0.3 `AsyncRead/AsyncWrite` traits, **not** the `tokio` versions. Use `futures_util::compat` to bridge between them.

## Compat — Bridging futures and tokio

```rust
use futures_util::compat::Future01CompatExt;
use futures_util::compat::Stream01CompatExt;

// Convert a futures 0.3 future to a tokio-compatible one
// Requires the "compat" feature
```

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Using `for` loop on a Stream | Use `while let Some(item) = stream.next().await` |
| Not `.await`ing a stream combinator | Most combinators return a new Stream; `.collect().await` or `.for_each().await` to drive |
| Blocking inside an async combinator | Use `spawn_blocking` for CPU work; keep combinator closures async |
| `join` instead of `try_join` for fallible | Use `try_join` to short-circuit on first `Err` |
| `select` dropping the loser silently | Handle `Either::Left`/`Right` and the remaining future |
| Mixing tokio and futures async traits | Use `tokio_util::compat` or `futures_util::compat` to bridge |

## Review Checklist

- [ ] `futures-util` features only include what's needed (`std`, `io`, `sink`, `async-await`).
- [ ] Streams consumed with `while let Some(...) = stream.next().await` or `.for_each()`.
- [ ] `try_join` / `try_for_each` used for fallible operations (not `join` / `for_each`).
- [ ] No blocking inside async combinators; `spawn_blocking` used for CPU work.
- [ ] Async I/O traits are consistent (`futures` vs `tokio`) — compat layer used if mixed.