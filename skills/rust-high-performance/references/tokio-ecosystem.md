# Tokio, bytes, serde and binary formats, rayon, caches, HTTP, tracing

Performance rules for the common async/service stack. Runtime basics (flavors, `spawn_blocking` vs rayon, mutex choice) are shared with the `tokio-rust` and `rust-async-conventions` skills; this file keeps the performance-specific detail and numbers.

Crate versions (crates.io, 2026-11-08): tokio 1.54, tokio-util 0.7, tokio-metrics 0.5, console-subscriber 0.5, bytes 1.12, serde 1.0, serde_json 1.0, futures 0.3, hyper 1.12, hyper-util 0.1, axum 0.8, reqwest 0.13, tracing 0.1, tracing-subscriber 0.3, tracing-appender 0.2, rayon 1.12, moka 0.12, quick_cache 0.7, simd-json 0.19, sonic-rs 0.5, postcard 1.1, rkyv 0.8, bitcode 0.6, wincode 0.6, mimalloc 0.1.

## 1. Tokio runtime

### 1.1 Flavor

**Rule**: multi-thread for servers; `current_thread` for CLIs, tests, single-connection tools, and thread-per-core designs (N `current_thread` runtimes with `SO_REUSEPORT`). Tokio docs: "Most applications should use the multi-thread scheduler, except in some niche use-cases". Send futures -> multi-thread; `!Send` -> `LocalRuntime` (stable since tokio 1.51; `Builder::new_current_thread().build_local(LocalOptions::default())`, then `rt.spawn_local`); otherwise current-thread.
**Detect**: `#[tokio::main]` on a tiny CLI; `Arc<Mutex<_>>` only to satisfy `Send` in a single-threaded program; one big runtime on a multi-socket NUMA host (the runtime is not NUMA-aware; start several).
**Caveat**: `current_thread` has no work stealing and `block_in_place` panics on it.
Source: https://docs.rs/tokio/latest/tokio/runtime/index.html

### 1.2 Worker and blocking-pool sizing

**Rule**: leave `worker_threads` at the default (`available_parallelism`); never raise it to hide blocking. `max_blocking_threads` defaults to 512 and the blocking queue is **unbounded**, so bound what you feed it with a `Semaphore`. In containers with fractional CPU quotas set the count explicitly if `available_parallelism` misreads the quota.
**Detect**: `worker_threads(64)` on 8 cores; `spawn_blocking` in a loop; heavy `tokio::fs`, DNS (`ToSocketAddrs`) or `tokio::io::stdout` traffic (all run on the blocking pool).

```rust
use std::path::PathBuf;
use std::sync::Arc;

fn heavy(path: PathBuf) -> u64 {
    std::fs::metadata(path).map(|m| m.len()).unwrap_or(0)
}

pub async fn process_all(paths: Vec<PathBuf>) -> Result<u64, Box<dyn std::error::Error + Send + Sync>> {
    let sem = Arc::new(tokio::sync::Semaphore::new(8));
    let mut set = tokio::task::JoinSet::new();
    for path in paths {
        let permit = sem.clone().acquire_owned().await?;
        set.spawn_blocking(move || {
            let _permit = permit;
            heavy(path)
        });
    }
    let mut total = 0;
    while let Some(r) = set.join_next().await {
        total += r?;
    }
    Ok(total)
}
```

Source: https://docs.rs/tokio/latest/tokio/runtime/struct.Builder.html

### 1.3 CPU vs blocking work

**Rule** (Alice Ryhl): async code should spend at most 10-100 µs between `.await`s. Blocking I/O and blocking drivers -> `spawn_blocking`. Sustained or parallel CPU work -> `rayon` bridged with `oneshot`, so no worker blocks. Permanent background loops -> a dedicated `std::thread`. `block_in_place` (multi-thread only) suspends everything else in the same task and is not cancellable; prefer `spawn_blocking` when unsure. Tokio deliberately does not detect blocking and add threads.
**Detect**: `std::thread::sleep`, `std::fs::*`, `reqwest::blocking`, big `serde_json::from_*`, hashing/compression/regex over large inputs, or long in-memory loops inside `async fn` with no `.await`.

