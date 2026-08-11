---
name: tokio-rust
description: Tokio async runtime conventions — patterns, anti-patterns, module reference, synchronization primitives, channel decision table, when NOT to use Tokio, and alternatives. Use when writing or modifying async Rust code that uses the tokio runtime.
---

# Tokio Conventions

Apply these conventions when working with Tokio in Rust projects.

## Version / Compatibility

- Latest checked: Tokio `1.53.1` (2026-07-20), MSRV `1.71` from README/crates.io metadata.
- Tokio `1.x` is stable, but MSRV may increase in minor releases. Use `tokio = "1"` for apps unless you intentionally pin.
- If pinning a fixed minor, prefer an LTS line (`1.51.x` through March 2027; `1.47.x` through September 2026).
- Unstable features (`tracing`, `schedule-latency`, `io-uring`, `taskdump`) require both a Cargo feature and `--cfg tokio_unstable`; APIs may break in `1.x`.

## Patterns ✅

| Pattern | Description |
|---|---|
| **Bounded channels** | Always prefer `mpsc::channel(cap)` over unbounded. Backpressure prevents OOM. |
| **`std::sync::Mutex` for sync-only locks** | If the critical section has no `.await`, use `std::sync::Mutex`. It's cheaper than `tokio::sync::Mutex`. |
| **`spawn_blocking` for bounded blocking work** | Blocking I/O and sync library calls go in `spawn_blocking`. Limit CPU-heavy use with a `Semaphore` or use `rayon`; use dedicated threads for long-lived blocking loops. |
| **`JoinSet` for task groups** | When spawning multiple related tasks, use `JoinSet` instead of collecting `JoinHandle`s manually. |
| **`CancellationToken` for shutdown** | Cleaner than `watch::channel<bool>` for propagating cancellation. Supports hierarchical `child_token()`. |
| **Cancel-safe futures in `select!`** | Prefer cancel-safe operations (`mpsc::recv`, `watch::changed`, `accept`) inside `select!` loops. |
| **`biased;` in `select!`** | Use when certain branches must be checked first (e.g., shutdown before work). |
| **`watch` for config/state broadcast** | Only latest value matters — ideal for config updates, shutdown signals, shared state. |
| **`oneshot` for request-response** | Embed a `oneshot::Sender` in a request message, send via `mpsc`, receive the response on the oneshot. |
| **`Semaphore` for rate limiting** | Limit concurrent operations (DB connections, API calls) with `Semaphore::new(N)`. Permits auto-release on drop. |
| **`interval` + `MissedTickBehavior::Skip`** | For periodic tasks that must not drift. `Burst` (default) catches up; `Skip` drops missed ticks. |
| **`pin!` before `select!` on streams** | `tokio::pin!(stream)` before using in `select!` to satisfy `Unpin` bound. |
| **`block_in_place` for brief blocking** | In multi-thread runtime only. Better than `spawn_blocking` when you need to stay on the same thread (e.g., to re-enter async inside). |

## Anti-Patterns ❌

