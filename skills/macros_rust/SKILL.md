---
name: macros_rust
description: Write and debug Rust macros — declarative macro_rules! (matchers, fragment specifiers block/expr/ident/ty/pat/tt/etc., repetitions $()sep rep, metavariable expressions ${count/index/len/ignore}, hygiene and $crate, follow-set restrictions), the core patterns (TT munchers, internal @-rules, counting, recursion limit), debugging with cargo-expand/trace_macros, declarative macros 2.0, and procedural macros (function-like, attribute, derive with helper attributes; proc-macro2 + quote + syn setup, parse_macro_input!, span-based error reporting). Use when authoring, reviewing, or debugging any Rust macro.
---

# Rust Macros

Patterns from *The Little Book of Rust Macros*. Two families: **declarative** (`macro_rules!`, "macro-by-example") and **procedural** (compiler plugins that map `TokenStream → TokenStream`). Prefer declarative for simple syntactic code-gen; reach for procedural when you need to inspect/transform AST (especially `#[derive]`).

## Golden rules

- A syntax extension must expand to a **complete, valid AST node** for its position (a full expression, item, etc.) — never a partial fragment like `1 +`.
- Metavariables captured as a non-`tt`/`ident`/`lifetime` fragment become **opaque AST nodes**: you can only substitute them into the output, never re-match or inspect their contents afterward.
- **`macro_rules!`** is **hygienic** for local variables and labels — identifiers it introduces can't collide with or capture the caller's, and vice versa. Names that must resolve at the call site (types, fns, other macros) are *not* auto-hygienic; reference your own crate's items via `$crate`. **Procedural macros are NOT hygienic by default**: `quote!` stamps new identifiers with `Span::call_site()`, so they can collide with or capture call-site names — use `Span::mixed_site()` for `macro_rules!`-like hygiene (see Procedural macros).
- Expansion is iterative: a macro may expand to another macro invocation, re-expanded until no invocations remain (bounded by the recursion limit).

## Declarative macros (`macro_rules!`)

```rust
macro_rules! name {
    (matcher) => { transcriber };   // rule 1
    (other)   => { ... };           // rule 2 — first matching rule wins, tried top-to-bottom
}
```

Captures: `$name:fragment`. Substitute with `$name`. Mix literal tokens and metavariables freely (within follow-set limits below).

### Fragment specifiers

| Specifier | Matches | Re-matchable after capture? |
|-----------|---------|------------------------------|
| `tt` | a single token tree (most flexible — use in munchers) | **yes** |
| `ident` | an identifier or keyword | **yes** |
| `lifetime` | a lifetime, e.g. `'a` | **yes** |
| `expr` | an expression | no (opaque) |
| `block` | a `{ ... }` block | no |
| `stmt` | a statement (no trailing `;`) | no |
| `pat` | a pattern (2021+: no top-level `|`) | no |
| `pat_param` | a pattern allowing top-level `|` | no |
| `path` | a type/expr path, e.g. `::std::mem::replace` | no |
| `ty` | a type | no |
| `lit` / `literal` | a literal (incl. `-1`) | no |
| `meta` | contents of an attribute `#[...]` | no |
| `item` | an item (fn, struct, impl, mod…) | no |
| `vis` | a (possibly empty) visibility qualifier | no |

Captures use the real compiler parser, so they are always syntactically valid for that fragment.

### Repetitions

General form **`$( ... ) sep rep`**:
- `sep` — optional separator token (commonly `,` or `;`); not a delimiter or repeat op.
- `rep` — `*` (0+), `+` (1+), or `?` (0 or 1, **no separator allowed**).
- Repeated metavariables can only be expanded **inside a matching repetition**, and the repetition structure in the transcriber must mirror the matcher. Nest arbitrarily.

```rust
macro_rules! vec_strs {
    ($($e:expr),* $(,)?) => {{          // trailing-comma tolerant
        let mut v = Vec::new();
        $( v.push(format!("{}", $e)); )*  // expands once per captured $e
        v
    }};
}
```

### Metavariable expressions

Form `${ op(...) }` (RFC 1584), stabilized in **Rust 1.83** — gate behind your MSRV. With `ident` a bound metavar and `depth` an integer:

- `${count(ident)}` / `${count(ident, depth)}` — total repeats (innermost / at depth).
- `${index()}` / `${index(depth)}` — current repetition index, counting outward.
- `${len()}` / `${len(depth)}` — number of repeats of that repetition.
- `${ignore(ident)}` — bind `$ident` for repetition but expand to nothing (drives a repeat by another var).
- `$$` — expands to a literal `$` (escape it, e.g. when generating a macro that itself uses `$`).

### Follow-set restrictions (a common gotcha)

After certain fragments, only specific tokens may legally follow in the matcher:
- `expr`, `stmt` → only `=>`, `,`, or `;`.
- `ty`, `path` → `=>`, `,`, `=`, `|`, `;`, `:`, `>`, `>>`, `[`, `{`, `as`, `where`, or a `block` fragment.
- `pat`, `pat_param` → `=>`, `,`, `=`, `if`, `in` (and `|` for `pat_param`).
- `vis` → any of `,`, an identifier, a type, or another fragment except `pat`.
- `tt`, `ident`, `lifetime`, `literal`, `meta`, `block`, `item` → may be followed by **anything**.

If you need to keep matching/inspecting a capture, grab it as `tt`/`ident`/`lifetime` — not `expr`/`ty`/etc.

### `$crate` and hygiene

Refer to items from the defining crate with `$crate::path::to::Item` so the macro works regardless of how the caller imported things. Local bindings the macro introduces are hygienic; if you intentionally want a name to be visible to the caller (rare), pass it in as an `ident` metavariable.

