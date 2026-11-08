# Locks, atomics, channels, and concurrent maps

Reviewer-oriented rules for shared state. None of these are unconditional wins; measure under realistic contention and key distribution.

Crate versions (crates.io, 2026-11-08): parking_lot 0.13, arc-swap 1.9, dashmap 6.2 (7.0 is rc, do not use), papaya 0.2, scc 3.8, crossbeam-channel 0.5, crossbeam-utils 0.8, flume 0.12, thread_local 1.1, loom 0.7, tokio 1.54, rayon 1.12.
Std floors: futex-based `Mutex`/`Condvar`/`RwLock` on Linux since 1.62, on Windows since 1.78; `std::sync::mpsc` backed by crossbeam-channel since 1.67; `OnceLock` 1.70; `LazyLock` 1.80; `OnceLock::wait` 1.86; `RwLockWriteGuard::downgrade` 1.92; `Atomic*::update`/`try_update` 1.95.

## A0. Preference ladder: the cheapest lock is the one you do not take

1. Data owned by one thread: no synchronization.
2. Per-thread accumulation, merged once (`thread_local!`, `rayon::fold`/`reduce`, per-worker struct).
3. Message passing / one owner task for stateful I/O resources (the Tokio guide's recommendation).
4. Immutable snapshot swapped atomically (`ArcSwap`) for read-mostly config.
5. Atomics for single-word counters and flags.
6. Sharded or concurrent map for hot shared maps.
7. `std::sync::Mutex` with a short critical section. Last resort: `RwLock`, spin locks.

## A1. `Mutex<int|bool>` -> atomic

**Rule**: a mutex whose only job is `*g += 1` or a flag becomes `AtomicU64`/`AtomicBool`; use `Relaxed` when the value is a pure statistic and no other memory is published through it.
**Detect**: `Mutex<(u|i)(8|16|32|64|size)>`, `Mutex<bool>`, `Mutex<Instant>`; one-line guard scopes.

```rust
use std::sync::atomic::{AtomicU64, Ordering};

static HITS: AtomicU64 = AtomicU64::new(0);

pub fn hit() {
    HITS.fetch_add(1, Ordering::Relaxed);
}
```

**Caveat**: `Relaxed` gives no cross-thread happens-before; a "ready" flag that guards other data needs `Release` store / `Acquire` load. Several separate atomics are not a consistent snapshot; if an invariant spans fields keep the `Mutex` around the struct. `fetch_add` wraps; if uniqueness is a safety property check-and-abort or use `fetch_update`.
Source: https://mara.nl/atomics/atomics.html (ch. 2)

## A2. Weakest correct `Ordering`, and what it costs per architecture

**Rule**: counters -> `Relaxed`; publish-then-read -> `Release` store, `Acquire` load (`AcqRel` for RMW); `SeqCst` only for a single global order across several atomics (rare).
**Detect**: `SeqCst` everywhere with no comment; a `Mutex` used as a fence for a flag.
**Facts** (Rust Atomics and Locks ch. 7): on x86-64 every load/store already has acquire/release semantics; `SeqCst` costs extra only on stores (`xchg` vs `mov`) and fences; `fetch_add` is `lock add` for all orderings. On ARM64, `Relaxed` is plain `ldr`/`str`. On baseline ARMv8.0 `Acquire` and `SeqCst` loads are both `ldar`; with RCpc (ARMv8.3+, all Apple Silicon) `Acquire` loads become the cheaper `ldapr` and RMWs use `ldadd` vs `ldaddal` for `SeqCst`. Corollary: wrong `Relaxed` code often works on x86 and breaks on ARM; test there and model-check with `loom` (0.7).
Source: https://mara.nl/atomics/memory-ordering.html · https://mara.nl/atomics/hardware.html

## A3. Native RMW instead of a CAS loop; `Atomic*::update` (1.95)

**Rule**: if the operation exists as `fetch_add/sub/and/or/xor/max/min/swap`, use it; reserve CAS loops for conditional updates, and write them with `update`/`try_update` (1.95) or `fetch_update`/`compare_exchange_weak`.
**Detect**: `loop { let c = x.load(..); if x.compare_exchange(c, c + 1, ..).is_ok() { break; } }` with an unconditional update.

```rust
use std::sync::atomic::{AtomicU32, Ordering};

pub fn inc(c: &AtomicU32) {
    c.fetch_add(1, Ordering::Relaxed);
}

pub fn saturating_inc(c: &AtomicU32) -> bool {
    c.try_update(Ordering::Relaxed, Ordering::Relaxed, |x| x.checked_add(1)).is_ok()
}
```

**Why**: x86-64 and ARMv8.1+ (LSE) have single-instruction atomic add (on default aarch64 Linux targets `fetch_add` is an outlined `__aarch64_ldadd*` call that picks LSE at runtime unless you build with `+lse` or a `target-cpu`); "a load can be significantly cheaper than a failed compare-and-exchange" because the latter demands exclusive access to the cache line. For a CAS-based flag, load first and CAS only when it looks free (test-and-test-and-set).
Source: https://mara.nl/atomics/hardware.html (Summary)

## A4. False sharing

**Rule**: independent hot atomics (per-thread counters, queue head/tail, `Vec<Mutex<_>>` shards with small `T`) go on separate cache lines via `crossbeam_utils::CachePadded<T>` or `#[repr(align(128))]`. **[measured]** 651 ms -> 41 ms for four adjacent `fetch_add` counters on M2 Max; details and snippet in memory-layout.md C2.
**Detect**: `[AtomicU64; N]` indexed by thread id; a struct with several `Atomic*` fields written by different threads; `Vec<Mutex<HashMap>>` shards (a `Mutex<T>` with small `T` is 5-8 bytes on Linux, so many share a line).
**Caveat**: 128 B per slot; apply to measured contention only (`perf c2c` on Linux).
Source: https://docs.rs/crossbeam-utils/latest/crossbeam_utils/struct.CachePadded.html

## A5. `std::sync::Mutex` vs `parking_lot` vs spin locks

**Rule**: default to `std::sync::Mutex`. std is futex-based on Linux since 1.62 (5-byte state, no `Box`) and on Windows since 1.78; the Perf Book says the std versions "have greatly improved on some platforms. So you should measure before switching". Choose `parking_lot` for its features (1-byte `Mutex`, no poisoning, upgradable/downgradable `RwLock`, fair unlock, deadlock detection, `ReentrantMutex`) or with a benchmark on your target OS and workload. No post-1.62 head-to-head benchmark was found; do not assert that either is faster.
**Detect**: `parking_lot` adopted "for speed" with no benchmark; `spin::Mutex` or `while lock.swap(true, Acquire) {}` in std-using application code.
**Spin locks**: matklad's 2020 bench (32 threads on 4C/8T, Linux) under heavy contention: parking_lot 10 ms, spin 55 ms average with a 161 ms maximum. The std numbers there are pre-1.62 and stale; the spin-vs-sleeping conclusion stands: a preempted spinning holder stalls everyone. Spin only when preemption is impossible (interrupts off, one pinned thread per core); otherwise bounded spin with `hint::spin_loop` then park.
**Mixing**: if you adopt parking_lot everywhere, ban `std::sync::Mutex` with Clippy `disallowed-types`; do not mix sync families in one module (see `rust-conventions`).
Sources: https://nnethercote.github.io/perf-book/standard-library-types.html · https://blog.rust-lang.org/2022/06/30/Rust-1.62.0.html · https://matklad.github.io/2020/01/04/mutexes-are-faster-than-spinlocks.html · https://github.com/Amanieu/parking_lot

## A6. Read-mostly `Arc<RwLock<Config>>` -> `ArcSwap`

**Rule**: data read on every request and replaced rarely (config, routing table, feature flags, TLS certs) lives in `arc_swap::ArcSwap<T>`; writers build a new `T` and `store()` it; readers `load()`.
**Detect**: `Arc<RwLock<Config>>`/`Arc<Mutex<Config>>` where every call site does `.read().unwrap()` and writes happen only at startup or reload.

```rust
use arc_swap::ArcSwap;
use std::sync::Arc;
use std::time::Duration;

pub struct Config {
    pub timeout: Duration,
}

pub fn timeout(cfg: &ArcSwap<Config>) -> Duration {
    cfg.load().timeout
}

pub fn reload(cfg: &ArcSwap<Config>, fresh: Config) {
    cfg.store(Arc::new(fresh));
}

pub fn new_shared(initial: Config) -> Arc<ArcSwap<Config>> {
    Arc::new(ArcSwap::from_pointee(initial))
}
```

**Facts** (arc-swap performance docs): reads are lock-free (usually wait-free) with no contention between readers; writes are more expensive than an uncontended `Mutex` but win under contention. `load()` borrows a per-thread slot (cheap); hold long-lived values with `load_full()`; `arc_swap::Cache` speeds repeated reads. Frequent read-modify-write by many writers is the wrong workload (each write clones).
**Version**: arc-swap 1.9. Source: https://docs.rs/arc-swap/latest/arc_swap/docs/performance/index.html

## A7. Contended `Mutex<HashMap>`: shorten, shard, then a concurrent map

**Rule ladder**, cheapest first:
1. Shorten the critical section: compute outside the lock, clone an `Arc`/`Bytes` out, never hold it across I/O or `.await`.
2. Shard: `Box<[Mutex<HashMap<K, V>>]>` indexed by `hash(key) & (n - 1)`. The Tokio tutorial lists sharding, a dedicated owner task, and restructuring as the fixes for contention, not switching to `tokio::sync::Mutex`.
3. `dashmap` 6.2 (sharded `RwLock<HashMap>`, `&self` API) for mixed workloads.
4. `papaya` 0.2 for read-heavy: reads never block, incremental resizing, lower tail latency than dashmap in its own benchmarks; update-heavy workloads pay allocator and reclamation overhead.
5. `scc` 3.8 for async-aware containers (`*_async` methods).

**Detect**: `Arc<Mutex<HashMap<..>>>` shared by many tasks; `futex_wait` in the profile; a guard held across `.await`.

```rust
use std::collections::HashMap;
use std::hash::{BuildHasher, Hash, RandomState};
use std::sync::Mutex;

pub struct Sharded<K, V> {
    shards: Box<[Mutex<HashMap<K, V>>]>,
    hasher: RandomState,
}

impl<K: Hash + Eq, V> Sharded<K, V> {
    pub fn new(shards: usize) -> Self {
        assert!(shards.is_power_of_two());
        let shards = (0..shards).map(|_| Mutex::new(HashMap::new())).collect();
        Self { shards, hasher: RandomState::new() }
    }

    fn shard(&self, k: &K) -> &Mutex<HashMap<K, V>> {
        let h = self.hasher.hash_one(k) as usize;
        &self.shards[h & (self.shards.len() - 1)]
    }

    pub fn insert(&self, k: K, v: V) -> Option<V> {
        self.shard(&k).lock().unwrap().insert(k, v)
    }
}
```

**DashMap pitfalls**: methods "may deadlock if called when holding any sort of reference into the map"; issue #369 documents a cross-shard deadlock between a held `Ref` and an `insert`. Never hold a `Ref`/`RefMut`/iterator across another map call or an `.await`; copy the value out and drop the guard. `with_shard_amount` (power of two) tunes contention.
**Caveat**: sharding does not help hot-key skew and breaks cross-key atomicity. A plain `Mutex<HashMap>` is often fastest at low contention.
Sources: https://tokio.rs/tokio/tutorial/shared-state · https://docs.rs/dashmap/latest/dashmap/struct.DashMap.html · https://github.com/xacrimon/dashmap/issues/369 · https://github.com/ibraheemdev/papaya

## A8. `RwLock` is not a free upgrade from `Mutex`

**Rule**: `RwLock` pays off only when read sections are long enough to overlap, reads vastly outnumber writes, and there are many reader threads. For nanosecond-scale reads a `Mutex` is as fast or faster: more state, more expensive atomics, and the reader count still bounces one cache line.
**Detect**: `RwLock` around a small struct or counter; `read()` then drop then `write()` "upgrade"; same-thread recursive `read()`.
**Facts** (std docs): the priority policy is OS-dependent and unspecified; a waiting writer may block new readers, so recursive `read()` on one thread "may deadlock". `RwLockWriteGuard::downgrade` (1.92) converts write -> read without releasing. parking_lot's `RwLock` is task-fair with upgradable reads.
**Fixes**: `Mutex`, `ArcSwap` (A6), sharding, per-thread copies.
Source: https://doc.rust-lang.org/std/sync/struct.RwLock.html

## A9. Per-thread accumulation, then merge

**Rule**: when threads only produce results (counts, histograms, buffers), accumulate per thread and merge after join; no lock or atomic traffic at all.
**Detect**: `Arc<Mutex<Vec<_>>>` pushed from workers; `Arc<Mutex<HashMap<_, usize>>>` counters; a `static` atomic bumped in a tight inner loop (cache-line ping-pong even though it is atomic).

```rust
use rayon::prelude::*;
use std::collections::HashMap;

pub fn histogram(items: &[u32]) -> HashMap<u32, u64> {
    items
        .par_iter()
        .fold(HashMap::new, |mut m, &x| {
            *m.entry(x % 16).or_insert(0u64) += 1;
            m
        })
        .reduce(HashMap::new, |mut a, b| {
            for (k, v) in b {
                *a.entry(k).or_insert(0) += v;
            }
            a
        })
}
```

`thread_local!` with `Cell`/`RefCell` (`with_borrow_mut` since 1.73) or the `thread_local` crate (per-object storage, iterate all values afterwards) covers non-rayon code.
**Caveat**: TLS has a small per-access cost; in async runtimes TLS is per worker thread, not per task.

## A10. Channels

**Rule**: plain worker pipelines: `std::sync::mpsc` (crossbeam-based since 1.67). Need MPMC, `select!`, bounded try/timeout variants or `Receiver: Clone`: `crossbeam-channel` 0.5. One channel type with sync and async ends: `flume` 0.12. Async-only: `tokio::sync::mpsc`; for a sync -> async bridge use tokio mpsc with `blocking_send`/`blocking_recv`. Never call a blocking `recv()` inside async code.
**Detect**: `Arc<Mutex<Receiver<_>>>` to fake MPMC; `Arc<Mutex<VecDeque<_>>>` + `Condvar` hand-rolled queues; unbounded channels where producers outrun consumers; `crossbeam_channel::Receiver::recv` inside an `async fn`.

```rust
pub fn bridge(rx: crossbeam_channel::Receiver<u64>, tx: tokio::sync::mpsc::Sender<u64>) {
    std::thread::spawn(move || {
        while let Ok(job) = rx.recv() {
            if tx.blocking_send(job * 2).is_err() {
                break;
            }
        }
    });
}
```

**Caveat**: no current cross-crate benchmark was found; do not claim one channel is N times faster. Batching (send `Vec<T>` chunks) beats switching crates. `kanal` 0.1 claims the top spot in its own benchmarks but is pre-1.0 with no release since 2025-03.
Sources: https://blog.rust-lang.org/2023/01/26/Rust-1.67.0/ · https://docs.rs/tokio/latest/tokio/sync/mpsc/index.html

## A11. `LazyLock` / `OnceLock` instead of `lazy_static` / `once_cell`

**Rule**: `static X: LazyLock<T> = LazyLock::new(|| ..)` (1.80) for lazy statics; `OnceLock` (1.70) for set-once cells; `LazyCell`/`OnceCell` single-threaded. Drop `lazy_static!` and most `once_cell` uses.
**Detect**: `lazy_static!` or `once_cell::sync::{Lazy, OnceCell}` with MSRV >= 1.80; `Regex::new` inside a per-request function.

```rust
use std::collections::HashMap;
use std::sync::LazyLock;

static TABLE: LazyLock<HashMap<&'static str, u32>> =
    LazyLock::new(|| HashMap::from([("a", 1), ("b", 2)]));
```

**Facts** (std docs): deref blocks while another thread initializes; an init panic poisons the `LazyLock` permanently. Each access is an acquire load (a plain load on x86); hoist `let t = &*TABLE;` out of an inner loop anyway. Keep `once_cell` only for MSRV < 1.80 or its `race` module. `OnceLock::wait` (1.86) blocks until another thread initializes.
Source: https://doc.rust-lang.org/std/sync/struct.LazyLock.html

## A12. Short critical sections; no std guard across `.await`

**Rule**: lock, copy or clone out what you need, unlock, then do the slow work (I/O, allocation, formatting, logging, callbacks). In async code `std::sync::Mutex` is correct for short sync sections; a `std::sync::MutexGuard` must not live across `.await`. `tokio::sync::Mutex` is more expensive and only for guards that genuinely span an await; a dedicated owner task is often better still.
**Detect**: `let g = m.lock().unwrap(); ... .await`; Clippy `await_holding_lock`, `await_holding_refcell_ref`. Guards that are `Send` (parking_lot `send_guard` feature) compile and deadlock instead of failing.

```rust
use std::sync::Mutex;

pub struct State {
    pub count: u64,
    pub url: String,
}

async fn fetch(url: &str) -> usize {
    url.len()
}

pub async fn step(state: &Mutex<State>) -> usize {
    let url = {
        let mut g = state.lock().unwrap();
        g.count += 1;
        g.url.clone()
    };
    fetch(&url).await
}
```

An inner `{ }` block is the clearest style and works on every version. Explicit `drop(guard)` before the await still fails the `Send` check that `tokio::spawn` requires (verified on rustc 1.99.1, editions 2021 and 2024); the Tokio tutorial is right. Use the inner block.
Source: https://tokio.rs/tokio/tutorial/shared-state

## A13. Spin locks: anti-pattern checklist

Flag any `spin::Mutex` or hand-written `AtomicBool` spin loop in std-using application code. If truly needed: bounded spin with `std::hint::spin_loop()`, then `std::thread::yield_now()` or a futex/park. Evidence and rationale in A5.
