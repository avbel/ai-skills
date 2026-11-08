---
name: rust-high-performance
description: Write and audit the fastest Rust — measure-first profiling, release build config (LTO, codegen-units, PGO, allocators), inlining since 1.75, allocation and layout reduction, readable auto-vectorization and SIMD dispatch, locks and atomics, perf features through Rust 1.99, tokio/rayon/serde rules, binary size and compile times. Use for "make this Rust faster", "optimize hot loop", "reduce allocations", "blazing fast Rust", "audit Rust performance".
---

# High-Performance Rust

Current stable at the time of writing: Rust 1.99.1 (released 2026-10-15; checked 2026-11-08); 1.100 ships 2026-11-12. Techniques from *The Rust Performance Book*, std docs, the Rust Reference, release notes and 2026 ecosystem surveys. Most are build-config or local rewrites; all are hints to a compiler that already does well, so measure each one.

Reference files (read one when a checklist row points at it):

- `references/inlining-codegen.md` — rustc's inlining rules, `#[inline]`/`#[cold]`/`std::hint`, asm verification.
- `references/vectorization-simd.md` — writing loops LLVM vectorizes, float reductions, `#[target_feature]` dispatch, SIMD crates.
- `references/memory-layout.md` — allocation avoidance, struct/enum layout (measured sizes), SoA, false sharing, interning.
- `references/concurrency-locks.md` — atomics, orderings, Mutex vs RwLock vs ArcSwap, sharding, channels, LazyLock.
- `references/hot-path-idioms.md` — entry API, hashers, sorting, memchr, number formatting, dispatch, const tables, new Vec/slice APIs.
- `references/new-rust-features.md` — version tables of every perf-relevant feature 1.75 -> 1.101 nightly.
- `references/tokio-ecosystem.md` — tokio runtime, bytes, serde/binary formats, rayon, caches, HTTP, tracing.

## Measure first — never guess

Profile to find the hot spot, change one thing, re-measure. Effects (especially inlining and hints) are unpredictable and sometimes negative.

- **Benchmark**: `Criterion` or `Divan` (`divan-rust` skill) in-process; `hyperfine` for whole-program wall time; Bencher/CI for regression tracking. Instruction counts (Cachegrind) vary less than wall time. Criterion and Divan black-box the closure's return value and their generated/parameterized inputs; wrap literals and captured inputs you pass yourself in `black_box`.
- **Profile CPU**: `samply`, `perf`, `cargo flamegraph`, `hotpath-rust` skill. `perf stat -e cycles,instructions,branch-misses` confirms a branch-misprediction theory before you reach for `select_unpredictable`.
- **Profile heap**: DHAT (valgrind) or the `dhat` crate (also heap-usage assertions in tests), `heaptrack`, `bytehound`. A hot `malloc`/`free` frame is the signal for the allocation checklist.
- **Read the asm**: `cargo install cargo-show-asm`; `cargo asm --lib --rust path::to::fn` interleaves source, `--mca` runs llvm-mca, `--callers-of panic_bounds_check` lists functions with live bounds checks. Tiny functions vanish from the output since 1.75 (inlined away): add a `pub #[inline(never)]` probe wrapper in a bench or example.
- **Tokio stalls**: `hud-tokio-profiler` skill, tokio-console, `RuntimeMetrics`.

```toml
[profile.release]
debug = true   # line tables for profilers; does not slow the binary
```

## Build configuration (no code change)

```toml
[profile.release]
codegen-units = 1   # fewer units, better optimization (default 16)
lto = "thin"        # cross-crate inlining; "fat" optimizes more, builds slower
panic = "abort"     # NOT free: any panic aborts the process (see below)
```

