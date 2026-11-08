# Auto-vectorization and SIMD

Readable Rust that LLVM's loop/SLP vectorizer can turn into packed instructions, the stable std APIs that help (`as_chunks`, `array_windows`, algebraic float ops, safe `#[target_feature]`), and the explicit-SIMD crate landscape as of 2026-11. Verify every claim in `cargo asm`; auto-vectorization swings with compiler version and surrounding code.

Mental model (matklad): LLVM optimizes per function, reasons well about local scalars and poorly about memory and aliasing. Wins come from (1) making calls inlinable, (2) expressing the loop as "one chunk, no branching, all lanes identical", (3) simple flat data layout.
Sources: https://matklad.github.io/2023/04/09/can-you-trust-a-compiler-to-optimize-your-code.html · https://shnatsel.github.io/state-of-simd-rust-2026/

## Iterate, do not index

**Rule**: replace `for i in 0..n { a[i] .. b[i] }` with `iter()`/`zip`/`fold`; bounds checks disappear and the loop vectorizes.
**Detect**: `cargo asm` shows `cmp` + `jae panic_bounds_check` inside the loop and scalar ops; Clippy `needless_range_loop`.

```rust
pub fn dot_indexed(a: &[i32], b: &[i32]) -> i32 {
    let mut s = 0i32;
    for i in 0..a.len() {
        s = s.wrapping_add(a[i].wrapping_mul(b[i]));
    }
    s
}

pub fn dot(a: &[i32], b: &[i32]) -> i32 {
    a.iter().zip(b).fold(0i32, |s, (x, y)| s.wrapping_add(x.wrapping_mul(*y)))
}
```

**Caveat**: `zip` stops at the shorter slice (a semantic change from panicking). `-C overflow-checks=on` blocks vectorization of plain `+`/`*`. Use `wrapping_*` only when wrapping is the intended semantics (hash, checksum, PRNG): for a real dot product, widen the accumulator (`i64`) or validate input ranges once outside the loop instead of silently wrapping.
Source: https://nnethercote.github.io/perf-book/bounds-checks.html

## Hoist length knowledge before the loop

**Rule**: when indexing is unavoidable, reslice to one length (`let src = &src[..dst.len()];`) or `assert_eq!(a.len(), b.len())` once before the loop; take `let s = &self.v[..]` out of `self` so the pointer and length are not reloaded per iteration.
**Detect**: indexed access into two or more slices; `self.field[i]` inside a hot loop; `Vec<Vec<T>>` row access in the inner loop.

```rust
pub fn add_assign(dst: &mut [f32], src: &[f32]) {
    let n = dst.len();
    let src = &src[..n];
    for i in 0..n {
        dst[i] += src[i];
    }
}
```

**Caveat**: the reslice panics if `src` is shorter; `assert!` also changes behaviour. Choose deliberately; `zip` gives min-length semantics instead. Last resort: `get_unchecked` with a `// SAFETY:` proof.
Sources: https://nnethercote.github.io/perf-book/bounds-checks.html · https://github.com/Shnatsel/bounds-check-cookbook

## `as_chunks::<N>()` (1.88) / `chunks_exact(N)` for fixed-width inner loops

**Rule**: give the inner loop a compile-time trip count so LLVM picks the vector width and the remainder leaves the hot loop. `as_chunks` returns `(&[[T; N]], &[T])`; `chunks_exact(N)` plus `remainder()` is the pre-1.88 form. Iterator `array_chunks` is still unstable.
**Detect**: a reduction or elementwise loop over a large slice with a large scalar prologue/epilogue in asm.

```rust
pub fn sum_u32(v: &[u32]) -> u32 {
    let (body, tail) = v.as_chunks::<32>();
    let mut acc = [0u32; 32];
    for c in body {
        for k in 0..32 {
            acc[k] = acc[k].wrapping_add(c[k]);
        }
    }
    let head = acc.iter().copied().fold(0, u32::wrapping_add);
    head.wrapping_add(tail.iter().copied().fold(0, u32::wrapping_add))
}
```

**Caveat**: pick N as a multiple of the widest lane count you target (32 u32 = four AVX2 registers of independent accumulators); too large spills registers. `array_windows::<N>()` (1.94) does the same for sliding windows:

```rust
pub fn sum3(v: &[u32]) -> u32 {
    v.array_windows::<3>()
        .map(|&[a, b, c]| a.wrapping_add(b).wrapping_add(c))
        .fold(0, u32::wrapping_add)
}
```

**Min version**: `as_chunks` 1.88; `array_windows` 1.94; `chunks_exact` any.
Sources: https://github.com/rust-lang/rust/blob/master/RELEASES.md (1.88, 1.94) · https://shnatsel.github.io/state-of-simd-rust-2026/

## No early exit inside the chunk: non-short-circuit `&`, one branch per chunk

**Rule**: the loop vectorizer cannot handle data-dependent exits (`break`, `?`, `return`, `&&`/`||` with side effects). Test a whole chunk with non-short-circuiting ops and branch once per chunk, then finish with a scalar tail.
**Detect**: `find`/`position`/`any`/`all`/`take_while` over bytes or ints in a hot loop; common-prefix, validation and memchr-like scans; asm shows a scalar byte loop with a `jne` out.

```rust
pub fn common_prefix(xs: &[u8], ys: &[u8]) -> usize {
    const C: usize = 16;
    let off = xs
        .chunks_exact(C)
        .zip(ys.chunks_exact(C))
        .take_while(|(a, b)| a == b)
        .count()
        * C;
    off + xs[off..]
        .iter()
        .zip(&ys[off..])
        .take_while(|(a, b)| a == b)
        .count()
}
```

matklad measured 650 ms (naive zip + break) -> 450 ms (chunked, inner break) -> 80 ms (whole-chunk compare) on his data; rerun on yours. For real byte search use the `memchr` crate (2.8) rather than a DIY scan.
Source: https://matklad.github.io/2023/04/09/can-you-trust-a-compiler-to-optimize-your-code.html

## Integer reductions vectorize; float reductions need help

Integers: `iter().sum()`, `fold` with `wrapping_*`, `min`/`max` vectorize at `opt-level` 2/3 (`s` vectorizes with smaller unroll; `z` does not). Floats: IEEE addition is not associative, so `s += x` is one serial dependency chain (latency-bound, roughly one add per 3-4 cycles) and LLVM will not reorder it.
**Detect**: `f32`/`f64` `sum()`, dot products, norms, `+=` accumulators; asm shows `addss`/`addsd` instead of `vaddps`.

### Option A: algebraic float ops (1.98)

`f32/f64::algebraic_{add,sub,mul,div,rem}` allow reassociation and FMA contraction per operation; never UB (unlike nightly `fadd_fast`), but NaN, ±Inf and -0.0 may behave unexpectedly (a NaN can appear with no NaN input) and two identical calls can return different results even in one run.

```rust
pub fn sum_algebraic(a: &[f32]) -> f32 {
    a.iter().fold(0.0f32, |acc, &x| acc.algebraic_add(x))
}
```

orlp measured naive 5.5 GB/s vs algebraic 118.6 GB/s (about 20x, 100k floats in cache, one machine) and *better* accuracy, because reordering approximates pairwise summation. For controlled error, algebraic-sum 256-element blocks and combine with Kahan using plain ops (algebraic ops would simplify the compensation to zero):

```rust
fn sum_block(a: &[f32]) -> f32 {
    a.iter().fold(0.0f32, |x, &y| x.algebraic_add(y))
}

pub fn sum_kahan_blocks(a: &[f32]) -> f32 {
    let mut chunks = a.chunks_exact(256);
    let mut sum = 0.0f32;
    let mut c = 0.0f32;
    for blk in &mut chunks {
        let y = sum_block(blk) - c;
        let t = sum + y;
        c = (t - sum) - y;
        sum = t;
    }
    sum + (sum_block(chunks.remainder()) - c)
}
```

**Caveat**: do not use where results must be bit-reproducible, where inputs may contain NaN/Inf, or where you branch on `is_nan()`/`is_finite()` of the result.
Source: https://blog.rust-lang.org/2026/08/20/Rust-1.98.0/ · https://orlp.net/blog/taming-float-sums/

### Option B: N independent accumulators (any Rust version, deterministic)