## Declarative macro patterns

- **Incremental TT muncher** — a recursive macro that consumes input one token tree at a time, accumulating, with a base case for empty input. Powerful but **quadratic** in input length; bump `#![recursion_limit = "256"]` for long inputs, put the hottest rules first, and avoid on very large inputs.
  ```rust
  macro_rules! count_tts {
      () => { 0usize };
      ($head:tt $($tail:tt)*) => { 1usize + count_tts!($($tail)*) };
  }
  ```
- **Internal rules** — hide helper arms behind a leading marker token (`@` by convention, e.g. `(@accum $($x:tt)*) => {...}`) so callers don't trigger them. Keep one public entry rule that dispatches to `@`-prefixed internal rules; faster and clearer than separate helper macros.
- **Counting** — `${count(...)}` where available; otherwise the classic `<[()]>::len(&[$(replace_expr!($x ())),*])` (map each item to `()`, take the slice length) avoids deep recursion. For a const, `[(); N]` array tricks.
- **Push-down accumulation / callbacks** — build output in an accumulator passed through recursive calls, or pass another macro name in to invoke on the result (`callback!(some_macro!(args))`).

## Debugging

- **`cargo expand`** (the `cargo-expand` plugin) — see fully expanded source. Underlying: `cargo rustc -- -Zunpretty=expanded` (nightly).
- **`trace_macros!(true)` / `trace_macros!(false)`** (nightly feature) — dump each macro invocation as it expands.
- **`log_syntax!(...)`** (nightly) — print the tokens passed to it, for targeted inspection inside a rule.
- `stringify!($($tt)*)` inside a rule to inspect what was captured at runtime.

## Declarative macros 2.0 (`macro`, unstable)

```rust
macro my_macro($e:expr) { /* ... */ }
```
`macro` items are real, path-scoped items (importable/`pub`-able like fns, no `#[macro_export]`/textual-scope quirks) with stronger hygiene. Still nightly-only; `macro_rules!` remains the stable choice.

## Procedural macros

Live in a dedicated crate (`Cargo.toml`: `[lib] proc-macro = true`). Three kinds, each mapping `TokenStream → TokenStream`. Use the ecosystem crates — author against `proc-macro2` (testable, usable outside proc-macro crates), parse with `syn`, generate with `quote!`.

```toml
[lib]
proc-macro = true
[dependencies]
syn = { version = "2", features = ["full"] }
quote = "1"
proc-macro2 = "1"
```

### The three kinds

```rust
use proc_macro::TokenStream;

// 1. Function-like — invoked as makro!(...). input = tokens inside the delimiters.
#[proc_macro]
pub fn my_macro(input: TokenStream) -> TokenStream { input }

// 2. Attribute — #[my_attr] or #[my_attr(args)]. TWO inputs.
//    attr = tokens in the (...) (empty for bare #[my_attr]); item = the annotated item.
//    Only THIS attribute is stripped from item; other attributes on the item remain in the stream.
//    Return replaces the item entirely (0+ items).
#[proc_macro_attribute]
pub fn my_attr(attr: TokenStream, item: TokenStream) -> TokenStream { item }

// 3. Derive — #[derive(MyDerive)]. input is always a struct/enum/union.
//    Output is APPENDED after the item (must be valid items). The ident names the derive.
//    `attributes(...)` declares inert helper attributes usable on fields/variants.
#[proc_macro_derive(MyDerive, attributes(my_helper))]
pub fn my_derive(item: TokenStream) -> TokenStream { TokenStream::new() }
```

### syn + quote

```rust
use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput};

#[proc_macro_derive(MyTrait)]
pub fn derive_my_trait(input: TokenStream) -> TokenStream {
    let ast = parse_macro_input!(input as DeriveInput); // structured parse; reports errors automatically
    let name = &ast.ident;
    let (ig, tg, wc) = ast.generics.split_for_impl();    // preserve generics + where-clause
    let expanded = quote! {
        impl #ig MyTrait for #name #tg #wc {
            fn name() -> &'static str { stringify!(#name) }
        }
    };
    expanded.into()
}
```
- `quote!` interpolates a local with `#var` and repeats over a `ToTokens` iterator with `#( #items )*` (with optional separators), mirroring `macro_rules!` repetition.
- `syn` parses standard Rust nodes (need the `full` feature for arbitrary items); `DeriveInput` for derives; implement `syn::parse::Parse` for custom non-Rust DSL syntax.
- Everything carries **spans** — keep input spans on generated tokens so error messages and IDE diagnostics point at the user's code. Generated identifiers default to `Span::call_site()` (unhygienic — can capture/collide with call-site names); use `Span::mixed_site()` for hygienic helper bindings, e.g. `syn::Ident::new("tmp", Span::mixed_site())`.

### Error reporting

Emit a real compiler error instead of `panic!`:
```rust
return syn::Error::new_spanned(&field, "unsupported field type")
    .to_compile_error()
    .into();
```
This points the diagnostic at `field`'s span. `panic!` aborts the whole compilation with a generic message — avoid it.

## When to use which

- **`macro_rules!`** — variadic/DSL syntax, repetitive code-gen, no AST inspection needed. Stable, no extra deps, no separate crate.
- **Procedural** — `#[derive(...)]`, attribute transforms, anything needing to read field/variant structure, types, generics, or produce errors with precise spans. Costs a separate crate + `syn`/`quote` compile time.

## Cross-references

- General style → `rust-conventions`, `rust-patterns` · Design → `design-patterns-rust`
- Build/perf impact of heavy proc-macro deps → `high_performance_rust`
