---
name: tokio-rust
description: Tokio async runtime conventions — runtime setup, task spawning, channels (mpsc/oneshot/broadcast/watch), synchronization primitives, async I/O, select!, streams, framing, timers, graceful shutdown, and bridging sync/async. Use when writing or modifying async Rust code that uses the tokio runtime.
---

Apply these conventions when working with Tokio in Rust projects.

## Cargo.toml

```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
# Or pick features: rt, rt-multi-thread, macros, net, io-util, sync, signal, time, fs
# "full" includes everything EXCEPT test-util and tracing

# Streams
tokio-stream = "0.1"
# Framing/codecs
tokio-util = { version = "0.7", features = ["codec"] }

[dev-dependencies]
tokio = { version = "1", features = ["full", "test-util"] }
```

## Runtime Setup

```rust
// Multi-thread (default, work-stealing, all CPU cores)
#[tokio::main]
async fn main() { }

// Explicit workers
#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() { }

// Single-thread (lightweight clients, WASM, tests)
#[tokio::main(flavor = "current_thread")]
async fn main() { }

// Manual builder (for libraries, bridging sync→async)
let rt = tokio::runtime::Builder::new_multi_thread()
    .worker_threads(4)
    .enable_all()
    .build()
    .unwrap();
rt.block_on(async { /* ... */ });
```

## Task Spawning

```rust
// spawn — requires Send + 'static
let handle: JoinHandle<i32> = tokio::spawn(async move { 42 });
let result = handle.await.unwrap();

// spawn_blocking — for CPU-heavy or blocking I/O
let result = tokio::task::spawn_blocking(|| {
    std::fs::read_to_string("big_file.txt")
}).await.unwrap();

// JoinSet — manage groups of tasks
let mut set = JoinSet::new();
for i in 0..10 {
    set.spawn(async move { i * 2 });
}
while let Some(res) = set.join_next().await {
    let val = res.unwrap();
}

// spawn_local — for !Send futures (requires LocalSet)
let local = tokio::task::LocalSet::new();
local.run_until(async {
    tokio::task::spawn_local(async { /* !Send OK */ }).await.unwrap();
}).await;

// yield_now — cooperatively yield to scheduler
tokio::task::yield_now().await;

// Abort a task
handle.abort();
```

## Shared State

**`std::sync::Mutex` vs `tokio::sync::Mutex`:**

| | `std::sync::Mutex` | `tokio::sync::Mutex` |
|---|---|---|
| Hold across `.await` | NO — deadlocks | YES |
| Performance | Faster | Slower (async overhead) |
| Use when | Quick sync data access, no `.await` in critical section | Must hold lock across `.await` points |

```rust
// std::sync::Mutex — brief lock, no .await inside
let data = Arc::new(std::sync::Mutex::new(vec![]));
{ data.lock().unwrap().push(42); } // drop before .await

// tokio::sync::Mutex — lock held across .await
let db = Arc::new(tokio::sync::Mutex::new(conn));
let mut c = db.lock().await;
c.query("SELECT ...").await; // OK
```

For high contention, consider sharding or `dashmap`.

## Channels

**mpsc — multi-producer, single-consumer:**
```rust
let (tx, mut rx) = mpsc::channel::<String>(100); // bounded, backpressure
let tx2 = tx.clone();
tx.send("msg").await.unwrap();
while let Some(msg) = rx.recv().await { } // None when all senders dropped
```
Unbounded: `mpsc::unbounded_channel()` — `send()` is sync, no backpressure.

**oneshot — single value, single use:**
```rust
let (tx, rx) = oneshot::channel::<String>();
tx.send("result".into()).unwrap(); // send is NOT async
let val = rx.await.unwrap();
```
Common: embed in request struct for request/response pattern.

**broadcast — all receivers get every message:**
```rust
let (tx, mut rx1) = broadcast::channel::<i32>(16);
let mut rx2 = tx.subscribe();
tx.send(10).unwrap();
// Both rx1 and rx2 receive 10. T: Clone required.
// Late subscribers miss earlier messages. Lagged receivers get RecvError::Lagged(n).
```

