---
name: tokio-stream-rust
description: Use when working with async streams in Tokio — StreamExt combinators, wrappers for Tokio types (ReceiverStream, LinesStream, interval), StreamMap, timeout/retry/throttle, and converting iterators to streams.
---

# Tokio-Stream Rust

Use these conventions for working with [`tokio-rs/tokio`](https://github.com/tokio-rs/tokio) `tokio-stream` crate. It provides stream utilities, wrappers for Tokio types, and the `StreamExt` trait for async iteration.

## Source Baseline

- Prefer released docs from `docs.rs/tokio-stream`, crates.io, and the matching GitHub release.
- Current stable: `tokio-stream 0.1.18`.
- This crate depends on `tokio` and `futures-core`.

## Cargo.toml

```toml
[dependencies]
tokio-stream = { version = "0.1", features = ["net"] }

# net feature enables: tokio-stream::wrappers::TcpListenerStream, UdpSocketStream, etc.
# Default features include: StreamExt, iter, once, empty, pending, stream_map
```

Feature flags:
- `net` — wrappers for `TcpListener`, `UdpSocket`, `UnixListener` (requires `tokio/net`).
- `io-util` — wrappers for `BufReader::lines` etc. (requires `tokio/io-util`).
- `fs` — wrappers for `ReadDirStream` (requires `tokio/fs`).
- `signal` — wrappers for `SignalStream` (requires `tokio/signal`).
- `sync` — wrappers for `WatchStream`, `BroadcastStream`, `ReceiverStream` (requires `tokio/sync`).
- `time` — `IntervalStream`, `timeout`, `throttle`, etc. (requires `tokio/time`).

Full features for most projects:
```toml
tokio-stream = { version = "0.1", features = ["net", "io-util", "sync", "time"] }
```

## Creating Streams

```rust
use tokio_stream::{self as stream, StreamExt};

// From an iterator
let mut s = stream::iter(vec![1, 2, 3]);
while let Some(val) = s.next().await { }

// From a range
let mut s = stream::iter(1..=10);

// Empty stream (yields nothing)
let mut s = stream::empty::<i32>();

// Once (yields one value)
let mut s = stream::once(42);

// Pending (never yields)
let mut s = stream::pending::<i32>();
```

## StreamExt — Combinators

`StreamExt` provides async combinators similar to `Iterator`:

```rust
use tokio_stream::{self as stream, StreamExt};

// Filter
let evens = stream::iter(1..=10).filter(|x| *x % 2 == 0);

// Map
let doubled = stream::iter(1..=10).map(|x| x * 2);

// Take first N
let first5 = stream::iter(1..=100).take(5);

// Skip first N
let skipped = stream::iter(1..=100).skip(10);

// Collect into Vec
let items: Vec<i32> = stream::iter(1..=10).collect().await;

// ForEach — process each item
stream::iter(1..=10).for_each(|x| async move {
    println!("{x}");
}).await;

// Fold into accumulator
let sum = stream::iter(1..=10)
    .fold(0, |acc, x| acc + x)
    .await;

// Merge two streams (interleave items as they become ready)
let merged = stream1.merge(stream2);

// Chain streams sequentially
let chained = stream1.chain(stream2);
```

## Wrappers — Tokio Types as Streams

```rust
use tokio_stream::wrappers::{
    ReceiverStream, BroadcastStream, WatchStream,
    IntervalStream, TcpListenerStream, LinesStream,
    ReadDirStream, SignalStream,
};

// mpsc::Receiver → Stream
let (tx, rx) = tokio::sync::mpsc::channel::<String>(100);
let mut stream = ReceiverStream::new(rx);
while let Some(msg) = stream.next().await {
    println!("msg: {msg}");
}

// broadcast::Receiver → Stream
let rx = tx.subscribe();
let mut stream = BroadcastStream::new(rx);

// watch::Receiver → Stream (yields on change)
let mut stream = WatchStream::new(watch_rx);
while let Some(value) = stream.next().await {
    println!("updated: {value:?}");
}

// interval → Stream
let mut interval = IntervalStream::new(tokio::time::interval(Duration::from_secs(1)));
while let Some(_) = interval.next().await {
    println!("tick");
}

// TcpListener → Stream of (TcpStream, SocketAddr)
let listener = TcpListener::bind("0.0.0.0:8080").await?;
let mut incoming = TcpListenerStream::new(listener);
while let Some(result) = incoming.next().await {
    let (socket, addr) = result?;
    tokio::spawn(handle(socket));
}

// BufReader::lines → Stream of lines
let reader = BufReader::new(file);
let mut lines = LinesStream::new(reader.lines());
while let Some(line) = lines.next().await {
    let line = line?;
    process(&line);
}

// read_dir → Stream of DirEntry
let mut entries = ReadDirStream::new(tokio::fs::read_dir(".").await?);
while let Some(entry) = entries.next().await {
    let entry = entry?;
    println!("{}", entry.path().display());
}
```

## StreamMap — Multiplex Streams by Key

```rust
use tokio_stream::{StreamMap, StreamExt};

let mut map: StreamMap<&str, impl Stream<Item = Event>> = StreamMap::new();
map.insert("tcp", tcp_stream);
map.insert("ws", ws_stream);

while let Some((key, event)) = map.next().await {
    match key {
        "tcp" => handle_tcp(event),
        "ws" => handle_ws(event),
        _ => {}
    }
}
```

- Each entry is identified by a key (`Hash + Eq + Clone`).
- `insert()` adds a stream; `remove()` removes one.
- Items from any ready stream are yielded with the key.

## Time-Based Combinators

```rust
use tokio_stream::StreamExt;
use std::time::Duration;

// Timeout each item
let mut stream = source_stream.timeout(Duration::from_secs(5));
while let Some(result) = stream.next().await {
    match result {
        Ok(item) => process(item),
        Err(_) => println!("timeout"),
    }
}

// Throttle — emit at most one item per duration
let throttled = source_stream.throttle(Duration::from_millis(100));

// Chunk — collect items into Vecs of up to N
let chunks = source_stream.chunks_timeout(100, Duration::from_secs(1));
// Yields Vec<Item> — either when 100 items collected or 1 second elapsed
```

## Cancel-Safe Streams

Most `tokio-stream` wrappers are cancel-safe:
- `ReceiverStream::next()` — safe (item stays in channel if not consumed).
- `BroadcastStream::next()` — may yield `Err(Lagged(n))`.
- `WatchStream::next()` — safe (only yields latest value).
- `IntervalStream::next()` — safe.

Non-cancel-safe patterns to avoid:
- `stream.read_exact()` on wrapped TCP streams — use `tokio::io::AsyncReadExt` directly.
- `try_for_each_concurrent()` (from `futures::StreamExt`) — items are dispatched before completion.

## Common Patterns

### Process Stream with Concurrency Limit

`buffer_unordered` comes from `futures::StreamExt`, not `tokio_stream::StreamExt` — add the `futures` crate for this pattern:

```rust
use futures::StreamExt;

let results = source_stream
    .map(|item| async { process(item).await })
    .buffer_unordered(10)  // up to 10 concurrent
    .collect::<Vec<_>>()
    .await;
```

### Graceful Shutdown Pattern

```rust
use tokio_stream::wrappers::WatchStream;
use tokio_stream::StreamExt;

let mut shutdown_stream = WatchStream::new(shutdown_rx);
tokio::select! {
    Some(()) = shutdown_stream.next() => {
        println!("shutting down");
    }
    result = do_work() => {
        println!("work completed: {result:?}");
    }
}
```

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Using `for` loop on a Stream | Use `while let Some(item) = stream.next().await` |
| Not importing `StreamExt` | `use tokio_stream::StreamExt;` is required for combinators |
| Blocking inside stream combinator | Use `tokio::spawn` or `spawn_blocking` for heavy work |
| `BroadcastStream::Lagged` errors | Increase channel capacity or handle `Err(Lagged)` explicitly |
| Not enabling needed features | Add `net`, `sync`, `time`, `io-util` features as needed |
| Mixing `futures::StreamExt` and `tokio_stream::StreamExt` | Pick one; they conflict if both are in scope |

## Review Checklist

- [ ] `tokio-stream` features match what's needed (`net`, `sync`, `time`, `io-util`, `fs`, `signal`).
- [ ] Tokio channel types wrapped with `ReceiverStream`, `BroadcastStream`, `WatchStream`.
- [ ] No `for` loop on streams — always `while let Some(...) = stream.next().await`.
- [ ] Time-based combinators (`timeout`, `throttle`, `chunks_timeout`) used for stream rate control.
- [ ] `StreamMap` used for multiplexing streams by key instead of manual `select!` chains.
- [ ] `BroadcastStream` `Lagged` errors handled, not silently dropped.