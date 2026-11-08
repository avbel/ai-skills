# Inlining, `std::hint`, and codegen verification

How rustc/LLVM decide what to inline, which attributes and hints change that, and how to check the result in assembly. Every hint here can slow code down; measure once per change, with `cargo asm` and a benchmark.

## How rustc decides today (read before adding any attribute)

- All four forms (`none`, `#[inline]`, `#[inline(always)]`, `#[inline(never)]`) are hints. `always` is honoured "in all but the most exceptional cases". Inlining is not transitive: if `f` calls `g` and both must inline at a call site, both need attributes.
- `#[inline]` is ignored on `#[no_mangle]`/`#[export_name]` functions. On `async fn`, honouring it on the generated `poll` is a 1.101 nightly change; do not rely on it on stable.
- Generic functions are implicitly inlinable (instantiated in the caller's crate). Before Rust 1.75 a non-generic function without `#[inline]` could never be inlined into another crate without LTO.
- **Rust 1.75**: small *leaf* non-generic functions are automatically cross-crate inlinable in optimized, non-incremental builds. Leaf means the MIR body makes no calls (bounds-check panics count as statements, not calls), has no unwind landing pads or non-trivial drops, and is under an internal size threshold. `#[inline(never)]` opts out and forces a real symbol. Incremental compilation (`incremental = true`) and `opt-level = 0` disable the inference, so dev-profile numbers differ from release.
- Within one crate, the MIR and LLVM inliners already decide by cost model; private functions rarely need attributes.

Sources: https://nnethercote.github.io/perf-book/inlining.html · https://doc.rust-lang.org/reference/attributes/codegen.html · https://matklad.github.io/2021/07/09/inline-in-rust.html · https://github.com/rust-lang/rust/pull/116505

## `#[inline]` on small `pub` non-leaf functions used cross-crate

**Rule**: in a library, a small non-generic `pub fn` stays leaf (auto-inlinable) if every call in it is MIR-inlined first: calls to small private helpers, `?`, bounds checks and arithmetic usually are. It fails the leaf test only when a call survives MIR inlining (a callee that is too big, `#[inline(never)]`, or a non-inline function of another crate) or it has drop glue. Then add `#[inline]` to it and to the callees that block inlining (not transitive).
**Detect**: hot cross-crate accessors, `Deref`/`AsRef`/`Index`/`From`/`Borrow` impls, newtype ops or `iter()` wrappers that show up as a real `call` in the **consumer crate's** release asm (`cargo asm`). Without that evidence, add nothing.

**Caveat**: each `#[inline]` function is codegen'd in every codegen unit that uses it (compile time, binary size). Do not blanket-annotate; in applications prefer `lto = "thin"|"fat"` and `codegen-units = 1` over sprinkling attributes. MSRV < 1.75 still needs `#[inline]` on leaf functions too.
**Min version**: any; auto behaviour 1.75.

## `#[inline(always)]` only for tiny, hot, leaf-ish functions

**Rule**: force inlining only when a profile shows call/return and prologue/epilogue overhead for a small function LLVM declined to inline. Cachegrind tell: a function is inlined iff its first and last source lines have no event counts.
**Detect against**: bodies over ~20-30 lines, many call sites, recursion, loops LLVM would unroll or vectorize separately, cold paths. Over-inlining bloats the i-cache and raises register pressure; the Perf Book notes that adding an attribute can even stop a neighbouring function from being inlined.

```rust
#[inline(always)]
pub fn rotl(x: u64, k: u32) -> u64 {
    x.rotate_left(k)
}
```

**Caveat**: `#[inline(always)]` is forbidden together with `#[target_feature]`; use `#[inline]` there.
Source: https://nnethercote.github.io/perf-book/inlining.html

## Hot/cold split: `#[inline(always)]` core + `#[inline(never)]` wrapper

**Rule**: a largish function with one hot call site and several cold ones gets an always-inlined core (called from the hot site) and a never-inlined wrapper (called everywhere else).
**Detect**: profile shows the same function called from a hot loop and from setup/error paths.

```rust
pub fn one() {}
pub fn two() {}
pub fn three() {}

#[inline(always)]
pub fn process_inlined() {
    one();
    two();
    three();
}

#[inline(never)]
pub fn process() {
    process_inlined()
}
```

**Caveat**: only worth it when the hot call site dominates. Perf Book examples: rust-lang/rust #53513, #64420.

## Outline cold code: `#[cold] #[inline(never)]`

**Rule**: move panics with formatting, `Err(String)` construction, `format!`, growth slow paths and rare fallbacks out of hot functions into a `#[cold] #[inline(never)]` helper. `#[cold]` tells the compiler the function is unlikely to be called, so the branch to it is laid out out-of-line.
**Detect**: hot function body contains `panic!("...{}...")`, `format!`, `String` building, lazy init, or a `Vec` grow path; the function is not inlined into callers because of that bloat.

```rust
pub struct Buf {
    data: Vec<u32>,
    len: usize,
}

#[cold]
#[inline(never)]
fn oob(i: usize, len: usize) -> ! {
    panic!("index {i} out of range for len {len}")
}

impl Buf {
    #[inline]
    pub fn get(&self, i: usize) -> u32 {
        if i >= self.len {
            oob(i, self.len);
        }
        self.data[i]
    }
}
```

**Caveat**: a `#[cold]` function that is called often is slower than a plain one. `panic!` already routes through a cold `panic_fmt`, so the win is for your own error constructors and non-diverging slow paths.
Source: https://nnethercote.github.io/perf-book/inlining.html (Outlining)

## Generic public fn: thin generic shim + non-generic inner

**Rule**: `pub fn f(p: impl AsRef<str>)` with a big body is instantiated per caller type. Keep the generic shim one line and put the body in a private non-generic function.
**Detect**: `impl AsRef<Path>`, `impl Into<String>`, `P: AsRef<..>` parameters on functions with large bodies; `cargo bloat` shows many copies.

```rust
pub fn parse_str(input: impl AsRef<str>) -> Result<Vec<u8>, String> {
    parse_str_inner(input.as_ref())
}

fn parse_str_inner(input: &str) -> Result<Vec<u8>, String> {
    Ok(input.as_bytes().to_vec())
}
```

Source: https://matklad.github.io/2021/07/09/inline-in-rust.html (same trick as `std::fs::read`)

## Build-level levers that beat per-function attributes

- `codegen-units = 1`, `lto = "thin"|"fat"` (Perf Book: 10-20 % reported), `panic = "abort"` (removes landing pads, so more functions pass the leaf test and auto-inline), PGO via `cargo-pgo` (10 %+ reported).
- Evaluate inlining only in release with `incremental = false`; dev builds disable cross-crate inference.
- Too much inlining is a real cost: larger hot loops miss the i-cache/uop-cache.
Source: https://nnethercote.github.io/perf-book/build-configuration.html

## `std::hint` status (stable 1.99.1)

| API | Status | Since |
|---|---|---|
| `hint::black_box` | stable | 1.66 (const 1.86) |
| `hint::unreachable_unchecked` (unsafe) | stable | 1.27 |
| `hint::spin_loop` | stable | 1.49 |
| `hint::assert_unchecked` (unsafe) | stable | 1.81 |
| `hint::select_unpredictable` | stable | 1.88 |
| `hint::cold_path` | stable | 1.95 |
| `hint::likely` / `hint::unlikely` | nightly (`likely_unlikely`) | — |
| `hint::prefetch_*`, `hint::must_use` | experimental | — |

Source: https://doc.rust-lang.org/std/hint/index.html

### `cold_path()` (1.95): mark an unlikely arm without outlining

**Rule**: call `cold_path()` at the top of the rare `if`/`match` arm when a `#[cold]` helper is inconvenient or the arm must stay inline. Build your own `likely`/`unlikely` on top of it; never use `core::intrinsics::likely` on stable.
**Detect**: known-rare arm in a hot branch (error return, cache miss, resize, `None` in a hot `?`-like loop).

```rust
use std::hint::cold_path;

pub fn bar(x: i32) -> i32 {
    match x {
        1 => 10,
        2 => 100,
        3 => {
            cold_path();
            1000
        }
        _ => {
            cold_path();
            10000
        }
    }
}

#[inline(always)]
pub const fn unlikely(b: bool) -> bool {
    if b {
        cold_path();
    }
    b
}
```

**Caveat** (std docs): can decrease performance if the branch runs more often than expected; hint only, codegen effect not guaranteed.
Source: https://doc.rust-lang.org/std/hint/fn.cold_path.html

### `assert_unchecked(cond)` (1.81, unsafe): state an invariant the optimizer cannot derive

**Rule**: after `cargo asm` shows a bounds check or branch that an invariant maintained elsewhere makes impossible, and reslicing / `assert_eq!` / `chunks_exact` did not remove it, assert the invariant with a `// SAFETY:` comment and a regression benchmark.
**Detect**: a struct invariant (`len <= buf.len()`, `idx < N`) re-checked in a hot accessor.

```rust
pub struct Window {
    buf: Vec<u8>,
    len: usize,
}

impl Window {
    pub fn tail(&self) -> &[u8] {
        // SAFETY: every constructor and mutator keeps len <= buf.len().
        unsafe { std::hint::assert_unchecked(self.len <= self.buf.len()) };
        &self.buf[..self.len]
    }
}
```

**Caveat** (std docs): a false condition is immediate UB; it "promotes a correctness requirement to a soundness requirement"; it can also make code slower and compile longer; complex conditions (`is_sorted()`) are useless; keep a benchmark and expect to drop it when the optimizer improves.
Source: https://doc.rust-lang.org/std/hint/fn.assert_unchecked.html

### `select_unpredictable(cond, a, b)` (1.88): branchless select for 50/50 data-dependent conditions

**Rule**: use for conditions the predictor cannot learn (binary search, partition, merge step, bucket choice) to encourage `cmov`/`csel`.
**Detect**: `perf stat -e branch-misses` high at a branch whose outcome is data-random; the loop-carried dependency on the selected value is short.

```rust
pub fn find_sorted(v: &[u32], target: u32) -> Option<usize> {
    if v.is_empty() {
        return None;
    }
    let mut base = 0usize;
    let mut size = v.len();
    while size > 1 {
        let half = size / 2;
        let mid = base + half;
        base = std::hint::select_unpredictable(v[mid] <= target, mid, base);
        size -= half;
    }
    if v[base] == target {
        Some(base)
    } else {
        None
    }
}
```

**Caveat** (std docs): lowering to `cmov` is not guaranteed; not for constant-time crypto; can be slower when the condition is predictable (a data dependency replaces speculation). Both operands are evaluated eagerly.
Source: https://doc.rust-lang.org/std/hint/fn.select_unpredictable.html

### `black_box` (1.66): benchmarks only

**Rule**: wrap benchmark inputs and outputs so the optimizer cannot const-fold or delete the work. Criterion and Divan black-box the closure's return value and their generated/parameterized inputs, but not literals or captured values you pass yourself (`b.iter(|| f(20))` can be constant-folded); never use it in production code.
**Detect**: an "impossibly fast" microbenchmark, a loop missing from asm, an unused result.

```rust
use std::hint::black_box;

pub fn bench_once(input: &[u32]) -> u32 {
    black_box(sum(black_box(input)))
}

fn sum(v: &[u32]) -> u32 {
    v.iter().copied().fold(0, u32::wrapping_add)
}
```

**Caveat**: best-effort only; expressions inside the call may still fold (`black_box(5 * 10)` folds; use `black_box(5) * black_box(10)`).
Source: https://doc.rust-lang.org/std/hint/fn.black_box.html

## Low-level codegen controls

- `#[unsafe(naked)]` functions (1.88): full control of prologue/epilogue for context switches, trampolines, interpreters.
- `asm_goto` (1.87): inline asm may jump to Rust labels; `asm_cfg` (1.93).
- `-C jump-tables=false` (1.93): disable jump tables when branch prediction or CFI matters.
- `#[track_caller]` appends an implicit location argument to the ABI; keep it on small panicking helpers, not on hot non-panicking functions. No measured numbers exist; treat as small but nonzero.
Sources: https://github.com/rust-lang/rust/blob/master/RELEASES.md · https://users.rust-lang.org/t/consequences-of-annotating-every-single-crate-function-with-track-caller-attribute/129154

## Verification toolkit

```bash
cargo install cargo-show-asm
cargo asm --lib --rust my_crate::hot_fn        # asm interleaved with source
cargo asm --lib --mca my_crate::hot_fn         # llvm-mca throughput estimate
cargo asm --lib --llvm my_crate::hot_fn        # LLVM IR
cargo asm --lib --callers-of panic_bounds_check
cargo asm --lib --target-cpu=x86-64-v3 my_crate::hot_fn
rustc --print cfg -C target-cpu=native         # what "native" resolved to
perf stat -e cycles,instructions,branch-misses ./target/release/app
```

- Tiny or generic functions vanish from `cargo asm` output (inlined since 1.75). Add an `#[inline(never)] pub fn` monomorphic probe wrapper in a bench or example and inspect that.
- What to look for: `panic_bounds_check` calls inside the loop; scalar `addss`/`mulss` vs packed `vaddps`/`vfmadd231ps`; `ymm`/`zmm` registers; several accumulators; `vgather*` (often slow).
- `llvm-mca` models a straight-line loop body on a chosen `-mcpu`; it ignores cache misses and most branch effects, so treat it as an estimate.
- Keep a regression benchmark next to every `unsafe` hint.
Sources: https://github.com/pacak/cargo-show-asm · https://llvm.org/docs/CommandGuide/llvm-mca.html · https://nnethercote.github.io/perf-book/build-configuration.html