- **`target-cpu`**: `RUSTFLAGS="-C target-cpu=native"` unlocks AVX2/AVX-512/NEON for the auto-vectorizer. A `native` binary dies with "illegal instruction" on an older CPU, the top gotcha when sharing binaries or building in CI. Pin a level (`x86-64-v3` = AVX2+FMA) for distributed artifacts or use runtime dispatch (checklist group 4). Benchmark `x86-64-v3` against `v4`/native: AVX-512 can be slower (downclocking on pre-Ice-Lake Intel, gather/scatter codegen).
- **`panic = "abort"`**: removes unwinding (smaller code, more leaf fns, so more auto-inlining), but a panic in any tokio task, axum handler or rayon job kills the whole process; `catch_unwind`, `JoinError::is_panic` and tower `CatchPanic` stop working and `Drop` cleanup is skipped. Only for binaries that already treat every panic as fatal.
- **PGO**: `cargo-pgo` — instrument, run representative workloads, rebuild. Worth it for CPU-bound programs (10 %+ reported).
- **Release vs dev**: evaluate inlining and vectorization only in release with `incremental = false`; incremental builds disable cross-crate inlining inference.

**Recipes**: max speed → `codegen-units = 1`, `lto = "fat"`, alternative allocator, `panic = "abort"` (if panics are fatal anyway), `target-cpu` or dispatch. Min size → `opt-level = "z"` (or `"s"`; `s` still vectorizes loops, `z` does not), `strip = "symbols"`; inspect with `cargo bloat`/`twiggy`.

### Alternative allocators

Replacing the system allocator can yield large speed/memory wins (program- and platform-dependent; larger binary, longer build).

```toml
[target.'cfg(not(target_env = "msvc"))'.dependencies]
tikv-jemallocator = "0.7"   # jemalloc — not available on MSVC
# mimalloc = "0.1"          # mimalloc — many platforms, incl. Windows
```
```rust
#[cfg(not(target_env = "msvc"))]
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;
// Tuning (e.g. THP) is a runtime env var; with tikv-jemallocator's prefixed symbols it is
// _RJEM_MALLOC_CONF, or embed it at build time with JEMALLOC_SYS_WITH_MALLOC_CONF.
```

## Code audit checklist

`You see → Do`; each group heading names its reference file. Allocation, layout and lock fixes usually pay off before inlining hints, which are often neutral. Numbers marked *measured* were run on rustc 1.99.1 (M2 Max); magnitudes are indicative, patterns are portable.

### 1. Inlining — `references/inlining-codegen.md`

| You see | Do |
|---|---|
| Small leaf `pub fn` in a library (getter, `len`, newtype `From`, `Deref`) with `#[inline]` "for cross-crate speed" | Since 1.75 rustc auto-inlines small *leaf* non-generic fns across crates in optimized non-incremental builds; the attribute is only insurance or MSRV < 1.75 |
| Small `pub fn` used cross-crate that still shows up as a real call in the consumer's asm (its callee survived MIR inlining: too big, `#[inline(never)]`, or a non-inline fn of another crate) | `#[inline]` on it and on the callees that block inlining (not transitive); confirm in asm first, since calls to small private helpers are usually MIR-inlined and the fn stays leaf |
| `#[inline]` on every private method, or on big bodies | Remove; within a crate LLVM already decides. Use `lto`/`codegen-units = 1` instead of sprinkling attributes |
| `#[inline(always)]` on anything but a tiny hot leaf | Downgrade to `#[inline]` or remove; forbidden together with `#[target_feature]` |
| Large fn with one hot call site and several cold ones | `#[inline(always)]` core + `#[inline(never)]` wrapper |
| `panic!("...{}")`, `format!`, `Err(String)` construction, grow path inside a hot fn | Outline into `#[cold] #[inline(never)] fn` returning `!` or the error; or `std::hint::cold_path()` (1.95) at the top of the rare arm |
| `pub fn f(p: impl AsRef<str>)` with a big body | Thin generic shim calling a non-generic inner fn |
| A hint you cannot prove helps | `cargo asm`, benchmark, keep the benchmark; drop the hint if neutral |

### 2. Allocation — `references/memory-layout.md` Part A

