# Performance-relevant Rust features by version (1.75 -> 1.101 nightly)

Stable at research time: **1.99.1** (2026-10-15; LLVM 23). Beta 1.100 ships 2026-11-12; nightly is 1.101 (stable 2026-12-24). Six-week train: 1.90 (2025-09-18), 1.91 (10-30), 1.92 (12-11), 1.93 (2026-01-22), 1.94 (03-05), 1.95 (04-16), 1.96 (05-28), 1.97 (07-09), 1.98 (08-20), 1.99 (10-01).
Primary source for every version number: https://github.com/rust-lang/rust/blob/master/RELEASES.md (also https://doc.rust-lang.org/stable/releases.html), cross-checked with release posts at `https://blog.rust-lang.org/YYYY/MM/DD/Rust-1.N.0/`. Beta/nightly items from https://releases.rs/.

## Toolchain and build

| Feature | Since | Effect |
|---|---|---|
| Cross-crate inlining of small leaf functions without `#[inline]` | 1.75 | release, non-incremental only; `#[inline]` still needed for small non-leaf `pub` fns and MSRV < 1.75 |
| `-O` means `opt-level=3` for bare `rustc` (was 2) | 1.86 | matches Cargo release |
| rustc built with ThinLTO + PGO on aarch64 Linux | 1.86 | up to ~30 % faster compiler there |
| `-C dwarf-version` stable | 1.88 | DWARF 5 debuginfo |
| Cargo automatic cache GC | 1.88 | disk, not time |
| Non-leaf frame pointers default on aarch64 Linux / Apple | 1.89 | reliable profiler stacks, small runtime cost |
| **`lld` default linker on `x86_64-unknown-linux-gnu`** (opt out `-C linker-features=-lld`) | **1.90** | ripgrep debug: incremental link 7x faster, ~40 % less end-to-end incremental time, clean debug build ~20 % faster; remove hand-configured lld, keep `mold` only by preference. Post: https://blog.rust-lang.org/2025/09/01/rust-lld-on-1.90.0-stable/ |
| Cargo `build.build-dir` stable | 1.91 | put intermediates on a fast disk/tmpfs |
| Cargo book chapter "Optimizing Build Performance" | 1.92 | docs |
| `-C jump-tables=bool` stable | 1.93 | disable jump tables for CFI/predictable branches |
| Global allocator may use TLS and `thread::current()` | 1.93 | thread-caching custom allocators |
| Symbol mangling v0 by default | 1.97 | better profiler/backtrace symbols; old demanglers may fail |
| Cargo `build.warnings` config | 1.97 | replaces `RUSTFLAGS=-Dwarnings` and does not invalidate the build cache |
| LLVM upgrades | 20 in 1.87, 21 in 1.91, 22 in 1.95, **23 in 1.99** | vectorizer/codegen improvements; LLVM 22 unblocks tail calls |
| Cargo: incremental off by default when `CI` env is set | 1.99 | no useless incremental overhead in CI |
| Cargo built-in `debug` profile (same as `dev` for now) | 1.99 | groundwork for a lighter `dev` |
| Rustdoc trait-impl filtering | 1.99 | ~20 % average, up to 40 % faster rustdoc |

## Language and codegen controls

