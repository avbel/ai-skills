---
name: rust-1-99
description: Rust 1.99.0 (2026-10-01) new features — defining C-variadic functions with VaList, layout of unsized types from raw pointers (size_of_val_raw), IntoIterator for Box<[T; N]>, attribute macros over outlined modules, Cargo debug profile and workspace default-features override. Use when upgrading to Rust 1.99, writing C-variadic FFI, or reading raw-pointer metadata.
---

# Rust 1.99 — New Features

Rust 1.99.0 was released on **2026-10-01** (branched from master 2026-08-14, LLVM 23). Use this skill when a project targets Rust ≥ 1.99 or uses its new APIs. For the release after this one see the [`rust-1-100`](../rust-1-100/SKILL.md) skill (never type, `Allocator`, `DropGuard`). For the full compatibility notes see [references/compatibility.md](references/compatibility.md).

- Announcement: <https://blog.rust-lang.org/2026/10/01/Rust-1.99.0/>
- Detailed changelog: <https://releases.rs/docs/1.99.0/>
- Performance-relevant fallout of this release: see the `rust-high-performance` skill's [new-rust-features reference](../rust-high-performance/references/new-rust-features.md).

## C-Variadic Function Definitions

Rust could already *call* C variadic functions (e.g. `libc::printf`). 1.99 stabilizes *defining* them in Rust, for `"C"` and `"C-unwind"` ABIs. The `...` parameter has type `VaList`, ABI-compatible with C's `va_list` across targets. Which types may be read is guarded by the `VaArgSafe` trait.

```rust
// SAFETY: must be called with (at least) 2 i32 arguments.
unsafe extern "C" fn sum(mut args: ...) -> i32 {
    // SAFETY: guaranteed by the caller.
    let a = unsafe { args.next_arg::<i32>() };
    let b = unsafe { args.next_arg::<i32>() };
    a + b
}

fn main() {
    // SAFETY: two i32 arguments are passed, as required.
    unsafe { sum(0i32, 2i32) };
}
```

Rules and guidance:

- The function must be `unsafe extern "C"` (or `"C-unwind"`) and the variadic parameter must be last and named (conventionally `args: ...`).
- `args.next_arg::<T>()` is `unsafe` and only sound if the caller actually passed a `T`; `VaArgSafe` rejects types with unstable C ABIs (e.g. non-`repr(C)` structs), not wrong argument counts — that contract stays on you. Document it in a `SAFETY:` comment as in the sample.
- 1.99 also stabilizes *naked* variadic functions (`#[unsafe(naked)]` + non-`"C"` ABIs); the body must be inline assembly.
- Prefer a typed Rust API (slice/iterator, `serde`, builder) over variadics in new code; use these only at a real C ABI boundary.

## Layout of Unsized Types from Raw Pointers

Three functions settle how to get size/alignment without a valid reference — previously only sound-looking for `Sized` types:

- `mem::size_of_val_raw(ptr) -> usize`
- `mem::align_of_val_raw(ptr) -> usize`
- `Layout::for_value_raw(ptr) -> Layout`

They read only the pointer's *metadata* (length/capacity part of fat pointers), so the pointee memory may be uninitialized, expired, or dangling:

```rust
use std::mem::size_of_val_raw;

fn element_count(slice: *const [u8]) -> usize {
    // SAFETY: only slice metadata is read; the pointee is not touched.
    unsafe { size_of_val_raw(slice) }
}
```

Safety contract: the pointer's *metadata* must be valid (e.g. a `*const [T]` whose length is meaningful). A reference is never required, which is the point — this is the sanctioned replacement for transmuting fat pointers or constructing fake references to query layout.

## `Box::leak`: No Round-Trip Unleaking

No language change, but `Box::leak` documentation now warns against deallocating the leaked reference later. Such round-trips interact badly with current and future optimizer assumptions and are especially problematic now that custom allocators are landing (1.100).

```rust
// WRONG: round-trip unleaking.
let leaked: &'static mut i32 = Box::leak(Box::new(42));
let boxed: Box<i32> = unsafe { Box::from_raw(leaked as *mut i32) }; // avoid

// RIGHT: keep ownership out of the borrow system instead.
let raw: *mut i32 = Box::into_raw(Box::new(42));            // or:
// let nn: NonNull<i32> = Box::into_non_null(Box::new(42)); // 1.99+
```

The same guidance applies to every other `leak` in std (`String::leak`, `OsString::leak`, …).

## Attribute Macros over Outlined Modules

`#[my_macro] mod foo;` is now stable — an outlined module (`mod foo;`, body in another file) may appear anywhere in the body of a custom attribute or derive macro:

```rust
#[derive(serde::Serialize)] // or any proc macro that emits items around the module
mod config;                  // expanded in place since 1.99; before: error
```

Before 1.99 the module had to be inline (`mod foo { ... }`) inside macro output. If a proc-macro crate you maintain emitted `mod foo;` errors, drop the workaround.

## Stabilized APIs

| API | Notes |
|---|---|
| `IntoIterator` for `Box<[T; N]>`, `&Box<[T; N]>`, `&mut Box<[T; N]>` | boxed arrays now iterate like arrays: `Box::new([1,2,3]).into_iter().sum::<i32>()` |
| `core::fmt::NumBuffer` re-exported in `alloc`/`std` | allocation-free integer formatting buffer (the `<int>::format_into` from 1.98) |

```rust
fn boxed_iter() -> i32 {
    let boxed: Box<[i32; 3]> = Box::new([1, 2, 3]);
    boxed.into_iter().sum() // 6 — moves out of the box, stable since 1.99
}
```

## Other Changes Worth Knowing

- **`UnsafeCell` guarantee**: contents may now be accessed without going through `get` (the `invalid_reference_casting` lint was adjusted accordingly).
- **`asm!` on x86**: 128-bit integers may be passed via vector registers.
- **`RangeInclusive` iteration** is optimized; exhausted ranges may report different `start()`/`end()` and slice-index differently — these behaviors were never guaranteed.
- **rustc suggestions** now prefer exact `#[doc(alias)]` names over fuzzy matches when suggesting a missing method.
- **`riscv64-unknown-linux-musl`** promoted to Tier 2 with host tools.
- **Compiler**: LLVM 23; `-Ctarget-cpu` is now a target-modifier for AVR/AMDGCN/NVPTX.

## Cargo

- **New built-in `debug` profile** (identical to `dev` for now). Groundwork for making `dev` lighter later; you can already write `[profile.debug]` sections. Docs: <https://doc.rust-lang.org/cargo/reference/profiles.html#debug-1>
- **Workspace `default-features` override** (RFC 3945): on edition 2024+ members can do `serde = { workspace = true, default-features = false }` and it *turns off* default features even when the workspace definition enables them. On older editions the field is ignored with a warning.

```toml
# workspace Cargo.toml
[workspace.dependencies]
serde = { version = "1", features = ["derive"] }  # derive enabled

# member Cargo.toml (edition 2024) — derive stays, default features now off
[dependencies]
serde = { workspace = true, default-features = false }
```

- **CI**: incremental compilation is now off by default when the `CI` env variable is set — remove any manual `CARGO_INCREMENTAL=0` workarounds.

## MSRV Notes

Code using the features in this skill needs `rust-version = "1.99"`. For code that must also build on older toolchains, gate the new APIs behind `cfg` or a feature flag rather than relying on them unconditionally. See the full [compatibility notes](references/compatibility.md) before upgrading a large codebase.