| You see | Do |
|---|---|
| `Vec::new()`/`String::new()` then a push loop with a known or estimable size | `with_capacity(n)` / `reserve(n)` (*measured*: 100 pushes = 6 allocs → 1) |
| `Vec::new()`, `String::new()`, `format!` inside a loop body or per-call fn | Hoist the buffer, `clear()` per iteration; return through `&mut Vec<T>`; `clone_from` onto an existing allocation |
| `format!`/`to_string()` in a loop; `s.push_str(&format!(..))` | `use std::fmt::Write; write!(buf, ..)` into one reused `String` (*measured*: 100 allocs → 1); `itoa` or std `format_into` (1.98) for integers |
| `BufRead::lines()` in a hot loop | One `String` + `read_line` + `clear()`; or `read_until`/`split` over bytes |
| `Vec<T>` holding data of a fixed, known length | `[T; N]`; hard upper bound → `arrayvec::ArrayVec`/`heapless::Vec`; usually small → `smallvec::SmallVec` 1.x (2.0 is beta) |
| `String`/`Vec<T>` field that is never grown after construction | `Box<str>` / `Box<[T]>` (24 → 16 B); widely cloned read-only → `Arc<str>` (*measured* struct: 80 → 56 B) |
| Many short strings (ids, tags, keys) | `compact_str` (0.10), `smol_str` (0.3); repeating strings → intern (`lasso` 0.7, 4-byte key) |
| `"literal".to_string()` in some branches, `format!` in others | `Cow<'static, str>` (same 24 B as `String`) |
| Millions of tiny objects that die together (AST, per-request, per-frame) | Arena (`bumpalo` 3.20; `Drop` is not run, keep data POD or use `bumpalo::boxed::Box`) |
| `let x = self.buf.clone(); self.buf.clear();` or `.clone()` only to satisfy the borrow checker | `mem::take` / `mem::replace` / `mem::swap` / `Option::take` |
| `.collect::<Vec<_>>()` immediately iterated again; `v.append(&mut xs.collect())` | Return `impl Iterator`; `extend` the existing collection; `into_iter().map().collect()` often reuses the source allocation (observed, not guaranteed) |
| `Box::new([0u8; N])` overflowing the stack (debug builds only; `-O` turns it into `calloc`) | `vec![0u8; n].into_boxed_slice()` (safe, one zeroed allocation); `new_zeroed_slice` (1.92) + `unsafe assume_init` only for `Rc`/`Arc` or non-`Vec` cases |

### 3. Layout — `references/memory-layout.md` Part B, C

| You see | Do |
|---|---|
| Manual field ordering on a default-repr struct | Nothing: `repr(Rust)` already reorders to minimize padding (*measured* `u8,u64,u8,u32` → 16 B) |
| `#[repr(C)]` struct with mixed field sizes | Order fields by descending alignment yourself (*measured* 24 → 16 B); question why it is `repr(C)` |
| Enum with one big variant; `Vec<Enum>` or `Result<T, BigError>` surprisingly large; Clippy `large_enum_variant` (default threshold 200 B) | `Box` the rare large payload (*measured* 108 → 16 B). Types over 128 B move via `memcpy` |
| `Option<u32>` / `Option<usize>` index fields; `u32::MAX` sentinels | `Option<NonZeroU32>` is 4 B vs 8 B; store index+1 or `nonmax::NonMaxU32`; niches are guaranteed only for `NonZero*`, references, `Box`, `NonNull`, fn pointers |
| `usize`/`u64` indices or counts in a type with millions of instances | `u32`/`u16`/`u8`, widen at use sites; `NonZeroU32` newtypes for ids |
| Bulk-stored enum (tokens, bytecode) above 16 B | Aim for 8-16 B (heuristic): indices or interned ids instead of `String`, `u32` payloads (*measured* 24 → 16 → 8 B) |
| `#[repr(u8)]` added to a default enum "to shrink it" | It never shrinks a `repr(Rust)` enum (fieldless enums are already 1 B); `repr(u8)`/`repr(C, u8)` only shrink C-like enums |
| A tuned type with no size guard | `const _: () = assert!(size_of::<T>() == N);` gated by `cfg(target_pointer_width)`; inspect with `RUSTFLAGS=-Zprint-type-sizes cargo +nightly build` and `top-type-sizes` |
| Loop touching 1-3 fields of a >= 64 B struct in `Vec<Struct>` | SoA or hot/cold split, then measure: *measured* 3.3x faster for a 128 B struct reading one field, but 25 % **slower** for a 64 B struct using 4 of 9 fields |
| Per-thread atomics or `head`/`tail` fields adjacent in memory | `crossbeam_utils::CachePadded` or `#[repr(align(128))]` (*measured* 651 → 41 ms) |
| `Rc<RefCell<Node>>` / `Box<Node>` graphs and trees | `u32` indices into a `Vec` arena (`NonZeroU32` newtype; `slotmap` for generations) |
| 4+ `bool` fields in bulk data | `bitflags` (2.13) or `modular-bitfield`; pack only cold/bulk data |

