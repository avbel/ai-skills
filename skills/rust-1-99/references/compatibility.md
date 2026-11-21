# Rust 1.99 Compatibility Notes

Checklist of changes in 1.99.0 that can break existing code. Source: <https://releases.rs/docs/1.99.0/> (Compatibility Notes section), plus rust-src stability attributes.

## Hard breaks

- **`no_mangle_generic_items` is now a hard error** — `#[no_mangle]`/`#[unsafe(no_mangle)]` on generic items is rejected; move it to a non-generic wrapper function.
- **Attributes that apply to nothing are errors in doc-comment code blocks** — fix the doctest or move the attribute.
- **`Pin::new_unchecked` safety invariants slightly changed** — audit `unsafe` blocks calling `Pin::new_unchecked` and re-read the current Safety section of its docs.
- **References to `extern` statics are no longer promoted** — code relying on `&EXTERN_STATIC` being promoted to `'static` may now error.
- **`#[repr(simd)]` on macro invocations** — a stable-Rust bug allowing this is fixed; `#[repr(simd)]` now errors where it was never legal.
- **Const-eval aborts on generics in the produced value's type.**
- **Union + value in a single pattern is no longer recommended** — the Reference itself removed the pattern: the compiler could read the union before checking the rest of the scrutinee, which is UB in manually-written tagged unions. Split the match: match the tag first, then read the union field in a nested match. (Documentation-guidance change; the pattern was never guaranteed.)
- **`let` pattern inferred types now typecheck** — some inference-dependent code may fail.

## New deprecations (warnings now, hard errors later)

- Legacy integral modules fully deprecated: `std::i32::MAX`, `std::u8::MIN`, … — use associated constants (`i32::MAX`, `u8::MIN`).
- Legacy float-module constants deprecated the same way: `std::f32::MAX` → `f32::MAX`.
- `Atomic*::fetch_update` deprecated in favor of `try_update`.

## Lints that newly fire

- `raw_borrows_via_references` (allow by default): references that immediately decay into raw borrows.
- `unconditional_panic` now covers calls like `chunks(0)`/`windows(0)`.
- `unreachable_cfg_select_predicates` joined the `unused` group.
- Unused `#[path]` on inline modules; POSIX symbols added to `invalid/suspicious_runtime_symbol_definitions`.
- `semicolon_in_expressions_from_non_local_macros` fires for **non-local** macros (a separate lint from the local one — `#[allow(semicolon_in_expressions_from_macros)]` will not silence it). Report it upstream to the macro's crate rather than silencing locally.
- Rustdoc: new `unused_footnote_definition` lint; attributes in doc code blocks that apply to nothing are errors.
- Trait methods are now resolved on an adjusted never type — code relying on the old resolution gets a future-compatibility warning.

## Behavior notes (not officially breaking)

- Exhausted `RangeInclusive` iterators: `start()`/`end()` may report different values; using an exhausted range as a slice index may behave differently.
- `transmute_copy` accepts `?Sized` types and now aborts (not unwinds) on size mismatch.
- `hermit` fs errors return `unsupported()` instead of raw errno 22.
- PowerPC inline asm: scalar floats were in the wrong vector lane on little-endian; generated code may change.
- `doc(cfg())` no longer filters doctests; anonymous lifetimes in associated-const types are inferred as `'static`.
- `str::escape_debug` no longer escapes U+FF9E/U+FF9F.

## Cargo

- Incremental compilation disabled by default when `CI` is set.
- CI scripts asserting on exact warning output may need updating due to the new/extended lints above.