```rust
fn expensive_hash(data: &[u8]) -> u64 {
    data.iter().fold(0xcbf29ce484222325u64, |h, &b| (h ^ u64::from(b)).wrapping_mul(0x100000001b3))
}

pub async fn hash(data: Vec<u8>) -> std::thread::Result<u64> {
    let (tx, rx) = tokio::sync::oneshot::channel();
    rayon::spawn(move || {
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| expensive_hash(&data)));
        let _ = tx.send(r);
    });
    rx.await.expect("rayon worker dropped the sender")
}
```

**Caveat**: a panic inside a `rayon::spawn` closure aborts the whole process unless the pool has a `panic_handler`, so catch it as above. `spawn_blocking` for sustained CPU work oversubscribes cores (fine for occasional bursts with a `Semaphore`, as `tokio-rust` says); `rayon::spawn`'s queue has no backpressure (add a `Semaphore`). Never call `par_iter()` directly inside an `async fn`.
Sources: https://ryhl.io/blog/async-what-is-blocking/ · https://docs.rs/tokio/latest/tokio/task/fn.block_in_place.html · https://tokio.rs/blog/2020-04-preemption

### 1.4 Finding blocking

- `tokio-console` (`RUSTFLAGS="--cfg tokio_unstable"` + `console_subscriber::init()`): per-task busy/idle, poll counts, long-poll and lost-waker warnings. Dev/staging tool.
- Stable `RuntimeMetrics`: `num_workers`, `num_alive_tasks`, `global_queue_depth`, `worker_total_busy_duration`. Poll-time histogram needs `tokio_unstable` + `enable_metrics_poll_time_histogram()` and costs two `Instant::now()` per poll.
- `tokio-metrics` 0.5 `TaskMonitor`/`RuntimeMonitor` (slow-poll ratio, scheduled duration).
- Clippy: `await_holding_lock`, `await_holding_refcell_ref`, and `disallowed-methods` for `std::thread::sleep`/`std::fs::read*` in async crates.
**Detect**: p99 spikes while some cores idle; `global_queue_depth` growing; one worker far busier than the rest. Metrics tell you *that* something blocks; `perf`/`samply` or the console tell you *where*.
Sources: https://docs.rs/tokio/latest/tokio/runtime/struct.RuntimeMetrics.html · https://github.com/tokio-rs/console

### 1.5 Cooperative budget and `yield_now`

**Rule**: every tokio resource op consumes a per-task budget; when it runs out, tokio resources return `Pending` so the task yields. This does not cover CPU loops or non-tokio futures. For a long loop that must stay on the runtime, `tokio::task::yield_now().await` every N iterations; still prefer moving the work off the runtime. `yield_now` is not a strong guarantee (the same task may be re-polled immediately; a `select!` with another ready branch swallows it).
**Detect**: `loop { if let Some(x) = rx.try_recv() { .. } }` drain loops; big `for` over in-memory data in an `async fn`.
Source: https://tokio.rs/blog/2020-04-preemption · https://docs.rs/tokio/latest/tokio/task/fn.yield_now.html

### 1.6 Mutex choice in async code

**Rule**: `std::sync::Mutex` (or parking_lot) for plain data with short critical sections and no `.await` inside; `tokio::sync::Mutex` only when the guard must span an `.await` (typically an I/O resource), and a dedicated owner task with message passing is often better. Tokio docs call the blocking mutex "often preferred" and the async one more expensive. Wrap the mutex in a type with sync methods (the mini-redis pattern) so guards cannot leak across awaits.
**Detect**: `Arc<tokio::sync::Mutex<HashMap<..>>>` whose uses are `lock().await; map.get()`; a std guard alive across `.await`.
**Futurelock**: `tokio::select!` over `&mut fut` branches that hold or wait on the same mutex can deadlock although nothing blocks (Oxide RFD 609); spawn the sub-future or restructure.
Sources: https://docs.rs/tokio/latest/tokio/sync/struct.Mutex.html · https://rfd.shared.oxide.computer/rfd/0609

### 1.7 Bounded `mpsc`, `recv_many`, `oneshot`