### 4. Vectorization (readable, no intrinsics) — `references/vectorization-simd.md`

| You see | Do |
|---|---|
| `for i in 0..n { a[i] .. b[i] }`; asm shows `panic_bounds_check` in the loop | `iter()`/`zip`/`fold`; if indexing stays, reslice `let b = &b[..a.len()];` or `assert_eq!` lengths once before the loop; hoist `self.v` into a local slice |
| Reduction or elementwise loop with a big scalar prologue/epilogue | `as_chunks::<N>()` (1.88) or `chunks_exact(N)` + `remainder()`; `array_windows::<N>()` (1.94) for sliding windows |
| `break`/`return`/`?`/`&&` inside a byte or int scan (`position`, `any`, `take_while`) | Test a whole chunk with non-short-circuit `&`, branch once per chunk, scalar tail (matklad: 650 → 80 ms); real byte search → `memchr` (2.8) |
| `f32`/`f64` `+=`, `sum()`, dot product; asm shows `addss`/`addsd` | `algebraic_add` (1.98; never UB, but no NaN/Inf/-0.0 guarantees and non-deterministic even between two identical calls) or 8-32 independent accumulators via `as_chunks` (deterministic) |
| `if`/`match`/`continue` per element | Branchless body: `if c { a } else { b }` on side-effect-free scalars, `min`/`max`/`clamp`, `(x > t) as u32` |
| Integer loop where `overflow-checks` blocks vectorization | `wrapping_*` only when modular arithmetic is the intent (hash, PRNG, checksum); otherwise widen the accumulator (`i64`/`u64`) or validate bounds once outside the loop. Never switch off a project's `overflow-checks` (see `rust-conventions`) |
| `Vec<Vec<T>>` in a numeric kernel; `&Cell<T>`/raw pointers in the loop | Flat `Vec<T>` with stride; `&mut [T]` + `&[T]` params give `noalias` |
| One binary for heterogeneous x86 fleets | `multiversion` 0.9 (MSRV 1.86) on the function that contains the loop, or `#[target_feature(enable = "avx2,fma")]` fn (safe since 1.86) + `is_x86_feature_detected!` once at the outer loop with an `#[inline(always)]` generic body |
| `std::simd` in a stable project | Still nightly-only; use the above or `fearless_simd` 1.2 / `pulp` 0.22 / `wide` 1.7 (no dispatch) |
| Any of the above | Verify in `cargo asm`: packed `vaddps`/`ymm` not `addss`; no `panic_bounds_check`; no `vgather*` |

### 5. Locks and atomics — `references/concurrency-locks.md`

Preference ladder: owned by one thread → per-thread accumulate + merge → message passing / owner task → `ArcSwap` snapshot → atomics → sharded or concurrent map → `std::sync::Mutex` with a short critical section → last resort `RwLock`, spin.