**watch — latest value only:**
```rust
let (tx, mut rx) = watch::channel("initial");
tx.send("updated").unwrap();
println!("{}", *rx.borrow());     // borrow current value (no clone)
rx.changed().await.unwrap();      // wait for new value
```
Great for config changes, shutdown signals.

## Synchronization Primitives

```rust
// RwLock — multiple readers OR one writer
let lock = RwLock::new(5);
{ let r = lock.read().await; }
{ let mut w = lock.write().await; *w += 1; }

// Semaphore — limit concurrent access to N
let sem = Arc::new(Semaphore::new(5));
let _permit = sem.acquire().await.unwrap(); // released on drop

// Notify — wake tasks (no data)
let notify = Arc::new(Notify::new());
notify.notify_one();              // wake one waiter
notify.notify_waiters();          // wake ALL
// In another task: notify.notified().await;
```

## Async I/O

```rust
use tokio::io::{AsyncReadExt, AsyncWriteExt};

reader.read(&mut buf).await?;
reader.read_exact(&mut buf).await?;
reader.read_to_end(&mut vec).await?;
writer.write_all(&buf).await?;
writer.flush().await?;

// Copy between streams
tokio::io::copy(&mut reader, &mut writer).await?;

// Buffered reading
use tokio::io::{BufReader, AsyncBufReadExt};
let reader = BufReader::new(file);
let mut lines = reader.lines();
while let Some(line) = lines.next_line().await? { }
```

## Framing (tokio-util::codec)

```rust
use tokio_util::codec::{Framed, LinesCodec, LengthDelimitedCodec};
use futures::{SinkExt, StreamExt};

// Line-delimited
let framed = Framed::new(tcp_stream, LinesCodec::new());
// Stream<Item=Result<String>> + Sink<String>

// Length-delimited (4-byte BE prefix)
let framed = Framed::new(tcp_stream, LengthDelimitedCodec::new());
```

Custom codec: implement `Decoder` (decode `BytesMut → Option<Frame>`) and `Encoder` (encode `Frame → BytesMut`).

## select! Macro

Waits on multiple futures, executes first to complete. **Others are cancelled (dropped).**

```rust
tokio::select! {
    val = rx.recv() => println!("{:?}", val),
    _ = tokio::time::sleep(Duration::from_secs(5)) => println!("timeout"),
}

// In a loop
loop {
    tokio::select! {
        Some(msg) = rx.recv() => handle(msg),
        _ = shutdown.changed() => break,
    }
}

// Preconditions
tokio::select! {
    val = rx.recv(), if enabled => { }
    else => { break; }
}

// Biased (poll in written order)
tokio::select! {
    biased;
    _ = high_priority() => {}
    _ = low_priority() => {}
}
```

**Cancel-safe** (OK in select loops): `mpsc::recv`, `broadcast::recv`, `watch::changed`, `TcpListener::accept`, `read`, `StreamExt::next`.
**NOT cancel-safe** (data loss risk): `read_exact`, `read_to_end`, `io::copy`. Mitigation: wrap in `tokio::spawn` and select on the `JoinHandle`.

## Streams

```rust
use tokio_stream::{self as stream, StreamExt};

let mut s = stream::iter(vec![1, 2, 3]);
while let Some(val) = s.next().await { }

// Adapters
let s = stream::iter(1..=10).filter(|x| x % 2 == 0).map(|x| x * 10).take(3);

// From channel
use tokio_stream::wrappers::ReceiverStream;
let stream = ReceiverStream::new(rx);

// In select! (must pin)
tokio::pin!(stream);
tokio::select! {
    Some(val) = stream.next() => { }
    _ = other_future() => { }
}
```

## Timers

```rust
// Sleep
tokio::time::sleep(Duration::from_millis(100)).await;

// Timeout
match tokio::time::timeout(Duration::from_secs(5), op()).await {
    Ok(result) => { }
    Err(_) => { /* timed out */ }
}

// Interval
let mut ticker = tokio::time::interval(Duration::from_secs(1));
ticker.set_missed_tick_behavior(MissedTickBehavior::Skip); // or Burst (default), Delay
loop { ticker.tick().await; do_work().await; }
```

## Networking