**Rule**: `mpsc::channel(n)` by default; `send().await` suspending the producer is the backpressure. Unbounded only when producers cannot be slowed (sync -> async bridge). Drain in batches with `recv_many(&mut buf, limit)` to cut wakeups; `reserve()` a permit before expensive work; `oneshot` for single replies. Cross sync/async with `blocking_send`/`blocking_recv`.
**Detect**: `unbounded_channel()` on a request path; RSS growing under load; `tokio::spawn` per message instead of a queue and N workers.

```rust
pub struct Job(pub u64);

fn flush(batch: &[Job]) {
    let _ = batch.len();
}

pub async fn consume(mut rx: tokio::sync::mpsc::Receiver<Job>) {
    let mut buf = Vec::with_capacity(128);
    while rx.recv_many(&mut buf, 128).await > 0 {
        flush(&buf);
        buf.clear();
    }
}

pub fn make_channel() -> (tokio::sync::mpsc::Sender<Job>, tokio::sync::mpsc::Receiver<Job>) {
    tokio::sync::mpsc::channel(1024)
}
```

**Caveat**: two tasks sending to each other over full bounded channels can deadlock; use `try_send` and shed on one side.
Source: https://docs.rs/tokio/latest/tokio/sync/mpsc/index.html

### 1.8 `broadcast` and `watch`

**Rule**: `broadcast` clones the value per receiver on `recv`, rounds capacity to a power of two, and gives slow receivers `RecvError::Lagged(n)`; send `Arc<T>` or `Bytes` and handle `Lagged`. `watch` keeps only the latest value (config, shutdown flags); do not hold `borrow()` across `.await`; `send_if_modified` avoids spurious wakeups.
**Detect**: `broadcast::channel::<Vec<u8>>`; `unwrap()` on broadcast `recv()`; `let g = rx.borrow(); ... .await`.
Sources: https://docs.rs/tokio/latest/tokio/sync/broadcast/index.html · https://docs.rs/tokio/latest/tokio/sync/watch/index.html

### 1.9 No task per tiny item

**Rule**: a spawn allocates and schedules a task; 100k spawns of tiny work is overhead plus unbounded memory. Batch items per task, cap concurrency with `futures::stream::iter(items).map(f).buffer_unordered(n)` (one task, one thread of progress), or `JoinSet` + `Semaphore` when you need parallelism across threads. Size `n` to downstream capacity (DB pool, rate limit), not core count.
**Detect**: `for x in items { tokio::spawn(tiny(x)); }`; a `Vec<JoinHandle>` awaited in a loop; `join_all` over an unbounded `Vec`.

```rust
use futures::StreamExt;

async fn fetch(id: u32) -> usize {
    id as usize
}

pub async fn fetch_all(items: Vec<u32>) -> Vec<usize> {
    futures::stream::iter(items)
        .map(fetch)
        .buffer_unordered(32)
        .collect()
        .await
}
```

Source: https://docs.rs/tokio/latest/tokio/task/struct.JoinSet.html

### 1.10 Large futures

**Rule**: a future's size is everything held across `.await`; big futures are memcpy'd on every move and can overflow worker stacks. Since tokio 1.41 `tokio::spawn` auto-boxes futures over 2 KiB in debug and 16 KiB in release (before that, release never boxed). Auto-boxing covers only the hand-off into the runtime: the future is still built on the caller's stack, and a big child inflates its parent through `.await`, so `Box::pin` large futures at the await site. Enable Clippy `large_futures` (pedantic, `future-size-threshold` 16 KiB); tokio's spawn spans carry `size.bytes`/`original_size.bytes` and tokio-console warns on auto-boxed tasks.
**Detect**: `[0u8; 64 * 1024]` or large structs as locals spanning an await; deep `async fn` chains; worker stack overflow.

```rust
async fn huge() {
    let mut a = [0u8; 20_000];
    tokio::task::yield_now().await;
    a[0] = 1;
    let _ = a;
}

pub async fn caller() {
    Box::pin(huge()).await;
}
```

**Caveat**: one allocation per `Box::pin`; prefer a `Vec`/`BytesMut` buffer over a stack array where possible; avoid giant `select!`/`join!` bodies in one state machine.
Sources: https://hegdenu.net/posts/how-big-is-your-future/ · https://github.com/tokio-rs/tokio/pull/6826 · https://github.com/tokio-rs/tokio/issues/6057