| You see | Do |
|---|---|
| `Mutex<u64>`, `Mutex<bool>`, one-line guard scopes | `AtomicU64`/`AtomicBool` with `Relaxed` for pure statistics; `Release`/`Acquire` when the value publishes other data |
| `Ordering::SeqCst` everywhere | Weakest correct ordering. x86-64: only `SeqCst` *stores* cost extra; ARM64: `Relaxed` is cheaper than everything else, so wrong `Relaxed` code passes on x86 and fails on ARM. Model-check with `loom` |
| `load` + `compare_exchange` loop doing an unconditional `+1` | `fetch_add`; conditional updates via `Atomic*::update`/`try_update` (1.95) or `fetch_update` |
| `Arc<RwLock<Config>>` read per request, written at startup/reload | `arc_swap::ArcSwap` (1.9): lock-free reads, no reader contention |
| `Arc<Mutex<HashMap>>` shared by many tasks | Shorten the critical section → shard `Box<[Mutex<HashMap>]>` by hash → `dashmap` 6.2 (never hold a `Ref` across another map call or `.await`) or `papaya` 0.2 (read-heavy) |
| `RwLock` around a small struct or counter | `Mutex` or `ArcSwap`; `RwLock` pays only for long reads, many readers, rare writes. Recursive `read()` may deadlock (OS policy unspecified) |
| Workers pushing into `Arc<Mutex<Vec<_>>>`; a static atomic bumped in an inner loop | Per-thread accumulate and merge: rayon `map`/`collect` or `fold`/`reduce`, `thread_local!` |
| `[AtomicU64; N]` indexed by thread id | Pad onto separate cache lines (group 3, *measured* 16x) |
| `lazy_static!` / `once_cell::sync::Lazy` with MSRV >= 1.80 | `std::sync::LazyLock` / `OnceLock`; an init panic poisons a `LazyLock` permanently |
| `spin::Mutex` or `while x.swap(true, ..) {}` in application code | `std::sync::Mutex`; spin only when preemption is impossible |
| `std::sync::MutexGuard` alive across `.await`; Clippy `await_holding_lock` | Lock, clone out, unlock in an inner `{ }` block, then await; `tokio::sync::Mutex` only when the guard must span the await |
| `parking_lot` adopted "for speed" | std is futex-based on Linux since 1.62 and the Perf Book says measure before switching; pick parking_lot for its features (no poisoning, 1-byte, fair, upgradable `RwLock`) or with a benchmark, then ban `std::sync::Mutex` via Clippy `disallowed-types` so families do not mix |

### 6. Hot-path idioms — `references/hot-path-idioms.md`

