# Allocation, data layout, and cache friendliness

How to cut heap allocations, shrink types, and keep hot data in cache. Items marked **[measured]** were run on rustc 1.99.1, Apple M2 Max (aarch64, 128-byte cache line), 64-bit, `-O`. Default `repr(Rust)` layout is unspecified by the Reference, so size numbers are "true for this compiler", not guarantees; pin them with const asserts. Profile allocations with DHAT or the `dhat` crate first: a hot `malloc`/`free` in a general profiler is the signal.

Crate versions (crates.io, 2026-11-08): smallvec 1.16 (2.0 is beta, do not adopt), arrayvec 0.7, heapless 0.9, tinyvec 1.13, compact_str 0.10, smol_str 0.3, ecow 0.3, thin-vec 0.2, bumpalo 3.20, lasso 0.7, crossbeam-utils 0.8, bitflags 2.13, modular-bitfield 0.13, top-type-sizes 0.2, dhat 0.3, slotmap 1.1, nonmax 0.5.

Sources used throughout: PERF-HEAP https://nnethercote.github.io/perf-book/heap-allocations.html · PERF-SIZE https://nnethercote.github.io/perf-book/type-sizes.html · PERF-ITER https://nnethercote.github.io/perf-book/iterators.html · REF-LAYOUT https://doc.rust-lang.org/reference/type-layout.html · OPTION-REPR https://doc.rust-lang.org/std/option/index.html#representation

# Part A. Allocation avoidance

Each alloc/free "typically involves acquiring a global lock, non-trivial data structure manipulation, possibly a system call" (PERF-HEAP). In rustc, removing about 10 allocations per million instructions gave about 1 %.

## A1. Pre-size: `with_capacity` / `reserve` / `reserve_exact`

**Rule**: if the final or minimum length is known or estimable, reserve once.
**Detect**: `Vec::new()`/`String::new()`/`HashMap::new()` followed by a push loop; `Vec::new()` inside a hot function.

```rust
pub fn fill(n: usize, f: impl Fn(usize) -> u32) -> Vec<u32> {
    let mut v = Vec::with_capacity(n);
    for i in 0..n {
        v.push(f(i));
    }
    v
}
```

**[measured]** 100 pushes without capacity = 6 allocations; with = 1. Minimum non-zero capacity on 1.99 is 8 for 1-byte elements, 4 for elements up to 1024 B, 1 above; growth is quasi-doubling and unspecified.
**Caveat**: over-reserving wastes RAM (`reserve_exact`, `shrink_to_fit`); for bimodal lengths histogram them before picking a number.

## A2. Reuse buffers: `clear()`, `clone_from`, out-params

**Rule**: hoist the allocation out of the loop; `clear()` keeps capacity; `a.clone_from(&b)` reuses `a`'s allocation; return results through `&mut Vec<T>`.
**Detect**: `Vec::new()`/`String::new()`/`format!` inside a loop body or per-call function; `BufRead::lines()`; `a = b.clone()` onto an existing collection.

```rust
use std::io::BufRead;

pub fn each_line(mut input: impl BufRead, mut process: impl FnMut(&str)) -> std::io::Result<()> {
    let mut line = String::new();
    while input.read_line(&mut line)? != 0 {
        process(&line);
        line.clear();
    }
    Ok(())
}
```

**Caveat**: a reused buffer that once held a huge item stays huge (`shrink_to`); stash workhorse buffers in a struct for repeated method calls.

## A3. `write!` into a reused `String` instead of `format!`

**Rule**: `format!`, `to_string()`, `to_owned()` and `String::from` each allocate; in loops write into one pre-sized buffer. Never `s.push_str(&format!(..))`; `write!(s, ..)` appends directly.
**Detect**: `format!` in loops, in `HashMap` lookups (`map.get(&format!(..))`), in eagerly evaluated log arguments; Clippy `format_push_string` (pedantic).

