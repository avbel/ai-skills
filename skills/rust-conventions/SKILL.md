---
name: rust-conventions
description: Rust 2024+ conventions for naming, ownership, error handling, traits, modules, iterators, concurrency, tests, and Clippy lint policy. Use when writing or modifying Rust source files, Cargo.toml, or Clippy configuration.
---

# Rust Conventions

Apply these conventions in Rust projects. These rules are written for any coding agent, including Claude Code, Codex, Cursor, and Copilot.

When driving an LLM to produce Rust that follows these conventions, also apply [`power-rust`](../power-rust/SKILL.md) — prompt patterns (crate version pinning, cancel-safety annotation, `// SAFETY:` invariants, lifetime call-site examples, multi-design trait proposals) that statistically reduce LLM Rust bugs.

## General

- Use Rust edition 2024 or later when the project allows it.
- After Rust code changes, run `cargo fmt` and `cargo clippy` when available and appropriate for the repository.
- When introducing or tightening lint policy, prefer Cargo-level Clippy lint groups over ad hoc command-only flags so CI, IDEs, and local runs share one policy.
- Encode incompatible target, platform, and feature combinations with `compile_error!` or `cfg` gates so unsupported builds fail early with a clear message.
- Prefer compile-time or debug-time invariant checks over relying on comments for safety-critical protocols.

## Clippy Lint Policy

For strict Rust projects, add lint groups in `Cargo.toml` using Cargo's `[lints.clippy]` table:

```toml
[lints.clippy]
pedantic = { level = "deny", priority = -1 }
nursery = { level = "warn", priority = -1 }
```

- Use `pedantic = "deny"` to make high-signal Clippy style and correctness lints part of the build contract.
- Use `nursery = "warn"` because nursery lints are useful but can be newer, noisier, or more likely to change.
- Keep `priority = -1` on lint groups so project-specific lint exceptions can override individual lints with the default priority.
- Prefer targeted lint exceptions in `Cargo.toml` for crate-wide policy and `#[allow(clippy::lint_name)]` only for narrow, justified local cases.
- If a project already has `[workspace.lints.clippy]`, put the policy there and opt crates into it with `[lints] workspace = true`.
- After changing lint policy, run `cargo clippy --all-targets --all-features` unless the repository documents a narrower command.

## Naming

- Types, traits, enums, and enum variants: `CamelCase`.
- Functions, variables, modules, and fields: `snake_case`.
- Constants and statics: `SCREAMING_SNAKE_CASE`.
- Constants require explicit type annotations.
- Lifetime parameters: short lowercase names such as `'a` and `'b`.
- Generic types: single uppercase names such as `T`, `E`, `K`, and `V`.

## Ownership and Borrowing

- Prefer `&T` for read-only access.
- Use `&mut T` only when mutation is needed.
- Transfer ownership with `T` only when the callee must own the data.
- Prefer `&str` over `&String` in function parameters.
- Use `String` for owned string data in structs.
- Use `.clone()` sparingly and intentionally.
- Use shadowing for type transformations instead of `mut` when the value will not change again.

## Structs and Enums

- Use field init shorthand when parameter names match field names.
- Use struct update syntax to create variants of existing structs.
- Prefer tuple structs for newtypes and single-purpose wrappers.
- Use unit-like structs for marker types and trait-only implementations.
- Structs should own their data unless lifetimes are explicitly managed.
- Prefer enums with data variants over separate structs when the types represent alternatives of the same concept.
- Model lifecycle-heavy protocols as explicit enums or state machines with named terminal states instead of scattered booleans.
- Add `#[must_use]` to handles, guards, permits, builders, and token-like values where dropping the value silently changes behavior or loses work.

## Error Handling

- Default to `Result<T, E>` for functions that can fail.
- Reserve `panic!` for contract violations, broken invariants, and unrecoverable states.
- Prefer `expect("reason")` over `unwrap()` when failure is impossible.
- `unwrap()` and `expect()` are acceptable in tests, examples, and prototypes.
- Use `?` for error propagation instead of manual `match` on `Result`.
- Encode invariants in the type system with validated newtype constructors when practical.