| Anti-Pattern | Why It's Bad | Fix |
|---|---|---|
| **Blocking the runtime** | `std::thread::sleep`, `std::fs::read`, CPU loops in async tasks starve all other tasks on that worker thread. | Use `spawn_blocking` or `block_in_place`. |
| **`std::sync::Mutex` across `.await`** | Locks the OS thread while a future is suspended — other tasks on the same worker can't progress. Can deadlock. | Use `tokio::sync::Mutex` or restructure so the lock drops before `.await`. |
| **Unbounded channels** | `mpsc::unbounded_channel()` has no backpressure. Producer can OOM the consumer. | Use `mpsc::channel(cap)` with a reasonable capacity. |
| **Non-cancel-safe ops in `select!`** | `read_exact`, `read_to_end`, `io::copy` lose partial progress on cancellation. Data corruption or loss. | Wrap in `tokio::spawn` and select on the `JoinHandle`. |
| **`block_on` inside async context** | Panics. Tokio runtime is already running. | Use `spawn_blocking` + `Handle::current().block_on()` only from sync → async bridge. |
| **`tokio::sync::Mutex` for sync-only data** | Unnecessary async overhead (allocation, context switch) for data never held across `.await`. | Use `std::sync::Mutex` — it's 10-100x faster for brief locks. |
| **Ignored `JoinHandle`** | Silently swallowed panics and errors. No backpressure. | `await` the handle or log the error. Use `JoinSet` for groups. |
| **`Arc<Mutex<Vec<_>>>` for high-contention maps** | Every write serializes all readers. | Use `DashMap` or sharded locks. |
| **Spawning unbounded tasks** | No limit → task count explodes → scheduler thrashing. | Use `Semaphore` or bounded `mpsc` to cap concurrency. |
| **`.unwrap()` on `send` / `recv`** | Channel closure is a normal event (shutdown, consumer dropped). | Handle `Err` gracefully or use `send().await?` pattern. |
| **`await`ing in a loop without `select!`** | `while let x = rx.recv().await` can't be interrupted (shutdown, timeout). | Wrap in `tokio::select!` with shutdown/timeout branch. |
| **Large futures on the stack** | `async fn` captures all locals — large buffers blow the stack. | `Box::pin(future)` to heap-allocate, or use `Box<[u8]>` for large buffers. |
| **`spawn_blocking` for long-lived workers** | Started blocking tasks cannot be aborted; runtime shutdown waits for them. | Use `std::thread::spawn` or a dedicated pool for persistent loops. |
| **`TcpStream::set_linger` / `TcpSocket::set_linger`** | Deprecated: `SO_LINGER` can block the runtime thread on drop. | Avoid linger; use `set_zero_linger()` only when abortive close and data loss are intentional. |

## Tokio Modules Quick Reference

| Module | Feature Flag | Purpose |
|---|---|---|
| `tokio::net` | `net` | Async TCP, UDP, Unix sockets. `TcpListener`, `TcpStream`, `UdpSocket`, `UnixListener`, `UnixStream`. |
| `tokio::fs` | `fs` | Async filesystem ops (`read`, `write`, `create_dir_all`, `remove_file`, etc.). Internally uses `spawn_blocking`. Use only for ordinary files; special files like named pipes can hang shutdown — use `tokio::net::unix::pipe` or `AsyncFd`. |
| `tokio::io` | `io-util`, `io-std` | `AsyncRead`/`AsyncWrite`/`AsyncBufRead` traits, `BufReader`/`BufWriter`, `copy`, `copy_bidirectional`, `split`, `duplex`, `stdin`/`stdout`/`stderr`. |
| `tokio::sync` | `sync` | Async sync primitives: `Mutex`, `RwLock`, `Semaphore`, `Notify`, `Barrier`, `mpsc`, `oneshot`, `broadcast`, `watch`. |
| `tokio::time` | `time` | `sleep`, `timeout`, `interval`, `Instant` (pausable in tests with `start_paused`). |
| `tokio::task` | `rt` | `spawn`, `spawn_blocking`, `spawn_local`, `JoinSet`, `LocalSet`, `yield_now`, `block_in_place`, `coop` (cooperative yielding). |
| `tokio::signal` | `signal` | `ctrl_c()`, Unix signals (`SIGTERM`, `SIGINT`, etc.), Windows signals. |
| `tokio::process` | `process` | Async child process management (`Command`, `Child`, `ChildStdin`/`Out`/`Err`). |
| `tokio::runtime` | `rt` | `Runtime`, `LocalRuntime`, `Handle`, `block_on`. Use `new_multi_thread()` or `new_current_thread()`; use `LocalRuntime` for `!Send` tasks without `LocalSet`. |

**Unstable diagnostics:** `runtime::dump`/task dumps require `taskdump` + `tokio_unstable` and are Linux-only. `schedule-latency` enables task scheduling latency metrics. Tokio's `tracing` feature emits internal runtime traces; it is not a `tokio::tracing` module.

**Companion crates:**

| Crate | Purpose |
|---|---|
| `tokio-stream` | `Stream` wrappers for channels (`ReceiverStream`, `BroadcastStream`, `IntervalStream`) + adapters (`filter`, `map`, `take`). |
| `tokio-util` | `Framed` + `Codec` for protocol framing, `CancellationToken`, `Either`, `io::StreamReader`, `sync::PollSemaphore`, `task::JoinMap`. |
| `tokio-test` | `tokio::test` macro extensions, `io::Builder` for mock I/O. |

## Synchronization Types — When to Use Each

### `std::sync::Mutex` vs `tokio::sync::Mutex`