| You see | Do |
|---|---|
| `contains_key` + `insert`; `get_mut` else `insert` | `entry(k).or_insert_with(..)`; for borrowed `String` keys `hashbrown::HashMap::entry_ref` |
| Default `HashMap` with short or integer keys hot in the profile, no HashDoS exposure | `rustc_hash::FxHashMap` (2.1), `foldhash` (0.2, hashbrown's default), `ahash` (0.8, slower-moving); ban the default with Clippy `disallowed-types` |
| `.sort()` on primitives; `sort_by_key` with an allocating key; `partial_cmp().unwrap()` on floats | `sort_unstable*`; `sort_by_cached_key`; `total_cmp`. Since 1.81 (driftsort/ipnsort) both sorts may panic on an inconsistent `Ord` |
| `n.to_string()` / `format!("{}", n)` per record in a serializer | `itoa::Buffer` (1.0), `zmij`/`ryu` for floats, or std `<int>::format_into` + `fmt::NumBuffer` (1.98) |
| `Vec<Box<dyn Trait>>` iterated per frame/request over a closed set | Generics or a hand-written enum with `match` (the `enum_dispatch` crate generates it) |
| `LazyLock<[u8; 256]>` or startup code building a pure table | `const fn` into a `static` array; `u8` index into 256 entries needs no bounds check |
| `v.remove(i)` in a loop; `v = v.into_iter().filter(..).collect()`; `partition` to split out matches | `retain`, `swap_remove`, `Vec::extract_if` (1.87) in place |
| `v.push(x); v.last_mut().unwrap()`; `split_at_mut` to get two `&mut` | `push_mut` (1.95); `get_disjoint_mut([i, j])` (1.86) |
| Index arithmetic while parsing a `&[u8]` cursor | `split_off(..n)` / `split_off_first()` (1.87); `split_first_chunk::<N>()` for fixed headers |
| Data-random 50/50 branch (binary search, partition) with high `branch-misses` | `std::hint::select_unpredictable` (1.88); slower if the branch is predictable |
| Invariant the optimizer cannot see, after reslicing failed | `std::hint::assert_unchecked` (1.81) with a `// SAFETY:` comment and a kept benchmark; UB if false |
| `haystack.iter().position(|&b| b == x)` on large inputs | `memchr::memchr`/`memchr2`/`memmem::Finder` (reuse the finder) |
| Hashing or PRNG written with plain `+`/`*` | `wrapping_*` (no debug panic, same release codegen) |

## Newer Rust features for speed

| Feature | Since | Use for |
|---|---|---|
| Auto cross-crate inlining of small leaf fns | 1.75 | drop most `#[inline]` on leaf getters (release, non-incremental) |
| driftsort / ipnsort | 1.81 | faster `sort`/`sort_unstable`; may panic on a bad `Ord` |
| `hint::assert_unchecked` | 1.81 | state invariants for bounds-check elision (unsafe) |
| `<[T]>::get_disjoint_mut`, `HashMap::get_disjoint_mut` | 1.86 | two `&mut` into one collection without `split_at_mut` |
| Safe `#[target_feature]` fns / safe non-pointer `std::arch` intrinsics | 1.86 / 1.87 | SIMD kernels without `unsafe` inside the feature region |
| `Vec::extract_if` (`HashMap` 1.88, `BTreeMap` 1.91) | 1.87 | remove-and-yield in place |
| `<[T]>::split_off`, `split_off_first/last` | 1.87 | shrinking slice cursors for parsers |
| `<[T]>::as_chunks` / `as_chunks_mut` | 1.88 | compile-time chunk width for the vectorizer |
| `hint::select_unpredictable` | 1.88 | branchless select |
| `lld` default linker on x86_64 Linux | 1.90 | faster links with no config |
| `Box/Rc/Arc::new_zeroed(_slice)` | 1.92 | zero-page allocation of large buffers |
| `<[T]>::array_windows` | 1.94 | fixed-size sliding windows without bounds checks |
| `hint::cold_path` | 1.95 | mark unlikely arms inline |
| `Vec::push_mut` / `insert_mut` | 1.95 | `&mut` to the pushed element, no re-lookup |
| `Atomic*::update` / `try_update` | 1.95 | CAS loops without ordering boilerplate |
| `f32/f64::algebraic_{add,sub,mul,div,rem}` | 1.98 | vectorizable float reductions |
| `<int>::format_into` + `fmt::NumBuffer` | 1.98 | allocation-free integer formatting close to `itoa` |
| LLVM 23 | 1.99 | newer vectorizer; re-benchmark after upgrading |

Coming in 1.100 (2026-11-12): the `Allocator` trait; check the 1.100 release notes for which `Vec`/`Box` `*_in` constructors are stable before relying on it. Nightly only: `std::simd`, `hint::likely`/`unlikely`, explicit tail calls (`become`), the parallel front-end (`-Z threads`). Full tables and sources: `references/new-rust-features.md`.

## Tokio and ecosystem

Runtime basics are in `tokio-rust` and `rust-async-conventions`; this skill adds the performance rules. Detail, numbers and sources: `references/tokio-ecosystem.md`.

1. Spend at most 10-100 µs between `.await`s. Sustained CPU work → prefer `rayon::spawn` + `oneshot` (catch panics: `rayon::spawn` aborts the process on panic by default); occasional CPU bursts → `spawn_blocking` + `Semaphore` is fine; blocking I/O → `spawn_blocking` bounded by a `Semaphore` (pool of 512, queue unbounded).
2. `std::sync::Mutex` for short sync sections; `tokio::sync::Mutex` only when the guard spans an `.await`; an owner task with message passing is often better than either.
3. Bounded `mpsc::channel(n)` by default; drain with `recv_many`; `oneshot` for replies; unbounded only for sync → async bridges.
4. No `tokio::spawn` per tiny item: `buffer_unordered(n)` or `JoinSet` + `Semaphore`, sized to downstream capacity.
5. `Box::pin` large futures at the await site; tokio >= 1.41 auto-boxes only at `spawn` (> 16 KiB in release). Enable Clippy `large_futures`.
6. `current_thread` or `LocalRuntime` for CLIs and `!Send` state (`Rc<RefCell>` instead of `Arc<Mutex>`).
7. `interval` → `MissedTickBehavior::Skip`/`Delay` for periodic work; `BufReader`/`BufWriter` around async sockets; many small `tokio::fs` ops → one `spawn_blocking` with `std::fs`.
8. `Bytes`/`BytesMut::split_to(n).freeze()` for zero-copy framing and sharing; detach long-lived small slices with `copy_from_slice`.
9. serde_json: `from_slice` over `from_reader`; borrow `&str`/`#[serde(borrow)] Cow<str>`; typed structs over `Value`. simd-json gives about 1.2-1.5x on typical records in one independent benchmark (sonic-rs numbers are its own); try the cheap fixes first.
10. Consider a binary format for hot internal paths after measuring (versioned or on-disk data needs a schema-evolution story): bitcode 0.6, postcard 1.1, wincode 0.6, rkyv 0.8 (validated `access` for untrusted bytes). **bincode is unmaintained** (RUSTSEC-2025-0141, INFO; `3.0.0` is a `compile_error!` placeholder): pin `bincode = "=2.0.1"` and migrate.
11. One `reqwest::Client` (it is the connection pool) with timeouts; tune hyper HTTP/2 only with a measurement.
12. `tracing`: `release_max_level_*` features in the binary crate only; fields not `format!`; `#[instrument(skip_all)]` on hot fns; `tracing_appender::non_blocking` (lossy by default when its buffer fills; `NonBlockingBuilder::lossy(false)` applies backpressure).
13. rayon: `with_min_len`/`par_chunks` when items are cheap; one pool built at startup; never `par_iter` inside an `async fn`; `fold`/`reduce` instead of `Mutex<Vec>`.

Caches: `moka` 0.12 (TTL, listeners, stampede protection) or `quick_cache` 0.7 (minimal overhead, no TTL). Sibling skills: `tokio-rust`, `rust-async-conventions`, `moka-rust`, `reqwest-rust`, `axum-rust`, `tracing-rust`, `hud-tokio-profiler`, `hotpath-rust`.

## I/O — lock and buffer

```rust
use std::io::{BufWriter, Write};

fn dump(lines: &[String]) -> std::io::Result<()> {
    let stdout = std::io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    for line in lines {
        writeln!(out, "{line}")?;
    }
    out.flush()
}
```

`print!`/`println!` lock stdout on every call and file I/O is unbuffered by default: lock once, wrap in `BufReader`/`BufWriter`, flush explicitly. Parse raw bytes (`Read`/`BufRead` over `&[u8]`, `bstr`) to skip UTF-8 validation.

## Reducing compile times

- **Linker**: `lld` is the default on `x86_64-unknown-linux-gnu` since Rust 1.90 (ripgrep: incremental link 7x faster, ~40 % less incremental time); no configuration needed there. `mold` remains an optional Linux alternative via `.cargo/config.toml` `rustflags = ["-C", "link-arg=-fuse-ld=mold"]`. On macOS use the default linker or `lld`.
- **Cranelift back-end** (`-Zcodegen-backend=cranelift`, nightly) for faster debug builds; **parallel front-end** (`-Z threads=N`, nightly).
- `[profile.dev] debug = "line-tables-only"`; Cargo `build.build-dir` (1.91) on a fast disk; `build.warnings` (1.97) instead of `RUSTFLAGS=-Dwarnings` (keeps the cache valid); Cargo disables incremental under `CI` since 1.99.
- Split heavy crates; find slow ones with `cargo build --timings` and `cargo bloat`.

## Avoiding regressions

- Benchmarks in CI (Bencher, Criterion); `dhat` heap-usage assertions for allocation counts.
- `const _: () = assert!(std::mem::size_of::<T>() <= N);` on tuned types.
- Clippy: `large_enum_variant` (200 B default), `result_large_err`, `large_futures` (pedantic, 16 KiB), `await_holding_lock`, `await_holding_refcell_ref`, `needless_range_loop`, `map_entry`, `format_push_string` (pedantic); `disallowed-types` for the default `HashMap` or `std::sync::Mutex` once you standardize; `disallowed-methods` for `std::thread::sleep` and `std::fs::read*` in async crates.
- `cargo audit` for unmaintained dependencies (bincode).

## Cross-references

- Benchmarking → `divan-rust` · Profiling → `hotpath-rust`, `hud-tokio-profiler`
- Style → `rust-conventions`, `design-patterns-rust` · Async → `rust-async-conventions`, `tokio-rust` · Unsafe review → `rust-high-assurance`
- Sources: Rust Performance Book (nnethercote.github.io/perf-book), std docs, Rust Reference, RELEASES.md, Rust Atomics and Locks (mara.nl/atomics), Shnatsel "State of SIMD in Rust 2026", matklad, orlp, rust_serialization_benchmark; full URLs in the reference files.