## Traits and Generics

- Use `impl Trait` for simple single-trait parameters.
- Use `<T: Trait>` when multiple parameters must share the same concrete type.
- Use `where` clauses when trait bounds would clutter the function signature.
- Respect the orphan rule: implement a trait on a type only if either the trait or type is local to the crate.
- Prefer `impl Trait` return types for a single concrete return type.
- Use `Box<dyn Trait>` when returning different concrete types.

## Lifetimes

- Rely on lifetime elision when possible.
- Annotate lifetimes only when the compiler requires it or when it clarifies a public API.
- Do not use `'static` to silence borrow errors. Fix the ownership issue.

## Modules and Visibility

- Default to private. Mark only crate API items as `pub`.
- Use `pub use` re-exports to flatten deep module paths for consumers.
- Use `src/module_name.rs` for leaf modules.
- Use `src/module_name/mod.rs` or `src/module_name.rs` with `src/module_name/` for modules with submodules.
- Use `crate::` for absolute paths within the crate and `super::` for parent modules.

## Closures and Iterators

- Let the compiler infer closure types unless annotation improves clarity.
- Use `move` closures only when transferring ownership is needed.
- Use the least restrictive closure trait bound: `Fn`, then `FnMut`, then `FnOnce`.
- Prefer iterator chains for transformations.
- Always terminate lazy iterator chains with a consuming adaptor.
- Use `.iter()` for borrowed values, `.iter_mut()` for mutable borrowed values, and `.into_iter()` for owned values.

## Smart Pointers and Concurrency

- Use `Box<T>` for recursive types or large data with single ownership.
- Use `Rc<T>` for single-threaded shared ownership.
- Use `Arc<T>` for thread-safe shared ownership.
- Pair `Arc<T>` with the right synchronization primitive for shared mutable state when message passing is not a better fit.
- Prefer message passing with channels over shared mutable state when threads do not need direct access to the same data.
- Types must implement `Send` to transfer ownership between threads and `Sync` for shared references across threads.
- Before choosing a lock type, double-check whether the guarded code runs in synchronous threads, async tasks, or both.
- Do not mix synchronization families casually. If a module already uses `std::sync::Mutex`, `parking_lot::Mutex`, `tokio::sync::Mutex`, `RwLock`, `Semaphore`, or channels for a shared resource, follow that design unless there is a clear reason to change it.
- Use `std::sync::Mutex` or `parking_lot::Mutex` for short, non-async critical sections where the lock guard is never held across `.await`.
- Use `tokio::sync::Mutex` only when async code must hold the guard across `.await` or must coordinate fairly between Tokio tasks.
- Do not hold a blocking mutex guard across `.await`; restructure the code, clone/move the needed data out, or switch to an async-aware primitive.
- For read-heavy shared state, consider `RwLock`; for bounded concurrency, consider `Semaphore`; for ownership transfer or work distribution, use channels.
- Keep lock acquisition order consistent across the crate and document it when multiple locks may be held together.
- For subsystems with multiple lock classes, document a lock hierarchy with stable rank names. When practical, enforce the hierarchy in debug builds or behind an opt-in diagnostics feature.
- When operations cross module boundaries while holding locks, document both lock rank and module ownership so cross-module deadlock patterns can be reviewed.
- Do not create orphan background work. Every spawned thread or task should have an owner, cancellation/shutdown path, and join/abort/drain decision.
- Treat cancellation and shutdown as protocols for code that performs external effects. Reserve resources before an `.await`, then commit in a distinct step after cancellation-sensitive work is safe to finish.

## Testing

- Place unit tests in a `#[cfg(test)] mod tests` block at the bottom of the source file and import `use super::*;`.
- Use `assert_eq!` and `assert_ne!` instead of `assert!` for value comparisons.
- Add custom assertion messages when they clarify intent.
- Use `#[should_panic(expected = "substring")]` to verify specific panic messages.
- Use `Result<(), E>` return type in tests when it simplifies `?`-based setup.