```rust
use std::fmt::Write;

pub fn ids(n: u32, mut use_it: impl FnMut(&str)) {
    let mut s = String::with_capacity(32);
    for i in 0..n {
        s.clear();
        write!(s, "id-{i}").unwrap();
        use_it(&s);
    }
}
```

**[measured]** 100 iterations: 100 allocations with `format!`, 1 with the reused buffer. `a + &b + &c` chains reuse `a`'s buffer but still realloc as it grows; `[..].concat()`/`join` compute the total length and allocate once. For integers use `itoa` (1.0) or std's `format_into` (1.98, see hot-path-idioms.md).
Sources: PERF-HEAP (String, clone, to_owned)

## A4. Never-grown data: `Box<str>`, `Box<[T]>`, `Arc<str>`

**Rule**: a `String`/`Vec` that is never grown after construction becomes `Box<str>`/`Box<[T]>` (16 bytes instead of 24, no spare capacity). Widely cloned read-only data becomes `Arc<str>`/`Arc<[T]>` (clone = refcount bump).
**Detect**: structs built once and read many times with `String`/`Vec<String>` fields; `.clone()` of such structs in hot code; `Vec` fields that are always `len == cap`.

```rust
// 80 bytes measured on 64-bit
pub struct Person {
    pub name: String,
    pub nick: Option<String>,
    pub age: u8,
    pub tags: Vec<String>,
}

// 56 bytes measured on 64-bit
pub struct PersonBox {
    pub name: Box<str>,
    pub nick: Option<Box<str>>,
    pub age: u8,
    pub tags: Box<[Box<str>]>,
}

pub fn collect_boxed(n: u32) -> Box<[u32]> {
    (0..n).collect()
}
```

**[measured]** `String`/`Vec` 24 B; `Box<str>`/`Box<[T]>`/`Arc<str>`/`&str` 16 B; `Option<Box<str>>` 16 B. `into_boxed_slice` may realloc to drop capacity.
**Caveat**: `Rc`/`Arc` on rarely shared values adds an allocation plus two counters; `Arc` clones contend under multi-core sharing.
Sources: PERF-SIZE (Boxed Slices), PERF-HEAP (Rc/Arc)

## A5. Fixed capacity on the stack: arrays, `ArrayVec`, `heapless::Vec`, `SmallVec`, `TinyVec`

**Rule**: exact size known -> `[T; N]`. Hard upper bound, no heap fallback -> `arrayvec::ArrayVec<T, N>` (Perf Book: a little faster than SmallVec, no spill check) or `heapless::Vec<T, N>` (no_std). Usually small, occasionally large -> `smallvec::SmallVec<[T; N]>` or `tinyvec::TinyVec` (safe code, `T: Default`).
**Detect**: DHAT shows many short-lived tiny `Vec`s at one site; length histogram mostly <= 8; `vec![a, b]` temporaries; fixed-arity data in a `Vec`.

```rust
pub fn split_small(s: &str) -> smallvec::SmallVec<[u32; 8]> {
    s.split(',').filter_map(|p| p.parse().ok()).collect()
}

pub fn first_eight(xs: &[u32]) -> arrayvec::ArrayVec<u32, 8> {
    let mut fixed = arrayvec::ArrayVec::<u32, 8>::new();
    for &x in xs.iter().take(8) {
        fixed.push(x);
    }
    fixed
}
```