```rust
pub fn sum8(a: &[f32]) -> f32 {
    let (body, tail) = a.as_chunks::<8>();
    let mut acc = [0.0f32; 8];
    for c in body {
        for k in 0..8 {
            acc[k] += c[k];
        }
    }
    acc.iter().sum::<f32>() + tail.iter().sum::<f32>()
}
```

The result differs from the serial sum (different association) but is identical on every run. Eight lanes fill one AVX register; use 16-32 to hide add latency. Pre-1.88: `chunks_exact(8)`.

## Branchless element bodies

**Rule**: inside the per-element body compute both sides cheaply and select; `if c { a } else { b }` on side-effect-free scalars lowers to `select` and vectorizes to a blend. Use `min`/`max`/`clamp`, `abs`, `saturating_*`, mask arithmetic (`(x > t) as u32`).
**Detect**: `if`/`match`/`continue`/`Option` unwrapping per element in a hot loop.

```rust
pub fn threshold(out: &mut [i32], inp: &[i32], t: i32) {
    for (o, &x) in out.iter_mut().zip(inp) {
        *o = if x > t { x } else { 0 };
    }
}

pub fn count_above(v: &[i32], t: i32) -> usize {
    v.iter().map(|&x| (x > t) as usize).sum()
}
```

**Caveat**: an arm that panics, conditionally indexes memory, calls a non-inlined function or divides will not vectorize. `hint::select_unpredictable` is for scalar code, not needed in vectorized loops.

## Aliasing and layout

- `out: &mut [T]` + `inp: &[T]` parameters give LLVM `noalias`; raw pointers, `&Cell<T>` and two views of the same `Vec` do not.
- Hoist `let row = &mut grid[r];` out of the inner loop; prefer a flat `Vec<T>` with a stride over `Vec<Vec<T>>` in numeric kernels.
Source: matklad (above)

## Build flags