| Feature | Since | Use |
|---|---|---|
| Inline `const { .. }` blocks | 1.79 | compile-time values in generic/array-init contexts; macros accept them since 1.87 |
| `NonZero<T>` generic | 1.79 | `Option<NonZero<u32>>` is 4 bytes; `NonZero<char>` 1.89 |
| `hint::assert_unchecked` (unsafe) | 1.81 | state an invariant the optimizer cannot derive |
| driftsort (`sort*`) and ipnsort (`sort_unstable*`, `select_nth_unstable*`) | 1.81 | faster sorts; may panic on an inconsistent `Ord` |
| New `binary_search` implementation | 1.82 | may return a different equal element |
| Strict/exposed provenance APIs | 1.84 / 1.85 | pointer tagging and arenas LLVM can still optimize |
| Edition 2024; `async \|\| {}` closures and `AsyncFn*` | 1.85 | closures can lend captured state to the future: fewer clones and `Box<dyn Future>` |
| Trait-object upcasting | 1.86 | no duplicate vtables or `as_any` workaround |
| **Safe `#[target_feature]` functions** | **1.86** | callable safely from a caller with a superset of features; `unsafe` otherwise |
| **Safe non-pointer `std::arch` intrinsics** inside a matching `#[target_feature]` fn | **1.87** | loads/stores still `unsafe` |
| `asm_goto` | 1.87 | inline asm jumping to Rust labels |
| `#[unsafe(naked)]` functions | 1.88 | hand-written prologue/epilogue |
| `hint::select_unpredictable` | 1.88 | branchless select for 50/50 conditions |
| let chains (edition 2024) | 1.88 | flatter control flow, no perf claim |
| AVX-512 target features and intrinsics | 1.89 | explicit AVX-512 on stable |
| `repr(u128/i128)` | 1.89 | |
| `strict_*` integer ops; `carrying_add/mul`, `borrowing_sub` | 1.91 | always-panic arithmetic; limb arithmetic without `u128` |
| `unchecked_shl/shr`, `unchecked_neg` | 1.93 | drop the overflow branch given a precondition |
| `avx512fp16`, aarch64 NEON fp16 intrinsics (not the `f16` type) | 1.94 | |
| **`hint::cold_path`** | **1.95** | mark an unlikely arm; replaces nightly `likely`/`unlikely` hacks |
| `cfg_select!` | 1.95 | drop the `cfg-if` dependency |
| `str::contains` sped up on aarch64 + NEON | 1.95 | free |
| `core::range::{Range, RangeFrom, RangeInclusive}` | 1.96 | `Copy` ranges implementing `IntoIterator` |
| `isolate_highest_one/lowest_one`, `bit_width` | 1.97 | bit tricks as single intrinsics |
| **`f32/f64::algebraic_{add,sub,mul,div,rem}`** | **1.98** | fast-math-like reassociation per op, never UB |
| **`<int>::format_into` + `fmt::NumBuffer`** | **1.98** (std re-export 1.99) | integer formatting close to `itoa` without allocation |
| NEON `vdot*` intrinsics | 1.98 | |
| `RangeInclusive` iteration optimized | 1.99 | free; exhausted-range `start()/end()` behaviour changed |
| Removal of `Copy` specialization in std internals | 1.93 | possible regressions: some APIs now call `Clone::clone`; re-benchmark `to_vec`/`extend_from_slice` on `Copy` types |

## Std APIs that avoid allocation, bounds checks or copies