### 1.11 Timers

**Rule**: `interval` defaults to `MissedTickBehavior::Burst` (fires all missed ticks back-to-back); for flushes, health checks and cache refreshes set `Skip` or `Delay`. In `select!` loops pin one `Sleep` and `reset()` it instead of creating a new `sleep()` per iteration.

```rust
async fn flush() {}

pub async fn periodic_flush() {
    let mut t = tokio::time::interval(std::time::Duration::from_secs(1));
    t.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        t.tick().await;
        flush().await;
    }
}
```

Source: https://docs.rs/tokio/latest/tokio/time/enum.MissedTickBehavior.html

### 1.12 Buffered async I/O and `tokio::fs`

**Rule**: raw `TcpStream`/`File` calls are one syscall (or one blocking-pool hop) each; wrap in `tokio::io::BufReader`/`BufWriter` for small-record protocols and `flush().await` before drop. `tokio::fs` runs every op on the blocking pool: for many small file ops do one `spawn_blocking` with `std::fs`; for whole files use `tokio::fs::read`.
**Detect**: `write_all` of many tiny pieces; `read_u8()` loops; `tokio::fs::File` read in small chunks.
**Caveat**: for latency-critical request/response, flush per message or set `TCP_NODELAY` and batch yourself.
Source: https://docs.rs/tokio/latest/tokio/runtime/struct.Builder.html (blocking-pool list)

### 1.13 Scheduler knobs (only with a metric)

`event_interval` (default 61) and `global_queue_interval` (current_thread 31; multi-thread adaptive, targeting ~200 µs between global-queue checks) are stable. `disable_lifo_slot()`, `enable_alt_timer()`, `enable_eager_driver_handoff()`, `enable_sharded_blocking_queue()` need `tokio_unstable` and may change or be removed. Try `disable_lifo_slot` when scheduled time is high but the runtime is underutilized, confirmed with tokio-metrics.
Source: https://docs.rs/tokio/latest/tokio/runtime/struct.Builder.html

### 1.14 `select!` ordering

`tokio::select!` polls branches in random order; `biased;` gives deterministic priority (shutdown first) and skips the RNG. An always-ready early branch then starves later ones; keep the high-priority branch rare, and check cancellation safety of every branch.
Source: https://docs.rs/tokio/latest/tokio/macro.select.html

## 2. `bytes`

**Rule**: `Bytes` is a refcounted, cheaply cloneable, sliceable view (`clone`/`slice`/`split_to` copy nothing; `from_static` is allocation-free; `Bytes::from(Vec<u8>)` is copy-free but allocates a small shared header unless `len == capacity`). Frame protocols with `BytesMut`: read into it, `split_to(n).freeze()` yields an immutable frame while the buffer keeps accepting reads. Share payloads across tasks as `Bytes`, not `Vec<u8>` clones.
**Detect**: `buf[..n].to_vec()` after a read; `Vec<u8>.clone()` per consumer; hand-rolled framing with `drain(..n)` (O(n) memmove).

```rust
use bytes::{Buf, Bytes, BytesMut};

/// Length-prefixed frames: u32 big-endian length, then payload. Returns None until a full frame is buffered.
const MAX_FRAME: usize = 16 * 1024 * 1024;

#[derive(Debug)]
pub struct FrameTooLarge(pub usize);

pub fn next_frame(buf: &mut BytesMut) -> Result<Option<Bytes>, FrameTooLarge> {
    if buf.len() < 4 {
        return Ok(None);
    }
    let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;
    if len > MAX_FRAME {
        return Err(FrameTooLarge(len));
    }
    if buf.len() - 4 < len {
        return Ok(None);
    }
    buf.advance(4);
    Ok(Some(buf.split_to(len).freeze()))
}
```

**Caveat**: never trust a length prefix from the network; cap it (`MAX_FRAME`) and close the connection on `Err`. A small `Bytes` keeps its whole backing allocation alive; detach long-lived retained slices with `Bytes::copy_from_slice`. `BytesMut::reserve` reuses the freed front region only once all frozen views are dropped.
Source: https://docs.rs/bytes/latest/bytes/struct.Bytes.html

