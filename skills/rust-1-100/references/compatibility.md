# Rust 1.100 Compatibility Notes

Checklist of changes in 1.100.0 that can break existing code. Sources: <https://releases.rs/docs/1.100.0/> and the release announcement.

## Never type fallout

- **Never-type fallback is now `!` on all editions** (2015/2018/2021 previously fell back to `()`; edition 2024 already did this). Rarely observable; can affect code that ignores the result of a function returning a generic parameter. The compiler may also detect more code as unreachable now.
- **`Infallible` is a type alias to `!`** — old `Result<T, Infallible>` code keeps working, but anything treating `Infallible` as a distinct enum (imports of its variants, exhaustive matching) breaks.
- **Trait methods are now resolved on an adjusted never type** — produced a future-compatibility warning earlier; a few crates needed published fixes. If a dependency fails, update it first.

## Language / compiler

- **`box` patterns are no longer syntactically allowed** — `box x` in patterns errored under lints before; now it is a syntax error. Migrate to `deref_patterns` (nightly) or explicit matching.
- **Closures capture variables used in `if let` more precisely** — may cause new borrow errors where a closure captured too much before.
- **Dyn-compatibility of trait objects is checked in more places** — `dyn Trait` usage that silently slipped through now errors.
- **Enum layout / explicit discriminants**: query-cycle errors reported in more cases.
- **`str::escape_debug` always escapes grapheme extenders**; let-else respects `expr` metavariable grouping in `macro_rules!`.
- **ARM targets**: `-Ctarget-feature`/`-Ctarget-cpu` values that would alter the ABI are now hard errors; ARMv7-A hardfloat targets need `VFPv3-D32` (`-Ctarget-feature=+d32` if your hardware lacks it).
- **x86 "Rust" ABI** uses SSE registers where always available — ABI-relevant for low-level FFI.
- **`repr(align)` fields inside `repr(packed)`** are now the deny-by-default lint `aligned_fields_in_packed` (was a hard error).
- Repeated `#[repr(..)]` attributes are now linted against.

## Libraries

- **Std uses Unicode 18.0.0** — char classification and `str` case handling follow the new Unicode tables; exact-behavior tests may need updates.
- **Some `Box` impls generalized to arbitrary allocators** — may cause new type-inference errors at call sites relying on the old impl shape.
- `ENOTSUP` now maps to `ErrorKind::Unsupported`.

## Cargo

- **New build-dir layout** (hash applied consistently, organized per build step): scripts/tests that walk or hardcode intermediate paths under `target/` must move to Cargo JSON messages. Some old workarounds are now unnecessary (see [cargo#17287](https://github.com/rust-lang/cargo/issues/17287)).
- **`cargo install` uses the tarball's lockfile by default**; `--locked` is a no-op — CI scripts checking for `--locked` output change.
- **`Iterator::{min,max}(_by_key)`** call different `Ord` methods — only matters for types with inconsistent `Ord` implementations.
- WASI SDK bumped 33 → 34 (wasm targets); `wasm32-wasip3` is Tier 2.
- Test harness allows repeated `--test-threads`/`--color` (last wins).