| | `std::sync::Mutex` | `tokio::sync::Mutex` |
|---|---|---|
| Hold across `.await` | ❌ Deadlocks or blocks worker thread | ✅ Safe |
| Performance | Fast (OS-level, no alloc) | Slower (async overhead, heap alloc) |
| Use when | Quick sync-only access, no `.await` in lock | Must `.await` while holding lock |
| Contention | Use `try_lock` or keep scope tiny | Natural — yields to other tasks |

### `tokio::sync::RwLock`

Multiple concurrent readers, exclusive writer. Use when reads vastly outnumber writes. Prefer `tokio::sync::Mutex` if reads ≈ writes (RwLock overhead isn't worth it). ⚠️ `tokio::sync::RwLock` is fair — writers won't starve, but readers may queue.

### `tokio::sync::Semaphore`

Limits concurrent access to N. Ideal for: connection pools, rate limiting API calls, bounding parallel file ops. Permits auto-release via `Drop`.

### `tokio::sync::Notify`

Bare wake-up signal, no data. Use for: event signaling, condition variable pattern, custom channel implementations. `notify_one()` wakes one waiter; `notify_waiters()` wakes all.

### `tokio::sync::Barrier`

N tasks wait at the barrier, all proceed together. Use for: batch synchronization, test handoffs, phased algorithms. Rarely needed in production code; more common in tests.

### Channel Decision Table

| Need | Channel | Data | Pattern |
|---|---|---|---|
| Multiple producers, single consumer | `mpsc::channel(cap)` | Any | Work queues, pipelining |
| Fire-and-forget, no backpressure needed | `mpsc::unbounded_channel()` | Any | Logging, metrics (use sparingly) |
| Single request → single response | `oneshot` | Any | RPC-style: embed `Sender` in request |
| All subscribers see every message | `broadcast::channel(cap)` | T: Clone | Chat, event fan-out |
| Subscribers only need latest value | `watch::channel(init)` | T: Clone | Config, state, shutdown signal |

## Cargo.toml

```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
# Or pick features: rt, rt-multi-thread, macros, net, sync
# Minimal practical set for network services. Add io-util, time, signal, fs as needed.
# Use "full" while prototyping, then trim before release.
# Note: io-std needed for stdin/stdout/stderr; process for async subprocesses.
# Latest checked Tokio: 1.53.1; MSRV: Rust 1.71.
# Unstable features (tracing/schedule-latency/io-uring/taskdump) also need --cfg tokio_unstable.

# Streams
tokio-stream = "0.1"
# Framing/codecs + CancellationToken
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

// spawn_blocking — for bounded blocking I/O/sync calls
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

// spawn_local — for !Send futures (requires LocalSet, or LocalRuntime on Tokio 1.51+)
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

For high contention, consider `DashMap` or sharded locks.

```rust
// std::sync::Mutex — brief lock, no .await inside
let data = Arc::new(std::sync::Mutex::new(vec![]));
{ data.lock().unwrap().push(42); } // drop before .await

// tokio::sync::Mutex — lock held across .await
let db = Arc::new(tokio::sync::Mutex::new(conn));
let mut c = db.lock().await;
c.query("SELECT ...").await; // OK
```

## Channels

```rust
// mpsc — bounded (backpressure)
let (tx, mut rx) = mpsc::channel::<String>(100);
let tx2 = tx.clone();
tx.send("msg").await.unwrap();
while let Some(msg) = rx.recv().await { }

// oneshot — single value, single use
let (tx, rx) = oneshot::channel::<String>();
tx.send("result".into()).unwrap();
let val = rx.await.unwrap();

// broadcast — all receivers get every message. T: Clone required.
let (tx, mut rx1) = broadcast::channel::<i32>(16);
let mut rx2 = tx.subscribe();
tx.send(10).unwrap();

// watch — latest value only. Great for config, shutdown.
let (tx, mut rx) = watch::channel("initial");
tx.send("updated").unwrap();
println!("{}", *rx.borrow());
rx.changed().await.unwrap();
```

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
notify.notify_one();
notify.notified().await;

// Barrier — N tasks synchronize
let barrier = Arc::new(Barrier::new(4));
// Each task: barrier.wait().await;
```

## Async I/O

```rust
use tokio::io::{AsyncReadExt, AsyncWriteExt};

reader.read(&mut buf).await?;
reader.read_exact(&mut buf).await?;
reader.read_to_end(&mut vec).await?;
writer.write_all(&buf).await?;
writer.flush().await?;

tokio::io::copy(&mut reader, &mut writer).await?;
tokio::io::copy_bidirectional(&mut client, &mut server).await?;

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

let s = stream::iter(1..=10).filter(|x| x % 2 == 0).map(|x| x * 10).take(3);

use tokio_stream::wrappers::ReceiverStream;
let stream = ReceiverStream::new(rx);
```

## Timers

```rust
tokio::time::sleep(Duration::from_millis(100)).await;

match tokio::time::timeout(Duration::from_secs(5), op()).await {
    Ok(result) => { }
    Err(_) => { /* timed out */ }
}

let mut ticker = tokio::time::interval(Duration::from_secs(1));
ticker.set_missed_tick_behavior(MissedTickBehavior::Skip);
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

⚠️ For high-throughput file I/O, `tokio::fs` adds indirection over `spawn_blocking`. Consider using `spawn_blocking` + `std::fs` directly for batch file operations.

## Signal Handling

```rust
tokio::signal::ctrl_c().await?;

use tokio::signal::unix::{signal, SignalKind};
let mut sigterm = signal(SignalKind::terminate())?;
sigterm.recv().await;
```

## Graceful Shutdown

```rust
// Pattern: watch channel + ctrl_c
let (shutdown_tx, shutdown_rx) = watch::channel(false);
// Workers select on shutdown_rx.changed()

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
tx.blocking_send(value).unwrap();
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
    tokio::time::sleep(Duration::from_secs(60)).await;
    // With start_paused, time stays frozen — the 60s sleep completes instantly
    assert!(start.elapsed() < Duration::from_millis(100));
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

## When NOT to Use Tokio — Alternatives

Tokio adds complexity (runtime, `Send` bounds, async color function). Don't reach for it when simpler tools work.

| Scenario | Why Tokio is Bad | Better Alternative |
|---|---|---|
| **CPU-bound computation** (crypto, image processing, compression) | No I/O to overlap; async yields no benefit; runtime + scheduling overhead. | `rayon` — parallel iterators, thread pools. Pure sync code. |
| **Simple CLI tools** (file converters, one-shot scripts) | Runtime startup cost, binary bloat, complexity for sequential work. | `std::fs`, `std::io`, `clap`. Plain sync Rust. |
| **Batch data processing** (ETL, CSV transform) | No concurrent I/O; sequential processing is clearer and faster. | `std::fs` + iterators. For parallelism: `rayon`. |
| **Embedded / no-std / WASM (limited)** | Tokio runtime requires OS threads, allocator, full std. | `embassy` (embedded async), `futures::executor::block_on` (minimal). |
| **Library code (not applications)** | Libraries should not pick a runtime — forces it on consumers. | Write runtime-agnostic code with `futures`, `async-trait`. Let the app choose runtime. |
| **Heavy blocking I/O** (legacy DB drivers, C FFI) | Wrapping everything in `spawn_blocking` adds overhead and thread pool pressure. | `std::sync` + `crossbeam` channels, or `threadpool` crate. |
| **Real-time / low-latency** (games, audio, trading) | GC-like pauses from cooperative scheduling; unpredictable task wake-up latency. | `ringbuf` + dedicated OS threads. `pasts` for constrained async. |
| **gRPC / Protobuf services** | `tonic` works with multiple runtimes but Tokio is common. If you need glommio/monoio, skip Tokio. | `tonic` can run on `glommio` or `monoio` runtimes. |
| **File-heavy workloads** (bulk file I/O) | `tokio::fs` is just `spawn_blocking` underneath; adds indirection. | `std::fs` directly (or `spawn_blocking` + `std::fs` within Tokio apps). |
| **Simple concurrent pipelines** (3-4 stages) | Full Tokio runtime is overkill for a fixed pipeline. | `crossbeam` channels + `std::thread`. Simpler, no async. |

### Quick Decision Guide

```
Need async I/O (network, timers, many concurrent connections)?
  → YES: Use Tokio.
  → NO: Need parallel CPU work?
    → YES: Use rayon.
    → NO: Need simple concurrency (a few threads)?
      → YES: Use std::thread + crossbeam channels.
      → NO: Just use plain sync Rust. No runtime needed.
```
