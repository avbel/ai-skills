# Hot-path standard-library idioms

Small, local rewrites that remove hashing, formatting, allocation, indirection or redundant checks from hot code. Bounds-check and vectorization idioms live in vectorization-simd.md; allocation and layout in memory-layout.md.

Crate versions (crates.io, 2026-11-08): rustc-hash 2.1, foldhash 0.2, ahash 0.8 (last release 2025-05, slower-moving), hashbrown 0.17, memchr 2.8, bstr 1.13, itoa 1.0, ryu 1.0, zmij 1.0, enum_dispatch 0.3 (last release 2024-03).

## B1. `HashMap` entry API, borrowed lookups, faster hashers

**Rule**: `contains_key` + `insert`, or `get_mut` + `insert`, hashes twice; `entry(k).or_insert_with(..)` / `.and_modify(..).or_insert(..)` hashes once.
**Detect**: Clippy `map_entry`; `if let Some(x) = m.get_mut(k) { .. } else { m.insert(..) }`.

```rust
use std::collections::HashMap;

pub fn count(m: &mut HashMap<String, u32>, k: String) {
    *m.entry(k).or_insert(0) += 1;
}
```

**Caveat**: `entry` takes the key by value, so with `String` keys it allocates even when the entry exists. For hot borrowed lookups either accept the double hash (`get_mut` first, `insert` on miss) or use `hashbrown::HashMap::entry_ref(&borrowed)`, which allocates the owned key only on insert.
**Hashers**: the default SipHash 1-3 is DoS-resistant but slow for short and integer keys. If hashing is hot and HashDoS is not a concern: `rustc_hash::FxHashMap` (integer keys; rustc saw 4-84 % slowdowns going back to the default), `foldhash` (hashbrown's default), `ahash` (AES-based; still maintained but slower-moving). Try more than one; the win is program-specific. Ban the default `HashMap` with Clippy `disallowed-types` once you standardize.

```rust
use rustc_hash::FxHashMap;

pub fn index(ids: &[u32]) -> FxHashMap<u32, usize> {
    let mut m: FxHashMap<u32, usize> = FxHashMap::default();
    m.reserve(ids.len());
    for (i, &id) in ids.iter().enumerate() {
        m.insert(id, i);
    }
    m
}
```

Sources: https://doc.rust-lang.org/std/collections/hash_map/enum.Entry.html · https://nnethercote.github.io/perf-book/hashing.html

## B2. `sort_unstable`, `sort_by_cached_key`, `total_cmp`

**Rule**: when equal elements need not keep order, `sort_unstable*` / `select_nth_unstable` (in place, no scratch allocation). An expensive key closure goes through `sort_by_cached_key` (computed once per element). Floats compare with `total_cmp`.
**Detect**: `.sort()` on primitives; `sort_by_key` with an allocating key; `partial_cmp().unwrap()` on floats.

```rust
pub fn sort_scores(v: &mut [f64]) {
    v.sort_unstable_by(|a, b| a.total_cmp(b));
}

pub fn sort_ci(v: &mut [String]) {
    v.sort_by_cached_key(|s| s.to_lowercase());
}
```

**Facts**: Rust 1.81 replaced both algorithms (driftsort stable, ipnsort unstable) and both **may panic on an inconsistent `Ord`** (e.g. NaN through `partial_cmp().unwrap()`) instead of returning garbage. The stable/unstable gap narrowed in 1.81; benchmark on your data.
Source: https://blog.rust-lang.org/2024/09/05/Rust-1.81.0/

## B3. `memchr` / `bstr` for byte search

**Rule**: byte and substring search in `&[u8]`/`&str` on hot paths -> `memchr::{memchr, memchr2, memchr3, memchr_iter}`, `memchr::memmem::Finder` (build once, reuse); `bstr` for text that may not be valid UTF-8 (`lines`, `split_str`, `find`) without paying validation.
**Detect**: `haystack.iter().position(|&b| b == x)`; `.split('\n')` over big buffers; `String::from_utf8(bytes)?` only to search.

```rust
pub fn first_line(buf: &[u8]) -> &[u8] {
    match memchr::memchr(b'\n', buf) {
        Some(pos) => &buf[..pos],
        None => buf,
    }
}

pub struct Scanner {
    finder: memchr::memmem::Finder<'static>,
}

impl Scanner {
    pub fn new() -> Self {
        Self { finder: memchr::memmem::Finder::new(b"HTTP/1.1") }
    }

    pub fn find(&self, haystack: &[u8]) -> Option<usize> {
        self.finder.find(haystack)
    }
}
```

**Caveat**: std `str::find` already uses memchr-style code for single bytes on many targets; gains are largest for 2-3 byte alternation, repeated needles and raw `&[u8]`. For very short haystacks overhead may dominate.
Source: https://docs.rs/memchr/latest/memchr/

## B4. Number formatting: `itoa`, `zmij`/`ryu`, std `format_into` (1.98)

**Rule**: serializers, loggers and CSV/JSON writers that format millions of numbers should bypass `core::fmt`: `itoa::Buffer` for integers, `zmij::Buffer` (dtolnay's newer Schubfach-based float printer, which the `itoa` README now points to) or `ryu::Buffer` for floats, then append the returned `&str`. Since Rust 1.98 std offers `<int>::format_into` writing into a `core::fmt::NumBuffer` (re-exported in std from 1.99); the release post reports performance close to `itoa`. See https://doc.rust-lang.org/std/fmt/struct.NumBuffer.html for the constructor and usage.
**Detect**: `n.to_string()` / `format!("{}", n)` in a loop; `core::fmt::num` frames in the profile.

```rust
pub fn append_ints(out: &mut String, ns: &[u64]) {
    let mut b = itoa::Buffer::new();
    for &n in ns {
        out.push_str(b.format(n));
        out.push(',');
    }
}
```

**Caveat**: only matters when number formatting is a measurable fraction; floats print the shortest round-trip form, not fixed precision.
Sources: https://github.com/dtolnay/itoa · https://github.com/dtolnay/zmij · https://blog.rust-lang.org/2026/08/20/Rust-1.98.0/

## B5. `write!` into a reused buffer, never `push_str(&format!(..))`

Covered with measurements in memory-layout.md A3. Short form: hold one `String` (or `Vec<u8>`/`BufWriter`), `clear()` per iteration, `use std::fmt::Write; write!(buf, ..)`. Clippy `format_push_string` (pedantic) finds the anti-pattern.

## B6. Overflow checks and explicit arithmetic intent

**Rule**: release has `overflow-checks = false`, dev has `true`. Make intent explicit where data-derived math happens: `checked_*` / `saturating_*` for untrusted lengths and offsets, `wrapping_*` only for hashes, checksums and PRNGs where wrapping is the intent (same codegen in both profiles, no debug panic); never as a way to silence real overflow. Do not enable `overflow-checks` in a hot release profile without measuring; it blocks vectorization.
**Detect**: untrusted `a + b` or `as usize` casts used for indexing or allocation; hashing code written with plain `*`/`+` (panics in debug).
Source: https://nnethercote.github.io/perf-book/build-configuration.html · https://doc.rust-lang.org/cargo/reference/profiles.html

## B7. Dispatch: generics or a hand-written enum before `dyn`

**Rule**: in a hot loop over a closed, small set of implementors, avoid `Box<dyn Trait>`/`&dyn Trait` per element. Use generics (monomorphized, inlinable) or an enum that implements the trait by `match`. Keep `dyn` at cold boundaries (plugin APIs, wiring).
**Detect**: `Vec<Box<dyn Trait>>` iterated per request or frame; indirect calls and vtable/heap misses in the profile.

```rust
pub trait Shape {
    fn area(&self) -> f64;
}

pub struct Circle(pub f64);
pub struct Rect(pub f64, pub f64);

impl Shape for Circle {
    fn area(&self) -> f64 {
        std::f64::consts::PI * self.0 * self.0
    }
}

impl Shape for Rect {
    fn area(&self) -> f64 {
        self.0 * self.1
    }
}

pub enum AnyShape {
    Circle(Circle),
    Rect(Rect),
}

impl Shape for AnyShape {
    fn area(&self) -> f64 {
        match self {
            AnyShape::Circle(c) => c.area(),
            AnyShape::Rect(r) => r.area(),
        }
    }
}
```

`#[enum_dispatch]` (0.3) generates that enum and delegation; its 4-12x figures are the crate's own benchmarks on trivial method bodies and old hardware, and the gain shrinks as bodies grow.
**Caveat**: the enum is the size of its largest variant (box big ones); adding an implementor touches the enum.
Source: https://docs.rs/enum_dispatch/latest/enum_dispatch/

## B8. `const fn` lookup tables in `static`

**Rule**: replace runtime-built tables (CRC, hex, base64 decode, ASCII class maps) with `const fn`-built `static` arrays: zero startup cost, lives in `.rodata`, and a `u8` index into 256 entries needs no bounds check. Prefer `static` over `const` for large tables (a `const` array may be copied at each use).
**Detect**: `LazyLock<[u8; 256]>` computing a pure table; a `match` on bytes with many arms that could be an index.

```rust
const fn build() -> [u8; 256] {
    let mut t = [0u8; 256];
    let mut i = 0;
    while i < 256 {
        t[i] = (i as u8).is_ascii_alphanumeric() as u8;
        i += 1;
    }
    t
}

static IS_ALNUM: [u8; 256] = build();

pub fn is_alnum(b: u8) -> bool {
    IS_ALNUM[b as usize] != 0
}
```

**Caveat**: `const fn` loops use `while`; huge tables compete for L1/L2 and can lose to computation. More const-stable std since 1.85-1.94 (`mem::swap`, float `abs/min/max/clamp`, `copy_from_slice`, `rotate_left`, `mul_add`) widens what tables can precompute.

## B9. `Vec` operations: `retain`, `swap_remove`, `extract_if` (1.87), `drain`, `push_mut` (1.95)

**Rule**: `retain` removes many elements in one O(n) pass (repeated `remove(i)` is O(n) each); `swap_remove` is O(1) when order is irrelevant; `extract_if` removes and yields matches in place while keeping the allocation; `drain(..)` moves elements out while reusing the buffer; `push_mut` returns `&mut T` to the new element without a second lookup; `pop_if` (1.86) is check-and-pop in one call.
**Detect**: `for i in (0..v.len()).rev() { if cond { v.remove(i); } }`; `v = v.into_iter().filter(..).collect()`; `partition` just to split out matches; `v.push(x); let r = v.last_mut().unwrap();`.

```rust
pub struct Job {
    pub done: bool,
}

pub fn drain_done(v: &mut Vec<Job>) -> Vec<Job> {
    v.extract_if(.., |j| j.done).collect()
}

pub fn push_and_init(v: &mut Vec<String>) {
    let s = v.push_mut(String::new());
    s.push_str("ready");
}
```

`HashMap`/`HashSet::extract_if` 1.88; `BTreeMap`/`BTreeSet::extract_if` 1.91; `VecDeque::pop_front_if/pop_back_if` 1.93, `retain_back` 1.99.
Sources: https://nnethercote.github.io/perf-book/standard-library-types.html · https://github.com/rust-lang/rust/blob/master/RELEASES.md

## B10. Slice cursors and disjoint borrows: `split_off` (1.87), `get_disjoint_mut` (1.86)

**Rule**: parse by shrinking a `&[u8]` cursor in place with `split_off(..n)` / `split_off_first()` instead of recomputing indices; take two `&mut` into one slice or map with `get_disjoint_mut` instead of `split_at_mut` gymnastics or clone-out/insert-back.

```rust
pub fn header(mut rest: &[u8]) -> Option<(&[u8], &[u8])> {
    let hdr = rest.split_off(..4)?;
    Some((hdr, rest))
}

pub fn add_into(v: &mut [u32], i: usize, j: usize) {
    if let Ok([a, b]) = v.get_disjoint_mut([i, j]) {
        *a += *b;
    }
}
```

`HashMap::get_disjoint_mut([&k1, &k2])` returns `[Option<&mut V>; 2]`. `split_first_chunk`/`split_last_chunk` (1.77) read fixed-size headers without `try_into`. `as_array` (1.93) views a slice as `&[T; N]`.
Source: https://github.com/rust-lang/rust/blob/master/RELEASES.md (1.86, 1.87, 1.93)

## B11. `Rc<RefCell<T>>` graphs -> indices

**Rule**: `Rc<RefCell<T>>` costs a heap allocation per node, refcount traffic per clone, a borrow-flag check per access (and `BorrowMutError` panics), and pointer chasing. In hot paths use indices into a `Vec`/arena (memory-layout.md C3), plain `&mut` passing, or ownership plus message passing. Clone an `Rc` only at genuine share points; borrow `&T` for calls.
**Detect**: `Rc<RefCell<..>>` stored in many structs; `.clone()` on `Rc`/`Arc` in loops only to satisfy the borrow checker; Clippy `redundant_clone`, `rc_clone_in_vec_init`, `await_holding_refcell_ref`.

```rust
pub struct Node {
    pub parent: Option<u32>,
    pub children: Vec<u32>,
}

pub struct Arena {
    pub nodes: Vec<Node>,
}
```

`Arc::make_mut` gives clone-on-write for shared data; each atomic refcount change on an `Arc` shared across cores contends on its cache line.
Source: https://nnethercote.github.io/perf-book/heap-allocations.html

## B12. Iterator and string additions worth knowing

| API | Since | Use |
|---|---|---|
| `iter::repeat_n` | 1.82 | exact-size repeat, clones n-1 times |
| `slice::chunk_by` | 1.77 | run grouping without allocation |
| `Peekable::next_if_map` | 1.94 | peek + transform + consume (tokenizers) |
| `str::floor_char_boundary` / `ceil_char_boundary` | 1.91 | safe truncation without a loop |
| `str::substr_range`, `[T]::subslice_range` | 1.98 | recover the offset of a sub-slice |
| `String::from_utf8_lossy_owned` | 1.99 | reuses the buffer when already valid |
| `fmt::from_fn` | 1.93 | `Display` adapters without a `String` |
| `IntoIterator for Box<[T; N]>` | 1.99 | by-value iteration without a `Vec` |
| `core::range::{Range, RangeInclusive}` | 1.96 | `Copy` ranges that implement `IntoIterator` |
| `RangeInclusive` iteration optimized | 1.99 | free on upgrade |

Regression to watch: 1.93 removed the `Copy` specialization inside std, so some APIs may call `Clone::clone` instead of bitwise copies; re-benchmark clone-heavy `Vec<T: Copy>` paths (`to_vec`, `extend_from_slice`) after upgrading.
Source: https://github.com/rust-lang/rust/blob/master/RELEASES.md

## B13. `#[track_caller]`

Keep it on small panicking helpers whose job is to report the caller. It appends an implicit location argument to the ABI and needs a shim for function pointers and `dyn`; no measured numbers exist, so treat the cost as small but nonzero and do not blanket-annotate hot non-panicking functions.
Source: https://users.rust-lang.org/t/consequences-of-annotating-every-single-crate-function-with-track-caller-attribute/129154

## Detection cheat-sheet (grep seeds)

```
contains_key + insert, get_mut + insert         -> B1 entry
\.sort\(\) on primitives; sort_by_key allocating -> B2
\.iter\(\)\.position\(\|&?b\| b ==               -> B3 memchr
\.to_string\(\)|format!\( in loops               -> B4/B5
Box<dyn .*> in a Vec in a hot loop               -> B7
LazyLock<\[u8; 256\]>                            -> B8 const table
\.remove\(i\) in loops; filter\(\)\.collect\(\)  -> B9 retain/extract_if
split_at_mut .* to get two &mut                  -> B10 get_disjoint_mut
Rc<RefCell<                                      -> B11
#\[track_caller\] on hot fns                     -> B13
```
