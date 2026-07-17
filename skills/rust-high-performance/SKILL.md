---
name: rust-high-performance
description: Optimize Rust speed, memory, binary size, and compile times — measure-first profiling, release build config (LTO, codegen-units, PGO, alternative allocators), reducing heap allocations, shrinking type sizes, faster hashers, buffered I/O, and rayon parallelism. Use when profiling shows a hot path or when tuning a Rust program for speed, memory, or size.
---

# High-Performance Rust

Techniques from *The Rust Performance Book* (Nethercote) to improve runtime speed, memory usage, binary size, and compile time. Many are build-config only; many require code changes.

## Measure first — never guess

Optimize against data, not intuition. Profile to find the hot spot, change one thing, re-measure.

- **Benchmark** with `Criterion` or `Divan` (`divan-rust` skill) for in-process micro/workload benchmarks; `hyperfine` for whole-program wall-time; `Bencher`/CI for regression tracking. Built-in `#[bench]` needs nightly. Prefer realistic workloads over microbenchmarks; metrics like instruction counts have lower variance than wall-time.
- **Profile** to locate hot code and allocations. CPU/time: `samply`, `perf`, `cargo flamegraph`, `hotpath-rust` (this repo). Heap: `DHAT`, `heaptrack`, `bytehound`. Tokio stalls: `hud-tokio-profiler` (this repo).
- Always re-measure after a change — effects (especially inlining) are unpredictable and sometimes negative.

```toml
# Get usable profiles from optimized builds: keep debug info in release.
[profile.release]
debug = true   # line tables for profilers; does not slow the binary
```

## Build configuration (free wins, no code change)

`Cargo.toml` `[profile.release]` tuning. These trade compile time for runtime/size.

```toml
[profile.release]
codegen-units = 1   # less parallelism, better optimization (default 16)
lto = "thin"        # cross-crate inlining; "fat" optimizes more but builds slower
panic = "abort"     # smaller/faster; removes unwinding (no catch_unwind)
```

- **`codegen-units = 1`** — slower build, faster code.
- **LTO** — `lto = "thin"` is a good default; `lto = "fat"` (or `true`) maximizes runtime speed and shrinks size at higher build cost.
- **`target-cpu`** — compile for the actual CPU to unlock SIMD/AVX etc. Hurts portability of the binary:
  ```bash
  RUSTFLAGS="-C target-cpu=native" cargo build --release
  ```
  Or pin a baseline (e.g. `x86-64-v3`) in `.cargo/config.toml` `[build] rustflags`. **Warning:** a `native`-built binary run on an older/different CPU crashes with "illegal instruction" — the #1 gotcha when sharing binaries or building in CI. Pin a baseline for any distributed artifact.
- **Profile-Guided Optimization (PGO)** — build instrumented, run representative workloads, rebuild with the profile (`cargo-pgo`). Worth it for CPU-bound programs.

**Recipes:** max speed → `codegen-units = 1`, `lto = "fat"`, an alternative allocator, `panic = "abort"`. Min size → add `opt-level = "z"` (or `"s"`) and `strip = "symbols"`.

### Alternative allocators

Replacing the system allocator can yield large speed/memory wins (varies by program/platform; increases binary size + build time).

```toml
[dependencies]
tikv-jemallocator = "0.5"   # jemalloc — Linux/Mac
# mimalloc = "0.1"          # mimalloc — many platforms
```
```rust
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;
// jemalloc + THP on Linux: build with MALLOC_CONF="thp:always,metadata_thp:always"
```

### Minimizing binary size

`opt-level = "z"` (smallest) or `"s"`, `lto = true`, `codegen-units = 1`, `panic = "abort"`, `strip = "symbols"`. Inspect with `cargo bloat` / `twiggy`.

## Reducing heap allocations

Allocations are a common hidden cost. Profile with DHAT to find hot allocation sites, then:

- **Pre-size collections** — `Vec::with_capacity(n)` / `String::with_capacity(n)` / `HashMap::with_capacity(n)` when the size is known, to avoid reallocation during growth. Use `reserve`/`reserve_exact` mid-stream. `shrink_to_fit` to release slack.
- **Reuse collections** across iterations: `vec.clear()` then refill keeps the allocation instead of dropping and reallocating.
- **Avoid needless owning** — accept `&str`/`&[T]`, defer `.clone()`/`.to_owned()`/`.to_vec()`. Use `Cow<'a, T>` when a value is *usually* borrowed but *occasionally* owned (e.g. conditional modification) — clone only when you actually mutate.
- **Box large, rare data** — move a large enum variant or struct field behind `Box<T>` so the common case stays small (see Type sizes).
- **`SmallVec<[T; N]>`** (smallvec crate) — stores up to N elements inline on the stack, spilling to the heap only when exceeded; a drop-in `Vec` replacement for many-short-vectors workloads. (Trade-off: larger stack size, slight overhead.)
- **Reading lines** — `BufRead::lines()` allocates a `String` per line. To avoid it, reuse one buffer with `BufRead::read_line(&mut buf)` (clearing between lines), or iterate `read_until`/`split` over raw bytes.

## Shrinking type sizes

Smaller types reduce memory traffic and cache pressure; types over **128 bytes** are copied with `memcpy` rather than inline. Find big types/allocations with DHAT (incl. copy-profiling) and:

```bash
RUSTFLAGS=-Zprint-type-sizes cargo +nightly build --release   # exact layout per type
```

- **Field ordering** — Rust already reorders struct fields to minimize padding (don't fight it), but watch enum/`#[repr(C)]` cases.
- **Smaller enums** — one oversized variant inflates the whole enum (it's sized for the largest variant + discriminant). `Box` the big variant so the enum shrinks to a pointer.
- **Smaller integers** — use `u32`/`u16`/`u8` where the range allows instead of `usize`/`u64`.
- **Boxed slices / `ThinVec`** — `Box<[T]>` drops `Vec`'s capacity word; `ThinVec` (thin_vec crate) stores len+cap on the heap so the handle is one pointer — good for many rarely-large vectors stored in structs.

## Faster hashing

The default `HashMap`/`HashSet` hasher (SipHash 1-3) is DoS-resistant but slow for short keys. If hashing is hot **and** untrusted input/HashDoS is not a concern:

- **`rustc-hash`** → `FxHashMap`/`FxHashSet` — very fast, especially for integer keys (used inside rustc). Drop-in replacements.
- **`ahash`** → `AHashMap` — uses AES instructions where available.
- **`fnv`** → `FnvHashMap` — higher quality than fxhash, a bit slower; good for small keys.

```rust
use rustc_hash::FxHashMap;
let mut m: FxHashMap<u32, Val> = FxHashMap::default();
```
Try more than one — the win is program-specific. Use Clippy's `disallowed-types` to ban accidental use of the default `HashMap` once you standardize on an alternative.

## Hot-path standard-library idioms

- **`collect`/`extend`** — give the iterator a known size (`ExactSizeIterator`) so the target collection pre-allocates; `extend` into an existing collection beats `collect` + concatenate.
- **`Option`/`Result`** — are cheap; prefer them over sentinel values, but watch their size in hot enums.
- **`Rc`/`Arc`** — refcount updates are atomic for `Arc` (slower); use `Rc` when single-threaded, and clone the *contents* rather than bumping refcounts in tight loops where appropriate.
- **Bounds checks** — slice/`Vec` indexing is bounds-checked. Help the optimizer elide them: iterate (`for x in &v`, `.iter()`) instead of indexing, hoist a `let slice = &v[..n];` before a loop, or use `.get_unchecked()` **only** with a proven-safe `// SAFETY:` invariant.
- **`copied`/`cloned`** — `iter().copied()` over `Copy` items avoids reference indirection in chains.

## I/O — lock and buffer

```rust
use std::io::{BufWriter, Write};
// 1. Lock once: print!/println! lock stdout on EVERY call.
let stdout = std::io::stdout();
let mut out = BufWriter::new(stdout.lock());   // 2. Buffer: file I/O is unbuffered by default
for line in &lines { writeln!(out, "{line}")?; }
out.flush()?;                                   // make flush errors explicit
```
Use `BufReader`/`BufWriter` around files and sockets to coalesce syscalls; lock `stdout`/`stderr`/`stdin` once for repeated ops. For parsing, reading raw bytes (`Read`/`BufRead` over `&[u8]`) avoids UTF-8 validation cost vs `String` lines.

## Inlining

`#[inline]` hints across crate boundaries (within a crate the compiler already inlines freely). It can speed up *or* slow down — always measure.

- `#[inline(always)]` / `#[inline(never)]` to force the decision in known cases.
- **Hot+cold split:** when a large function has one hot call site, split it into an `#[inline(always)]` core and an `#[inline(never)]` wrapper; call the core at the hot site, the wrapper at cold sites to avoid code bloat.
- **Outlining:** move rarely run code into a `#[cold]` function so the hot path generates tighter code.

## Parallelism

Use **`rayon`** for data parallelism — `par_iter()`/`par_iter_mut()`/`par_sort()` are near drop-in for iterator chains over large collections. `crossbeam` for scoped threads and channels. Parallelism multiplies throughput but adds overhead and contention — measure that the work per item justifies it, and watch shared-state locking.

## Reducing compile times

- **Faster linker** — `lld` or `mold` via `.cargo/config.toml` `rustflags = ["-C", "link-arg=-fuse-ld=mold"]`. `mold` is Linux-only; on macOS use the default linker or `lld` (`sold`/`zld` are discontinued).
- **Cranelift back-end** (`-Zcodegen-backend=cranelift`) for faster debug builds.
- **Parallel front-end** (`-Z threads=N`, nightly) speeds the front-end.
- Trim debug info in dev (`[profile.dev] debug = "line-tables-only"`), split heavy crates (the `prefer small crates` idiom), and use `cargo-bloat`/`cargo build --timings` / self-profile to find slow crates.

## Avoiding regressions

Lock in wins: add benchmarks to CI (Bencher/Criterion-in-CI), assert key type sizes with `const _: () = assert!(std::mem::size_of::<T>() <= N);`, and ban regressions (default hasher, owning types) via Clippy `disallowed-types`/`disallowed-methods`.

## Cross-references

- Benchmarking → `divan-rust` · Profiling → `hotpath-rust`, `hud-tokio-profiler`
- General style → `rust-conventions`, `design-patterns-rust` · Async perf → `rust-async-conventions`, `tokio-rust`