| API | Since |
|---|---|
| `split_first_chunk` / `split_last_chunk`, `slice::chunk_by` | 1.77 |
| `LazyCell`, `LazyLock` | 1.80 |
| `Box/Rc/Arc::new_uninit(_slice)`, `iter::repeat_n` | 1.82 |
| `HashMap::with_hasher` and `BuildHasherDefault::new` const | 1.85 |
| `<[T]>::get_disjoint_mut`, `HashMap::get_disjoint_mut`, `Vec::pop_if`, `OnceLock::wait` | 1.86 |
| `<[T]>::split_off(_mut)`, `split_off_first/last`, `Vec::extract_if`, `String::extend_from_within`, `Box<MaybeUninit<T>>::write`, `unbounded_shl/shr`, `is_multiple_of` | 1.87 |
| **`<[T]>::as_chunks` / `as_chunks_mut` / `as_rchunks`**, `HashMap/HashSet::extract_if`, `Cell::update` | **1.88** |
| `File::lock/try_lock/unlock`, `DerefMut` for `Lazy*`, `OsString::leak`/`PathBuf::leak` | 1.89 |
| `BTreeMap/BTreeSet::extract_if`, `AtomicPtr::fetch_ptr_add` family, `core::array::repeat`, `iter::chain` fn | 1.91 |
| **`Box/Rc/Arc::new_zeroed(_slice)`**, `RwLockWriteGuard::downgrade`, `Iterator::eq` specialized for `TrustedLen` | **1.92** |
| `<[MaybeUninit<T>]>::write_copy_of_slice` / `assume_init_ref/_mut`, `<[T]>::as_array`, `VecDeque::pop_front_if/pop_back_if`, `String/Vec::into_raw_parts`, `fmt::from_fn` | 1.93 |
| **`<[T]>::array_windows`**, `LazyLock::get/get_mut/force_mut`, `Peekable::next_if_map` | **1.94** |
| **`Vec::push_mut/insert_mut`** (also `VecDeque`, `LinkedList`), **`Atomic*::update/try_update`**, `MaybeUninit` array conversions, `Layout::repeat/extend_packed` | **1.95** |
| `BTreeMap::append` optimized, `From<T> for LazyLock`, `NonZero` range iteration | 1.96 |
| `Atomic*::from_mut/get_mut_slice/from_mut_slice`, `str::substr_range`, `subslice_range`, `strip_circumfix`, `String::from_utf16le/be` | 1.98 |
| `Vec::into_parts/from_parts`, `Box::into_non_null`, `String::from_utf8_lossy_owned`, `VecDeque::retain_back`, `LocalKey<Cell<T>>::update`, `IntoIterator for Box<[T; N]>` | 1.99 |

## Beta and nightly (do not depend on in stable products)

| Item | Status 2026-11-08 | Why it matters |
|---|---|---|
| **`Allocator` trait** stabilized (PR #156882), most `Box` impls generalized over `A` | **1.100 beta, stable 2026-11-12** | arena allocators for std collections; check the 1.100 notes for which `*_in` constructors are stable |
| `!` never type, `bool::toggle`, `unsafe_cell_access`, SSE-register ABI for SIMD types, integer min/max intrinsics; `Iterator::min/max(_by_key)` use overridden `min`/`max` | 1.100 beta | `Result<T, !>` zero-cost; SIMD args in registers |
| `slice_split_once`, `funnel_shifts`, `#[inline]` honoured on the generated `poll` of `async fn`, min external LLVM 22 | 1.101 nightly (stable 2026-12-24) | inlining control for async hot paths |
| `std::simd` (`portable_simd`, #86656) | nightly only | use `as_chunks` + safe `#[target_feature]` or stable SIMD crates instead |
| `hint::likely` / `hint::unlikely` (`likely_unlikely`, #151619) | nightly only | use `cold_path` |
| Explicit tail calls (`become`) and `loop_match` | unstable; 2026 project goal | guaranteed TCO for interpreters and state machines |
| Parallel front-end (`-Z threads=N`) | nightly only; 2026 goal to stabilize | faster `cargo check`/build on many cores |
| `-Z pack-coroutine-layout` | nightly experiment | smaller async state machines (nested futures grow superlinearly) |
| Polonius alpha borrow checker | on nightly since 2026-08; stabilization planned | fewer clones to appease the borrow checker |
| Next-gen trait solver | on nightly since 2026-08 | compile-time; "Compiler performance optimization" goal tracks regressions |
| MIR move elimination (RFC 2026-04), in-place initialization | goals | remove memcpy of large moves; construct big values in place |
| Cranelift backend (`-Zcodegen-backend=cranelift`) | nightly | faster debug builds |

Sources: https://releases.rs/docs/1.100.0/ · https://releases.rs/docs/1.101.0/ · https://goals.rust-lang.org/2026/goals.html · https://blog.rust-lang.org/2026/08/04/enabling-polonius-alpha-on-nightly/ · https://doc.rust-lang.org/nightly/unstable-book/library-features/portable-simd.html