```rust
// TCP server
let listener = TcpListener::bind("127.0.0.1:8080").await?;
loop {
    let (socket, addr) = listener.accept().await?;
    tokio::spawn(async move { handle(socket).await; });
}

// TCP client
let stream = TcpStream::connect("127.0.0.1:8080").await?;

// UDP
let sock = UdpSocket::bind("0.0.0.0:8080").await?;
sock.send_to(b"hello", "127.0.0.1:9090").await?;
```

## Filesystem (tokio::fs)

Runs on `spawn_blocking` internally (non-blocking to the runtime).

```rust
let text = tokio::fs::read_to_string("path.txt").await?;
tokio::fs::write("path.txt", b"data").await?;
tokio::fs::create_dir_all("a/b/c").await?;
tokio::fs::remove_file("path.txt").await?;
```

## Signal Handling

```rust
// Ctrl+C (cross-platform)
tokio::signal::ctrl_c().await?;

// Unix signals
use tokio::signal::unix::{signal, SignalKind};
let mut sigterm = signal(SignalKind::terminate())?;
sigterm.recv().await;
```

## Graceful Shutdown

```rust
// Pattern: watch channel + ctrl_c
let (shutdown_tx, shutdown_rx) = watch::channel(false);

// Workers select on shutdown_rx.changed()
// Main waits for ctrl_c, then sends true

// Alternative: CancellationToken (tokio-util)
use tokio_util::sync::CancellationToken;
let token = CancellationToken::new();
let child = token.child_token();
// In task: select! { _ = child.cancelled() => break, ... }
// Trigger: token.cancel();
```

## Bridging Sync ↔ Async

```rust
// Sync → Async: block_on (from outside runtime)
let rt = tokio::runtime::Runtime::new().unwrap();
rt.block_on(async { do_async().await });

// Async → Sync: spawn_blocking
let result = tokio::task::spawn_blocking(|| sync_work()).await.unwrap();

// Sync sending into async channel
tx.blocking_send(value).unwrap(); // blocks the thread, safe from spawn_blocking
```

**Never** call `block_on` from within an async context — it will panic.

## Testing

```rust
#[tokio::test]
async fn basic() { assert_eq!(async_fn().await, 42); }

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn multi() { }

// Mock time (requires test-util feature)
#[tokio::test(start_paused = true)]
async fn time_test() {
    let start = tokio::time::Instant::now();
    tokio::time::sleep(Duration::from_secs(60)).await; // completes instantly
    assert!(start.elapsed() >= Duration::from_secs(60));
}
```

## Common Pitfalls

| Pitfall | Fix |
|---|---|
| Blocking in async task | `spawn_blocking` or `block_in_place` |
| Holding `std::sync::Mutex` across `.await` | Use `tokio::sync::Mutex` or restructure |
| Forgetting `.await` on a future | Futures are lazy — always `.await` or `spawn` |
| Non-`Send` data across `.await` | `Arc`, restructure, or use `current_thread` |
| `select!` with non-cancel-safe futures | Wrap in `tokio::spawn`, select on `JoinHandle` |
| `block_on` inside async context | Panics — use `spawn_blocking` + `handle.block_on` |
| Unbounded channels without backpressure | Prefer bounded `mpsc::channel(cap)` |
| Large futures on the stack | `Box::pin(future)` to heap-allocate |

## When to Use What

| Need | Use |
|---|---|
| Concurrent async work | `tokio::spawn` |
| Blocking/CPU work | `spawn_blocking` |
| `!Send` futures | `spawn_local` + `LocalSet` |
| Manage N tasks | `JoinSet` |
| Mutex across `.await` | `tokio::sync::Mutex` |
| Mutex (brief, no `.await`) | `std::sync::Mutex` |
| Limit concurrency | `Semaphore` |
| Wake task (no data) | `Notify` |
| One value between tasks | `oneshot` |
| Many values, one consumer | `mpsc` |
| Latest-value broadcast | `watch` |
| All-values broadcast | `broadcast` |
| Delay | `sleep` |
| Fail if too slow | `timeout` |
| Periodic work | `interval` |
| Shutdown signal | `ctrl_c` + `watch` or `CancellationToken` |