## 3. Serialization

### 3.1 serde_json shape and borrowing

**Rule**: `from_slice`/`from_str` on an in-memory buffer; `from_reader` is unbuffered, "usually slower than reading a file completely into memory", needs `DeserializeOwned`, and waits for EOF (wrong on persistent sockets; use `Deserializer::from_reader(..).into_iter()`). `&str`/`&[u8]` fields borrow automatically; `Cow<str>` needs `#[serde(borrow)]`. Typed structs instead of `serde_json::Value`; `to_writer`/`to_vec` into a reused buffer instead of `to_string` then copy.
**Detect**: `from_reader(File::open(..)?)` without `BufReader`; `from_str::<Value>` then `from_value::<T>`; owned `String` fields read once; `to_string(&x)?.into_bytes()`.

```rust
#[derive(serde::Deserialize)]
pub struct Msg<'a> {
    pub id: u64,
    pub name: &'a str,
    #[serde(borrow)]
    pub note: std::borrow::Cow<'a, str>,
}

pub fn parse(bytes: &[u8]) -> Result<Msg<'_>, serde_json::Error> {
    serde_json::from_slice(bytes)
}
```

**Caveat**: `&str` fails at runtime if the JSON string contains escapes; use `Cow<str>` + `#[serde(borrow)]` when escapes are possible. Borrowing structs fit request-scoped parsing, not stored state. Multi-MB parses belong in `spawn_blocking`/rayon.
Sources: https://docs.rs/serde_json/latest/serde_json/fn.from_reader.html · https://serde.rs/lifetimes.html

### 3.2 simd-json and sonic-rs

**Rule**: consider only after the profile shows JSON as a top cost on large payloads, and after the cheaper fixes above. Independent numbers (rust_serialization_benchmark, log dataset, 2026-11-05): serde_json 2.33 ms ser / 4.60 ms de; simd-json 1.53 / 3.99 ms, so about 1.2-1.5x on string-heavy small records. sonic-rs' 3x (twitter.json 0.83 ms vs 2.29 ms) is its own benchmark and it is absent from the independent table.
- simd-json 0.19: `from_slice(&mut buf)` parses in place (mutates the buffer); runtime SIMD detection; scalar fallback is much slower.
- sonic-rs 0.5: parses straight into structs, lazy field lookup (`get`, `LazyValue`), wants `-C target-cpu=native`.
**Caveat**: float edge cases and error messages differ from serde_json; test on your corpus.
Sources: https://github.com/djkoloski/rust_serialization_benchmark · https://github.com/simd-lite/simd-json · https://github.com/cloudwego/sonic-rs

### 3.3 Binary formats for internal traffic

Same benchmark, same dataset (serialize / deserialize / borrowed deserialize / size):
- bitcode 0.6: 175 µs / 1.44 ms / 44 µs / 704 KB
- postcard 1.1: 256 µs / 1.95 ms / 500 µs / 725 KB
- wincode 0.6: 145 µs / 1.64 ms / 344 µs / 1,046 KB
- rkyv 0.8: 222 µs / 1.46 ms unvalidated, 1.82 ms validated / zero-copy access 340 µs validated, 7.8 µs unvalidated / 1,011 KB
- rmp-serde 1.3: 1.06 ms / 2.53 ms / 1.14 ms / 785 KB
- serde_json 1.0: 2.33 ms / 4.60 ms / 1,827 KB

**Rule**: when measurement shows JSON cost on a hot internal path (RPC, cache values, queues), consider a binary format; versioned or on-disk data also needs a schema-evolution story, debuggability and cross-language needs may outweigh speed: smallest and fastest Rust-only -> bitcode (derive native `Encode`/`Decode`, reuse a `bitcode::Buffer`); `no_std`, varint, published wire spec -> postcard (reuse output buffers; COBS framing for streams); bincode-compatible -> wincode; zero-copy reads of trusted or mmap'd data -> rkyv (validating `rkyv::access` for untrusted bytes; `access_unchecked` is `unsafe`); cross-language -> protobuf (`prost`) or MessagePack. Borrowed deserialization (`&str` fields) is the big read-side win in every format.
**Caveat**: one dataset on a shared VM; numeric-heavy or blob-heavy shapes rank differently. Check each crate's own compatibility guarantees before persisting data across versions.
Source: https://github.com/djkoloski/rust_serialization_benchmark

