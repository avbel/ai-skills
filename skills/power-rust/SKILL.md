---
name: power-rust
description: Prompt patterns that reduce common LLM Rust bugs — pin crate versions and async runtime, annotate cancel-safety per async fn, require `// SAFETY:` invariants on every `unsafe`, demand example call sites for non-trivial lifetimes, and propose multiple trait designs for user confirmation. Use when writing or reviewing AI-generated Rust.
---

# Power Rust

Five prompt patterns, distilled from a six-month benchmark of LLM-generated Rust ([habr.com/ru/articles/1035712](https://habr.com/ru/articles/1035712/)), that statistically reduce the bugs models keep producing in Rust code. Apply them when you ask a coding model for Rust, and when you review AI-generated Rust before it lands.

These rules are written for any coding agent — Claude Code, Codex, Cursor, Copilot — and for the humans driving them.

## 1. Pin crate versions and async runtime in the prompt

Do **not** write `"write an HTTP handler"`. Instead write:

```
write an HTTP handler, axum 0.7, tokio 1.35, sqlx 0.7 with postgres
```

The model knows multiple incompatible APIs for popular crates. Without a version anchor it averages across them, which produces e.g. `parking_lot::Mutex` held across `.await`, or `sqlx` API calls that match no real release. In the source benchmark this single change dropped Mutex-category errors from 46% to 19%.

Always state in the prompt:

- The exact major.minor of every direct dependency you'll touch (`axum 0.7`, not "axum").
- The async runtime and its version (`tokio 1.35`, `async-std`, `smol`).
- The driver/feature flag where it matters (`sqlx 0.7 with postgres`, `reqwest with rustls-tls`).
- The minimum supported Rust edition / version if non-default.

## 2. Annotate cancel-safety on every async fn

Cancel-safety has no signature — `async fn process(&mut self)` looks identical whether it's safe to drop mid-future or not. The model cannot infer it from local context alone, so force it to write the conclusion down.

Prompt template:

```
For every async fn in the output, add a line comment directly above the
signature that says either `// cancel-safe: <reason>` or
`// not cancel-safe: <reason>`. The reason must name the specific await
point that is or isn't safe to drop.
```

This works far better than the looser `"write cancel-safe code"`, because it forces a per-function analysis instead of letting the model claim safety in prose. Treat any `not cancel-safe` annotation as a review checkpoint: either wrap the call in a cancellation-resistant primitive (`tokio::select!` with a guard branch, a `JoinHandle` you `abort()` explicitly) or document why the caller cannot cancel.

Note from the docs: `tokio::io::AsyncReadExt::read` is cancel-safe; `read_exact` is not. Differences this subtle are exactly what the annotation surfaces.

## 3. Require `// SAFETY:` on every `unsafe` block

Prompt template:

```
Before every `unsafe { ... }` block and every `unsafe fn`, write a
`// SAFETY:` comment that enumerates the invariants the caller (or this
function) must uphold. One bullet per invariant. If you cannot list the
invariants, do not emit the unsafe block — return a safe alternative.
```

Two payoffs:

1. It gates `unsafe` behind a thought exercise. Many uses evaporate once the model has to write down why they're sound.
2. The comment is exactly the artifact a reviewer needs. `// SAFETY:` blocks plus `cargo clippy -- -W clippy::undocumented_unsafe_blocks` give you a mechanical audit trail.

Watch out for `unsafe` that *looks* safe — e.g. `std::ptr::read(buf.as_ptr() as *const Header)` on a network buffer. The fix is `read_unaligned`, but the model proposes it only when the prompt mentions "unaligned" or "network". If `// SAFETY:` cannot honestly list an alignment invariant, the code is wrong.

## 4. Demand example call sites for non-trivial lifetimes

When a signature has more than one lifetime parameter, or returns a reference that outlives the obvious local scope, ask the model to produce a calling example before it commits to the signature.

Prompt template:

```
Before writing this function, propose its signature and a minimal calling
example (5–15 lines) that exercises the lifetimes. Compile-check the
example mentally and explain which lifetime each borrow is bound to.
Only then write the body.
```

This forces the model out of local optimization. A signature like `fn get<'a>(&'a self, key: &'a str) -> &'a Value` looks fine in isolation but ties two unrelated lifetimes together at the call site; a worked example surfaces that immediately. In the source benchmark this pattern closed almost all lifetime-category errors.

When the example reveals the signature is wrong, the typical fixes are:

- Split the lifetimes (`<'a, 'b>` with an explicit contract between them).
- Return owned data (`String`) instead of a borrow (`&str`).
- Take an explicit lifetime bound on the input rather than letting it default.

## 5. Propose 2–3 trait designs and wait for user confirmation

Models design trait hierarchies worse than median humans when given a free hand: they over-genericize, miss object-safety constraints, and emit blanket impls that paint future implementors into a corner. The fix is **not** to forbid trait design — it's to require a checkpoint.

Prompt template:

```
Do not pick a trait design unilaterally. Propose 2–3 candidate trait
hierarchies for the task. For each, list:

- The trait signatures (no impls yet).
- Object-safety: object-safe or not, with the specific reason.
- Generics vs. associated types: which the design uses and why.
- Blanket-impl risk: any blanket impls and what they foreclose.
- Extension cost: how a new variant or new method lands.

Then stop and ask which design to use. Do not generate impls until the
user has picked or amended one.
```

The skill here is the checkpoint, not any particular design choice. If the model returns one design, push back and ask for alternatives.

## Mandatory: enable `clippy::pedantic` for files with AI-generated Rust

Any crate that contains LLM-generated Rust **must** enable `clippy::pedantic`. This is not a suggestion. The pedantic lints catch a large fraction of the model's residual mistakes (needless borrows, `unwrap` on infallible paths, mis-sized integer casts, redundant clones).

Add to `Cargo.toml`:

```toml
[lints.clippy]
pedantic = { level = "deny", priority = -1 }
nursery = { level = "warn", priority = -1 }
```

And run, for every PR that includes AI-written Rust:

```
cargo clippy --all-targets --all-features
```

`priority = -1` keeps the group at the lowest priority so individual `#[allow(clippy::lint_name)]` lines in justified spots continue to win. If the workspace already has `[workspace.lints.clippy]`, put the policy there and opt crates in with `[lints] workspace = true`. (Same policy as [`rust-conventions`](../rust-conventions/SKILL.md) — keep them in sync.)

For every `unsafe`, `unwrap`, `transmute`, `Arc`, `Mutex`, blanket impl, or hand-written `Send` / `Sync`, also do a manual review. Clippy will not catch these.

## Suggested (not required): nightly UB / unsoundness checking

For code that uses `unsafe`, FFI, or `transmute`, **consider** running:

- `miri` in nightly CI on the affected tests. Slow, but it catches undefined behaviour Clippy cannot see (uninitialized reads, pointer-provenance violations, data races in `unsafe` code). One caught UB usually repays a week of CI wall-time.
- `cargo-careful` as a lighter intermediate option, especially when miri is too slow for your suite.

These are advisory. Use them when the cost/benefit fits your project — don't treat them as gates.

## Source

- Article: [Я заставил LLM писать Rust полгода. Вот что они стабильно ломают](https://habr.com/ru/articles/1035712/) (habr.com)
- Section: *Промпты, которые реально работают*
