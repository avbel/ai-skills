# Rust 1.99 Compatibility Notes

Checklist of changes in 1.99.0 that can break existing code. Source: <https://releases.rs/docs/1.99.0/> (Compatibility Notes section).

## Hard breaks

- **Legacy integral modules fully deprecated** — `std::i32::MAX`, `std::u8::MIN`, etc. Use associated constants: `i32::MAX`, `u8::MIN`.
- **`no_mangle_generic_items` is now a hard error** — `#[no_mangle]` on generic items was unsound; remove it or use `#[unsafe(no_mangle)]` on a non-generic wrapper.
- **Attributes that apply to nothing are errors in doc-comment code blocks** — fix the doctest or move the attribute.
- **`Pin::new_unchecked` safety invariants slightly changed** — audit `unsafe impl` blocks that construct `Pin` directly; re-read the current `Safety` section of the docs.
- **References to `extern` statics are no longer promoted** — code relying on `&EXTERN_STATIC` being `'static`-promoted may now error.
- **`#[repr(simd)]` on macro invocations** — a stable-Rust bug allowing this is fixed; `#[repr(simd)]` now errors where it was never legal.
- **Const-eval aborts on generics in the produced value's type.**
- **Union + value in one pattern is no longer recommended** — the Reference itself removed the pattern (the compiler could read the union before checking the rest of the scrutinee matches; UB in manually-written tagged unions). Split the match: match the tag first, then read the union field in a nested match.
- **`let` pattern inferred types now typecheck** — some inference-dependent code may fail.
- **ARM `-Ctarget-feature`/`-Ctarget-cpu` values that alter the ABI are hard errors now.**

## Lints that newly fire

- `raw_borrows_via_references` (allow by default): references that immediately decay into raw borrows.
- `unconditional_panic` now covers calls like `chunks(0)`/`windows(0)`.
- `unreachable_cfg_select_predicates` joined the `unused` group.
- Unused `#[path]` on inline modules; POSIX symbols added to `invalid/suspicious_runtime_symbol_definitions`.
- `semicolon_in_expressions_from_macros` now fires for **non-local** macros too — report it upstream to the macro's crate rather than silencing locally.
- Rustdoc: new `unused_footnote_definition` lint; attributes in doc code blocks that apply to nothing are errors.

## Behavior notes (not officially breaking)

- Exhausted `RangeInclusive` iterators: `start()`/`end()` may report different values; using an exhausted range as a slice index may behave differently.
- `transmute_copy` accepts `?Sized` types and now aborts (not unwinds) on size mismatch.
- `hermit` fs errors return `unsupported()` instead of raw errno 22.

## Cargo

- Incremental compilation disabled by default when `CI` is set.
- CI scripts asserting on exact warning output may need updating due to the new/extended lints above.