### 3.4 bincode is unmaintained

bincode development ceased in December 2025 (RUSTSEC-2025-0141, an INFO "unmaintained" advisory; the team considers 1.3.3 complete). `bincode 3.0.0` on crates.io is a deliberate placeholder whose `lib.rs` is a `compile_error!`; the last functional release is 2.0.1. The README recommends wincode, postcard and rkyv.
**Rule**: never add bincode to new code; never write `bincode = "*"` or `>= 2`. Existing code: pin `bincode = "=2.0.1"` (or `"1.3"`), then migrate to wincode (wire-compatible with bincode configs), postcard or rkyv. `cargo audit` flags the advisory.

```toml
bincode = "=2.0.1"   # stop-gap
wincode = "0.6"      # target, or postcard = "1.1"
```

Sources: https://docs.rs/bincode/latest/bincode/ · https://rustsec.org/advisories/RUSTSEC-2025-0141

## 4. rayon

**Rule**: rayon splits work recursively; when per-item work is under about a microsecond the split/steal overhead dominates and `par_iter` can be slower than `iter`. Coarsen with `with_min_len(n)` or `par_chunks(n)`/`par_chunks_mut` and process each chunk sequentially. Use `map`/`collect` or `fold`/`reduce` instead of pushing into `Mutex<Vec<_>>`; `map_init`/`for_each_init` give per-thread scratch buffers. Build one `ThreadPool` at startup and `pool.install(..)`; never create pools per call; never block a rayon thread on I/O, on locks held by other pool threads, or on `block_on`. When mixing with tokio, cap `num_threads` so rayon threads plus tokio workers do not exceed cores (or accept oversubscription knowingly).
**Detect**: `par_iter().map(|x| x + 1)` on cheap ops or under ~1000 items; `par_iter` nested in an already-parallel hot loop; `ThreadPoolBuilder::new()...build()` inside a function; `block_on` inside a `par_iter` closure.

```rust
use rayon::prelude::*;

pub fn squares(v: &[u64]) -> Vec<u64> {
    v.par_iter().with_min_len(1024).map(|x| x * x).collect()
}

pub fn chunk_sums(v: &[u64]) -> Vec<u64> {
    v.par_chunks(4096).map(|c| c.iter().sum()).collect()
}
```

**Caveat**: always compare against a sequential baseline on production-sized input.
Sources: https://github.com/rayon-rs/rayon/issues/1136 · https://docs.rs/rayon/latest/rayon/iter/trait.IndexedParallelIterator.html

## 5. Caches: moka vs quick_cache

- moka 0.12: sync and async caches, TinyLFU admission + LRU eviction, TTL/TTI, per-entry expiry, eviction listeners, weighted capacity, per-key atomic init (`get_with`/`try_get_with` coalesce concurrent loaders: stampede protection); heavier than a plain map; no background threads since 0.12.
- quick_cache 0.7: S3-FIFO, scan-resistant, minimal overhead over a concurrent hash table, weighter, `get_or_insert_async`/`get_value_or_guard_async`; no TTL/TTI or rich listeners ("look at Moka").
- mini-moka 0.10: last release 2024-01; prefer the two above.
**Rule**: need TTL/TTI, per-entry expiry or eviction callbacks -> moka; need minimal per-op overhead and no TTL -> quick_cache. Always bound capacity; store `Arc<V>` because `get` clones the value out. Do not wrap either in a `Mutex`/`RwLock`; they are already concurrent.
**Detect**: `Arc<Mutex<HashMap>>` with manual eviction; unbounded `HashMap` as a cache; check-then-load-then-insert races (stampedes).

```rust
use std::sync::Arc;

async fn load(k: u64) -> String {
    k.to_string()
}

pub async fn lookup(cache: &moka::future::Cache<u64, Arc<String>>, k: u64) -> Arc<String> {
    cache.get_with(k, async { Arc::new(load(k).await) }).await
}
```