**Caveat** (Perf Book): SmallVec "reliably reduces the allocation rate ... but its use does not guarantee improved performance"; each op pays an inline-vs-heap check; large `N` or `T` makes the value bigger than a `Vec` and moves cost more (types > 128 B are memcpy'd). The `union` feature drops the tag word. Depend on `smallvec = "1"`; 2.0 is beta.
Sources: PERF-HEAP (Short Vecs) · https://docs.rs/smallvec/latest/smallvec/ · https://docs.rs/tinyvec/latest/tinyvec/

## A6. Small strings: `compact_str`, `smol_str`, `ecow`

**Rule**: when most strings are short (identifiers, keys, tags, tokens), keep them inline. Interning (C4) beats all of these when strings repeat.
**Detect**: `Vec<String>`/`HashMap<String, _>` with DHAT showing huge counts of allocations under 24 bytes; parsers producing small strings.

| type | size | inline cap | mutable | clone |
|---|---|---|---|---|
| `compact_str::CompactString` 0.10 | 24 | 24 B | yes | O(n) |
| `smol_str::SmolStr` 0.3 | 24 | 23 B | no | O(1), `new_static` for literals |
| `ecow::EcoString` 0.3 | 16 | 15 B | copy-on-write | O(1) when spilled |

`CompactString` has `size_of::<CompactString>() == size_of::<Option<CompactString>>()`, `From<String>` reuses the buffer, and `format_compact!`.
**Caveat**: a branch per access; no win when strings are mostly long.
Sources: https://github.com/ParkMyCar/compact_str · https://docs.rs/smol_str/latest/smol_str/struct.SmolStr.html · https://docs.rs/ecow/latest/ecow/

## A7. `Cow<'static, str>` for mixed literal/runtime strings

**Rule**: when most values are literals and a few are built at runtime, store `Cow<'static, str>` (24 B, same as `String` **[measured]**). Functions that modify input only sometimes return `Cow<'a, str>` and clone only on write.
**Detect**: `"literal".to_string()` in some branches and `format!` in others; `to_owned()` of input that is usually returned unchanged.

```rust
use std::borrow::Cow;

pub fn errors(line: Option<u32>) -> Vec<Cow<'static, str>> {
    let mut errs = Vec::new();
    errs.push(Cow::Borrowed("something went wrong"));
    if let Some(n) = line {
        errs.push(Cow::Owned(format!("line {n}")));
    }
    errs
}
```

**Caveat** (Perf Book): "can be fiddly to get working, but often worth the effort".
Source: PERF-HEAP (Cow)

## A8. Arenas: `bumpalo`, `typed-arena`

**Rule**: many small objects that die together (AST, request-scoped data, per-frame data) -> bump-allocate and free in bulk.
**Detect**: DHAT shows millions of tiny allocations with similar lifetimes; a build phase followed by a drop-everything phase; `Box<Node>` trees.

```rust
#[derive(Default, Clone, Copy)]
pub struct Node {
    pub val: u32,
    pub next: Option<u32>,
}

pub fn build<'b>(bump: &'b bumpalo::Bump, n: u32) -> bumpalo::collections::Vec<'b, &'b Node> {
    let mut nodes = bumpalo::collections::Vec::new_in(bump);   // feature "collections"
    for val in 0..n {
        let node: &'b mut Node = bump.alloc(Node { val, next: None });
        nodes.push(&*node);
    }
    nodes
}
// per request: bump.reset()
```

**Caveat**: alloc = bounds check + pointer bump, no individual free; **`Drop` is not run** for arena values (use `bumpalo::boxed::Box`, feature `boxed`, or keep arena data POD); `Bump` is `!Sync` (`bumpalo-herd` for rayon); memory is held until reset. The std `Allocator` trait stabilizes in Rust 1.100 (2026-11-12); check the 1.100 release notes for which `Vec`/`Box` `*_in` constructors are stable before relying on arena-backed std collections.
Sources: https://docs.rs/bumpalo/latest/bumpalo/ · https://rustc-dev-guide.rust-lang.org/memory.html · https://releases.rs/docs/1.100.0/

## A9. `mem::take` / `mem::replace` / `mem::swap` / `Option::take` instead of `clone`

**Rule**: to move out of a `&mut` place leave a cheap placeholder instead of cloning.
**Detect**: `let x = self.buf.clone(); self.buf.clear();`; `.clone()` added only to satisfy "cannot move out of borrowed content".

```rust
pub struct Acc {
    buf: Vec<u8>,
}

impl Acc {
    pub fn take_all(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.buf)
    }
}
```

**Caveat**: `take` leaves a capacity-0 `Vec`; to keep a reused buffer `swap` two workhorse buffers or `drain(..)`.
Source: https://doc.rust-lang.org/std/mem/fn.take.html

## A10. `collect` / `extend` sizing

**Rule**: do not `collect` just to iterate again; return `impl Iterator`; `extend` an existing collection instead of `collect` + `append`; implement `size_hint`/`ExactSizeIterator` on custom iterators so `collect` allocates once.
**Detect**: `.collect::<Vec<_>>()` immediately followed by `.iter()`/`for`; `v.append(&mut other.iter()...collect())`; `extend(slice.iter().cloned())` (use `extend_from_slice`).

```rust
pub fn push_doubled(out: &mut Vec<u64>, xs: &[u32]) {
    out.extend(xs.iter().map(|&x| u64::from(x) * 2));
}
```

**[measured]** `(0..100).collect::<Vec<u32>>()` = 1 allocation. `src.into_iter().map(|x| x + 1).collect::<Vec<u32>>()` = 0 allocations and the same pointer: std often reuses the source allocation when element layouts are compatible (observed, not a documented guarantee). The std `FromIterator for Vec` docs warn this can extend the lifetime of a large allocation and raise memory use; `shrink_to_fit` or collect into `Box<[T]>` when the output is much smaller than the input. `iter().map().collect()` over a borrowed `Vec` always allocates. `filter` has lower-bound `size_hint` 0, so call `reserve` yourself when you know the bound. Perf Book: `chain` can be slower than one iterator; `filter_map` over `filter` + `map`; `chunks_exact` over `chunks`.
Source: PERF-ITER

## A11. `ThinVec` for usually-empty vectors in hot types

**Rule**: `thin_vec::ThinVec<T>` (0.2) is one word: len and cap live in the heap block; an empty one does not allocate.
**Detect**: a type instantiated millions of times with a `Vec` field that is usually empty (AST `attrs`); the largest enum variant is dominated by a `Vec`.
**Caveat**: extra indirection to read `len`.
Source: PERF-SIZE (ThinVec)

## A12. Zeroed and uninitialized allocation (std)

| API | Since | Use |
|---|---|---|
| `Box/Rc/Arc::new_uninit`, `new_uninit_slice` | 1.82 | allocate without writing; avoid a stack temporary for big values |
| `Box::new_zeroed(_slice)`, `Rc/Arc::new_zeroed(_slice)` | 1.92 | `calloc`-style zero pages, no memset for large buffers |
| `Box<MaybeUninit<T>>::write` | 1.87 | initialize in place, returns `Box<T>` |
| `<[MaybeUninit<T>]>::write_copy_of_slice`, `assume_init_ref/_mut/_drop` | 1.93 | fill uninit buffers (readers, arenas) |

```rust
pub fn zeroed_buffer(len: usize) -> Box<[u8]> {
    vec![0u8; len].into_boxed_slice()
}

pub fn zeroed_shared(len: usize) -> std::sync::Arc<[u8]> {
    // SAFETY: an all-zero byte pattern is a valid [u8].
    unsafe { std::sync::Arc::<[u8]>::new_zeroed_slice(len).assume_init() }
}
```

`Box::new([0u8; 1 << 26])` builds the array on the stack first only in debug builds (stack overflow risk); with `-O` it becomes a `calloc`. For `Box<[u8]>`, `vec![0; n].into_boxed_slice()` is safe and does one zeroed allocation; reach for `new_zeroed_slice` + `unsafe assume_init` for `Rc`/`Arc` or types `vec!` cannot build. `vec![0; n]` is already as fast as or faster than `resize`/`extend` (Perf Book).
Source: https://github.com/rust-lang/rust/blob/master/RELEASES.md (1.82, 1.92, 1.93)

## A13. Enforce allocation budgets in tests

`dhat` 0.3 heap-usage tests (`dhat::assert_eq!(stats.total_blocks, N)`) or a counting `#[global_allocator]` around the function under test keep allocation counts from regressing.
Source: PERF-HEAP (Avoiding Regressions)

# Part B. Struct and enum layout

## B1. Default `repr(Rust)` reorders fields; `repr(C)` does not

**Rule**: leave structs on the default repr; the compiler sorts fields to minimize padding. The Reference guarantees only alignment and non-overlap for `repr(Rust)`; everything else may change between compilations. If you need `repr(C)` (FFI, `bytemuck` casts, stable layout), order fields by descending alignment yourself.
**Detect**: `#[repr(C)]` on a non-FFI struct; mixed `u8/u64/u8/u32` fields under `repr(C)`; `offset_of!`/pointer casts that assume layout.

```rust
#[repr(C)]
pub struct BadC {
    a: u8,
    b: u64,
    c: u8,
    d: u32,
}

#[repr(C)]
pub struct GoodC {
    b: u64,
    d: u32,
    a: u8,
    c: u8,
}

pub struct Reordered {
    a: u8,
    b: u64,
    c: u8,
    d: u32,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(std::mem::size_of::<BadC>() == 24);
#[cfg(target_pointer_width = "64")]
const _: () = assert!(std::mem::size_of::<GoodC>() == 16);
```

**[measured]** `BadC` 24, `GoodC` 16, `Reordered` 16. `repr(C)` advances offsets in declaration order, padding to each field's alignment.
**Caveat**: `repr(packed)` removes padding but makes references to fields UB and slows unaligned access.
Sources: REF-LAYOUT · PERF-SIZE (Field Ordering)

## B2. Niche optimization: free `Option`

**Rule**: types with invalid bit patterns let `Option<T>` store the discriminant for free. Expose niches: `NonZero*`, references, `Box`, `NonNull`, `Rc/Arc`, `String`/`Vec`/`Box<str>`, `bool`, `char`, fieldless enums, `Duration`.
**Guaranteed** (OPTION-REPR): `Option<T>` has the size/alignment/ABI of `T` for `Box<U>`, `&U`, `&mut U`, `fn` pointers, `NonZero*`, `NonNull<U>` and `repr(transparent)` wrappers of those. Everything else below is observed.
**Detect**: `Option<u32>`/`Option<usize>` index fields; hand-rolled `u32::MAX` sentinels.

| type | bytes **[measured]** |
|---|---|
| `Option<u8>` / `Option<u32>` / `Option<u64>` / `Option<usize>` | 2 / 8 / 16 / 16 |
| `Option<NonZeroU8>` / `Option<NonZeroU32>` / `Option<NonZeroU64>` | 1 / 4 / 8 |
| `Option<bool>`, `Option<Option<bool>>`, `Option<Ordering>` | 1 |
| `Option<&T>` / `Option<Box<T>>` / `Option<fn()>` | 8 |
| `Option<&str>` / `Option<Box<[u8]>>` / `Option<Arc<str>>` | 16 |
| `Option<String>` / `Option<Vec<u8>>` | 24 |
| `Option<Duration>` | 16 |
| `Result<(), io::Error>` / `Result<u32, ()>` | 8 / 8 |

```rust
use std::num::NonZeroU32;

pub struct Edge {
    pub to: u32,
    pub next: Option<NonZeroU32>,
}

const _: () = assert!(std::mem::size_of::<Edge>() == 8);
```

`Option<u32>` in that field would make `Edge` 12 bytes. When 0 is a valid index store index+1, or use `nonmax::NonMaxU32` (0.5).
Multi-variant data enums use niches too: `enum Tok { Num(u64), Str(String), Id(u32) }` is 24 B because `String`'s capacity niche holds the tag; with `Box<str>` (one niche value) the same three variants still need a separate tag, also 24 B **[measured]**. The niche *count* matters, not just its existence.
Sources: OPTION-REPR · REF-LAYOUT · https://www.0xatticus.com/posts/understanding_rust_niche/

## B3. Enum size = largest variant + tag: box the outlier

**Rule**: when one variant is much larger than the rest and rare, box its payload; the enum shrinks to the second-largest variant plus tag.
**Detect**: Clippy `large_enum_variant` (fires above `enum-variant-size-threshold`, **default 200 B** — verified with clippy 0.1.99: `[u8; 300]` flagged, `[u8; 150]` not); surprising `size_of` on `Vec<Enum>` or `Result<T, BigError>`; `memcpy` in the profile (types > 128 B are moved with `memcpy`).

```rust
pub enum Wide {
    X,
    Y(i32),
    Z(i32, [u8; 100]),
}

pub enum Narrow {
    X,
    Y(i32),
    Z(Box<(i32, [u8; 100])>),
}
```

**[measured]** `Wide` 108 B, `Narrow` 16 B. Perf Book example: `enum E { A, B(i32), C(u64, u8, u64, u8), D(Vec<u32>) }` is 32 B; boxing `C` gives 24 B.
**Caveat**: one allocation and a pointer chase for the boxed variant; worth it only when that variant is rare. For `Result<T, E>` boxing a big `E` keeps the hot `Ok` path small (Clippy `result_large_err`).
Sources: PERF-SIZE (Smaller Enums) · https://rust-lang.github.io/rust-clippy/master/#large_enum_variant

## B4. Bulk-stored enums: aim for 8-16 bytes (heuristic); `repr(u8)` does not shrink default enums

**Rule**: for enums stored in big arrays, bytecode or token streams, aim for tag + one machine word. This is a practical heuristic; the sourced limit is 128 B (memcpy). Techniques: `Box<str>`, index or interned id (4 B) instead of `String` (24 B); `u32` payloads; `kind: u8` plus side tables.

```rust
pub enum Tok24 {
    Num(u64),
    Str(String),
    Id(u32),
}

pub enum Tok16 {
    Num(u64),
    Str(std::num::NonZeroU32),
    Id(u32),
}

pub enum Tok8 {
    Num(u32),
    Str(std::num::NonZeroU32),
    Id(u32),
}
```

**[measured]** 24 / 16 / 8 bytes.
`repr` facts **[measured + Reference]**: a fieldless enum with <= 256 variants is already 1 byte by default; `repr(C)` makes it 4 (C `int`). For enums with fields `repr(u8)` fixes the layout as a union of `repr(C)` structs starting with the tag; `repr(u8) R8 { A(u32), B(u8) }` is 8 bytes, same as the default. The Reference's `repr(C) EnumC { V0(u8), V1 }` is 8 vs `repr(C, u8)` 2 (reproduced). **Use `repr(u8)`/`repr(C, u8)` to shrink an enum that must be C-like; it never shrinks a default `repr(Rust)` enum**, and on data-carrying enums it disables niche filling, so it can grow them (measured: `enum { A(&u8), B }` 8 → 16 B, `enum { A(String), B(u32) }` 24 → 32 B).
Sources: REF-LAYOUT (primitive representations) · PERF-SIZE

## B5. Smaller integers and `NonZero`

**Rule**: store indices and counts as `u32`/`u16`/`u8` and widen with `as usize` at use sites; `NonZeroU32` newtypes for ids keep `Option<Id>` at 4 bytes.
**Detect**: `usize` fields in structs with millions of instances; `Vec<usize>` of indices; `Option<usize>`.

```rust
pub struct NodeWide {
    pub parent: usize,
    pub first_child: usize,
    pub kind: u32,
}

pub struct NodeNarrow {
    pub parent: u32,
    pub first_child: u32,
    pub kind: u32,
}
```

24 B vs 12 B. Guard conversions at the boundary (`u32::try_from(len).expect(..)`).
Source: PERF-SIZE (Smaller Integers)

## B6. Pin sizes: const asserts, `-Zprint-type-sizes`, `top-type-sizes`

**Rule**: assert the size of every type you tuned, gated by target.

```rust
pub struct HotType {
    a: u64,
    b: u32,
    c: u32,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(std::mem::size_of::<HotType>() == 16, "HotType grew");
const _: () = assert!(std::mem::size_of::<Option<Box<HotType>>>() == std::mem::size_of::<usize>());
```

Inspection: `RUSTFLAGS=-Zprint-type-sizes cargo +nightly build --release` prints per-variant sizes, field order, padding and tag size; `top-type-sizes` (0.2) sorts the output. `static_assertions` (last release 2019) is superseded by `const _: () = assert!(..)`.
Source: PERF-SIZE (Measuring Type Sizes, Avoiding Regressions) · https://crates.io/crates/top-type-sizes

## B7. Bit packing: `bitflags`, `modular-bitfield`

**Rule**: several `bool`s in a bulk-stored struct -> one flags integer (`bitflags` 2.13); sub-byte fields -> `#[modular_bitfield::bitfield]` (0.13). **[measured]** a struct of 8 `bool`s is 8 B; a `bitflags` `u8` is 1 B. `Vec<bool>` for large sets -> a bitset crate.
**Caveat**: shifts and masks on every access; breaks auto-vectorization of the unpacked form; loses niches; atomics need whole-word ops. Pack cold or bulk data only.
Sources: https://docs.rs/modular-bitfield/latest/modular_bitfield/ · https://crates.io/crates/bitflags

# Part C. Cache friendliness

## C1. SoA vs AoS, hot/cold splitting (not automatically faster)

**Rule**: when a hot loop reads a few fields of many large structs, split into per-field `Vec`s or into a hot struct and a cold struct sharing an index.
**Detect**: loop over `Vec<BigStruct>` touching 1-3 small fields of a >= 64 B struct; profile shows cache/bandwidth bound (high cache-misses, low IPC).

**[measured]** M2 Max, 1.99.1 `-O`:
- 64 B struct, updating 4 of 9 fields (4M elements, 10 passes): AoS 43-49 ms, SoA 54 ms. **SoA slower** (four streams plus bounds checks; one struct is exactly one cache line and half its fields are used).
- 128 B struct, reading one `f32` (2M elements, 20 passes): AoS 114 ms, SoA 35 ms (**3.3x**).
- 64 B struct, summing one `f32`: AoS 41 ms, SoA 34 ms (1.2x).

The win scales with (struct size / bytes actually used). Keep AoS for code that uses the whole struct. `soa_derive` (0.14) generates the SoA type.
**Caveat**: SoA complicates insertion/removal (swap_remove every column) and random access to a whole entity; borrowing several columns mutably needs `split_at_mut`/zip.
Source: https://jamesmcm.github.io/blog/intro-dod/ (his AoS/SoA gap also shrank to 25 % once unused fields were removed)

## C2. False sharing: pad hot per-thread atomics

**Rule**: data written by different threads must not share a cache line. Wrap each hot per-thread or per-role atomic in `crossbeam_utils::CachePadded<T>` or `#[repr(align(128))]`.
**Detect**: `[AtomicU64; N]`/`Vec<AtomicUsize>` indexed by thread id; adjacent `head`/`tail` atomics in a queue; throughput *drops* as threads increase although each touches "its own" variable.

```rust
use std::sync::atomic::AtomicU64;

#[repr(align(128))]
pub struct Padded(pub AtomicU64);

pub struct PerThread {
    pub counters: Box<[Padded]>,
}
```

**[measured]** 4 threads x 20M `fetch_add(Relaxed)` on 4 adjacent `AtomicU64`s: 651 ms; with each counter in a `repr(align(128))` wrapper: 41 ms (about 16x). `CachePadded` uses 128 on x86-64/aarch64/powerpc64 (the Intel spatial prefetcher pulls line pairs), 32 on arm/mips, 64 elsewhere; it is `repr(C)` since 0.8.22.
**Caveat**: 64-128 B per padded field; only for contended, write-heavy atomics.
Source: https://docs.rs/crossbeam-utils/latest/crossbeam_utils/struct.CachePadded.html

## C3. Indices instead of pointers

**Rule**: for graphs, trees and linked structures stored in a `Vec`, reference nodes by `u32` index (newtype, ideally `NonZeroU32`) rather than `&Node`/`Box<Node>`/`Rc<RefCell<Node>>`.
**Detect**: `Rc<RefCell<Node>>` or `Option<Box<Node>>` structures with many nodes; lifetime parameters only to link nodes; cyclic structures; need to clone or serialize the graph.

```rust
use std::num::NonZeroU32;

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct NodeId(NonZeroU32);

pub struct Node {
    pub val: u32,
    pub next: Option<NodeId>,
}

pub struct Graph {
    nodes: Vec<Node>,
}

impl Graph {
    pub fn get(&self, id: NodeId) -> &Node {
        &self.nodes[id.0.get() as usize - 1]
    }
}
```

**[measured]** `Node<'a> { val: u32, next: Option<&'a Node<'a>> }` 16 B vs the index form 8 B; nodes are contiguous, no refcounts, no lifetimes, one allocation. `slotmap` (1.1) adds generational keys against stale indices.
**Caveat**: bounds check per deref (usually cheap); stale indices without generations; use a distinct newtype per arena.
Sources: PERF-SIZE (Smaller Integers) · https://rustc-dev-guide.rust-lang.org/memory.html

## C4. String interning: `lasso`

**Rule**: when the same strings repeat (identifiers, field names, tags, hostnames), store each once and pass a 4-byte key; compare keys.
**Detect**: `HashMap<String, _>` keyed by repeating identifiers; many clones of the same values; string equality in a hot loop.

```rust
pub fn intern_all(names: &[&str]) -> (lasso::RodeoResolver, Vec<lasso::Spur>) {
    let mut rodeo = lasso::Rodeo::default();
    let keys: Vec<lasso::Spur> = names.iter().map(|n| rodeo.get_or_intern(n)).collect();
    (rodeo.into_resolver(), keys)
}
```

`Spur` wraps a `NonZeroU32` (4 bytes); `resolver.resolve(&key)` returns the `&str`.

lasso 0.7: `Rodeo` (single-thread) -> `into_reader()`/`into_resolver()` for a contention-free read phase; `ThreadedRodeo` locks under contention. `Option<Spur>` stays 4 bytes.
**Caveat**: interned strings live until the interner drops; a key is only meaningful with its interner.
Source: https://docs.rs/lasso/latest/lasso/

# Triage table

| You see | Apply |
|---|---|
| DHAT / profiler: `malloc`/`free` hot | A1 reserve, A2 reuse, A3 no `format!`, allocator swap |
| many tiny `Vec`s | A5 ArrayVec/SmallVec, A11 ThinVec, A8 arena |
| many short `String`s | A6 compact_str/smol_str, C4 interning, A7 Cow |
| `String`/`Vec` never grown | A4 `Box<str>`/`Box<[T]>`/`Arc<str>` |
| surprising `size_of` on a hot type | B6 print-type-sizes, B3 box variant, B5 u32, B2 NonZero |
| `memcpy` in profile | B3/B6: get the type under 128 B |
| loop touches few fields of a big struct | C1 SoA / hot-cold split (measure) |
| per-thread atomics scale badly | C2 padding |
| pointer-heavy tree/graph | C3 u32 index + arena |
| repeated identifier strings | C4 lasso |
| many `bool` fields in bulk | B7 bitflags/modular-bitfield |