- Default x86_64 baseline is SSE2. `-C target-cpu=native` or a level (`x86-64-v2` = SSE4.2, `x86-64-v3` = AVX2+FMA+BMI2, `x86-64-v4` = AVX-512) unlocks wider vectors; `rustc --print target-cpus` lists names, `rustc --print cfg -C target-cpu=native` shows what you got. A `native` binary SIGILLs on older CPUs; pin a level or dispatch at runtime for anything distributed.
- AVX-512: on pre-Ice-Lake Intel it downclocks all cores, and LLVM may emit slow gather/scatter when auto-vectorizing for it (reports of 1.75x slower on Intel, 4x on AMD: llvm/llvm-project#70259, #91370). Benchmark `x86-64-v3` against `v4`/native.
- Keep `overflow-checks` and `debug-assertions` off in release for numeric kernels, or use `wrapping_*`.
Sources: https://nnethercote.github.io/perf-book/build-configuration.html · https://shnatsel.github.io/state-of-simd-rust-2026/

## Explicit SIMD landscape (crates.io, 2026-11)

| Option | Status | Runtime multiversioning | Notes |
|---|---|---|---|
| auto-vectorization | stable | via `multiversion` or manual dispatch | easiest, fragile |
| `std::simd` (`portable_simd`) | nightly only (#86656) | bring your own | ops with no LLVM equivalent silently fall back to scalar (`reduce_sum`, `swizzle_dyn`) |
| `wide` 1.7 | stable | none | fixed-width `f32x8` etc.; x86 needs `-C target-cpu=x86-64-v3` or you get SSE2; good for aarch64-only |
| `pulp` 0.22 | stable | yes, verbose | native-width vectors; the whole hot loop must sit inside `vectorize(...)` or each intrinsic becomes a call |
| `multiversion` 0.9 (MSRV 1.86) | stable | `#[multiversion(targets = "simd")]` | best for auto-vectorized loop functions |
| `fearless_simd` 1.2 | stable | `#[simd]` / `kernel!` | levels SSE2/SSE4.2/AVX2/AVX-512 (Ice Lake+)/NEON/WASM; maintained by the survey author |
| `archmage`, `safe_unaligned_simd` | stable | feature tokens | safe intrinsics via type-level tokens |

Source: https://shnatsel.github.io/state-of-simd-rust-2026/

## `#[target_feature]` + one runtime check at the outer boundary

Facts: calling a `#[target_feature]` function on a CPU without the feature is UB. Since **1.86** safe functions may carry `#[target_feature]`; they are callable safely only from a caller that enables a superset of the features, otherwise the call needs `unsafe`. Since **1.87** most `std::arch` intrinsics without pointer arguments are safe inside a matching `#[target_feature]` function; loads and stores stay `unsafe`. `#[inline(always)]` is forbidden with `#[target_feature]`; functions with target features do not inline into callers that lack them; closures inside inherit the attribute. `is_x86_feature_detected!` caches its result (one atomic load) and folds to `true` when the feature is enabled at compile time.

**Rule**: dispatch once at the outermost kernel, never per element. Put the kernel body in an `#[inline(always)]` generic helper so one source compiles at several feature levels.

```rust
pub fn sum(v: &[f32]) -> f32 {
    #[cfg(target_arch = "x86_64")]
    {
        if is_x86_feature_detected!("avx2") && is_x86_feature_detected!("fma") {
            // SAFETY: AVX2 and FMA were verified at runtime on this CPU just above.
            return unsafe { sum_avx2(v) };
        }
    }
    sum_generic(v)
}

#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2,fma")]
fn sum_avx2(v: &[f32]) -> f32 {
    sum_generic(v)
}

#[inline(always)]
fn sum_generic(v: &[f32]) -> f32 {
    let (body, tail) = v.as_chunks::<8>();
    let mut acc = [0.0f32; 8];
    for c in body {
        for k in 0..8 {
            acc[k] += c[k];
        }
    }
    acc.iter().sum::<f32>() + tail.iter().sum::<f32>()
}
```

Raw intrinsics belong only inside such a region, and since 1.87 need no `unsafe` when they take no pointers:

```rust
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2")]
fn double_lanes(a: std::arch::x86_64::__m256i) -> std::arch::x86_64::__m256i {
    std::arch::x86_64::_mm256_add_epi32(a, a)
}
```

**Caveats**: dispatch overhead (branch + non-inlined call) dominates for tiny inputs. Generic std iterator adaptors inside a `#[target_feature]` function may be compiled without the feature if not inlined; check the asm. "AVX-512 present" is not "AVX-512 fast" on Skylake-era Intel; gate on Ice Lake+/Zen 4+ as `fearless_simd` does.
**Min version**: safe `#[target_feature]` fns 1.86; safe `std::arch` 1.87; `is_x86_feature_detected!` 1.27.
Sources: https://blog.rust-lang.org/2025/04/03/Rust-1.86.0/ · https://doc.rust-lang.org/reference/attributes/codegen.html · https://doc.rust-lang.org/std/macro.is_x86_feature_detected.html

## `multiversion` for auto-vectorized loop functions

```rust
use multiversion::multiversion;

#[multiversion(targets = "simd")]
pub fn scale(x: &mut [f32], k: f32) {
    for v in x {
        *v *= k;
    }
}
```

**Rule**: annotate functions that contain the loop; a call into a multiversioned function costs under a dozen instructions, so for functions that handle a handful of values use `#[inline(always)]` and multiversion further up. `targets = "simd"` checks AVX-512 presence, not speed; list explicit targets (`"x86_64+avx2+fma"`, `"aarch64+neon"`) to avoid slow AVX-512 parts.
**Version**: multiversion 0.9, MSRV 1.86. Source: https://github.com/calebzulawski/multiversion

## `std::simd` is nightly-only

Do not build a stable product on it. The docs banner says "nightly-only experimental API"; the 2026 survey reports infrequent breaking changes and silent scalar fallback for ops LLVM lacks. If you accept nightly, pair it with `multiversion` for dispatch.
Source: https://doc.rust-lang.org/std/simd/index.html

## Choosing

1. Restructure for auto-vectorization (sections above) and set `-C target-cpu` for a known fleet. Verify in asm.
2. Shipping to unknown x86: `multiversion` on loop-level functions, or manual `#[target_feature]` + detection.
3. Explicit lanes/shuffles on stable: `fearless_simd` or `pulp` (dispatch), `wide` (fixed target).
4. `std::simd` only in nightly projects.
5. Raw intrinsics only for exact-instruction needs (pclmul, aes, gfni, vpopcnt) inside `#[target_feature]` regions.