**Caveat**: moka maintenance is amortized onto cache ops; in tests call `run_pending_tasks()` before asserting sizes. Hit ratios (TinyLFU vs S3-FIFO) are workload-dependent; measure hit ratio and p99, not only throughput.
Sources: https://github.com/moka-rs/moka · https://github.com/arthurprs/quick-cache

## 6. HTTP

### 6.1 One `reqwest::Client`

**Rule**: build one `reqwest::Client` (cheap `Clone`, `Arc` inside) and reuse it: it owns the connection pool (keep-alive, HTTP/2 multiplexing, TLS sessions). Set `timeout`/`connect_timeout`; tune `pool_idle_timeout`/`pool_max_idle_per_host`; stream large bodies (`bytes_stream`) when you only forward them.
**Detect**: `reqwest::get(url)` or `Client::new()` inside a handler or loop; `.bytes().await` on multi-MB bodies; no timeouts.

```rust
pub struct AppState {
    pub http: reqwest::Client,
}

pub fn build_state() -> Result<AppState, reqwest::Error> {
    let http = reqwest::Client::builder()
        .pool_max_idle_per_host(32)
        .connect_timeout(std::time::Duration::from_secs(3))
        .timeout(std::time::Duration::from_secs(15))
        .build()?;
    Ok(AppState { http })
}
```

Build it once in `main` (or app state) with `?` and pass clones; avoid a process-global `static` client, which hides the build error behind a panic and can outlive the runtime it was used on (per-test runtimes).

**Caveat**: `Client::new()` panics if the TLS backend fails to initialize; use `builder().build()` to handle the error. Building a client loads root certificates.
Source: https://docs.rs/reqwest/latest/reqwest/struct.Client.html

### 6.2 hyper / axum

hyper 1.x keeps HTTP/1.1 connections alive by default; `axum::serve` builds on hyper-util. Keep load-balancer idle timeouts shorter than the server's keep-alive to avoid reset races; set `TCP_NODELAY` for small-message latency. If a measurement shows HTTP/2 stream or flow-control limits, tune via hyper-util's `server::conn::auto::Builder` -> `.http2()` in a manual accept loop; with plain `axum::serve` you get hyper's defaults. hyper 1.x has no client pool: use hyper-util's legacy `Client` or reqwest.
Sources: https://docs.rs/hyper-util/latest/hyper_util/server/conn/auto/struct.Builder.html · https://docs.rs/axum/latest/axum/

## 7. tracing

**Rule**: compile out levels in the **binary crate only** with `tracing` features `max_level_*` / `release_max_level_*` (statically disabled events cost nothing; dynamically disabled ones cost a cached callsite check). Libraries must not set these (feature unification would silence the whole app). Pass data as fields (`debug!(?req, "req")`) rather than `format!`/`to_string()`; guard expensive computation with `tracing::enabled!`. `#[instrument]` on hot functions records every argument with `Debug` on every call while the span is enabled: use `skip_all`, explicit `fields(..)`, `level = "trace"`. Never hold `Span::enter()` across `.await`; use `.instrument(span)` or `#[instrument]` on the async fn. Synchronous log writes block the worker: use `tracing_appender::non_blocking` and keep the `WorkerGuard` alive; it drops events when its buffer fills unless built with `NonBlockingBuilder::lossy(false)`.
**Detect**: `trace!`/`debug!` in per-packet loops with no static cap in release; `info!("{}", expensive.to_string())`; `#[instrument]` without `skip_all` on per-item functions; `let _g = span.enter(); ... .await`.

```toml
# binary crate only
tracing = { version = "0.1", features = ["max_level_debug", "release_max_level_info"] }
```

```rust
pub struct Item {
    pub id: u64,
}

#[tracing::instrument(level = "trace", skip_all, fields(id = %item.id))]
pub async fn handle(item: &Item) {
    tracing::debug!(?item.id, "handled");
}
```

**Caveat**: the static features do not affect `log` records bridged through tracing's `log` feature (use `log`'s own `max_level_*` features). A binary built with `release_max_level_info` cannot enable `debug` at runtime via `RUST_LOG`; document it.
Source: https://docs.rs/tracing/latest/tracing/level_filters/index.html
