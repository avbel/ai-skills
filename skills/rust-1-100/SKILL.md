---
name: rust-1-100
description: Rust 1.100.0 (2026-11-12) new features — never type `!` stable, `Infallible` as alias of `!`, stable Allocator API for Vec/Box, mem::DropGuard, mem::conjure_zst, extern "custom", Cargo dependency cooldowns (min-publish-age) and cargo lints. Use when upgrading to Rust 1.100, writing Result<T, !>, custom allocators, transactional rollback guards, or configuring Cargo supply-chain cooldowns.
---

# Rust 1.100 — New Features

Rust 1.100.0 was released on **2026-11-12** (branched from master 2026-09-25). Use this skill when a project targets Rust ≥ 1.100 or uses its new APIs. For the previous release see the [`rust-1-99`](../rust-1-99/SKILL.md) skill (C-variadic definitions, raw-pointer layout, `Box<[T; N]>` iteration). For the full compatibility notes see [references/compatibility.md](references/compatibility.md).

- Announcement: <https://blog.rust-lang.org/2026/11/12/Rust-1.100.0/>
- Detailed changelog: <https://releases.rs/docs/1.100.0/>
- Nightly-gated items that graduated in this release: see the `rust-nightly` skill (`never_type`, `allocator_api` are no longer nightly).

## Never Type `!` Is Stable

After 10 years, the never type `!` — the canonical uninhabited type of diverging computations — is fully stable. `return`, `break`, `continue`, and `std::process::exit` have type `!`, which coerces to any type. What's new in 1.100 is **naming `!` anywhere**, not just as a return type:

```rust
// `Result<T, !>` could not be written before 1.100.
fn infallible_unwrap<T>(res: Result<T, !>) -> T {
    let Ok(v) = res; // the None-equivalent arm is statically impossible
    v
}
```

`Infallible` is now a **type alias for `!`**, so old `Result<T, Infallible>` APIs and new `Result<T, !>` code interoperate freely. Use `!` in new APIs; keep `Infallible` only where old rustc must compile the code (it is a plain alias now, not a separate compatibility shim).

Guidance:

- Model truly-unreachable error states as `Result<T, !>` (or `io::Result` style enums with an uninhabited error variant) instead of `unwrap()`-documented "can't happen" invariants — the type system then proves it.
- `!` coerces to any type in `match`/`if` arms, which is what makes diverging arms (`None => return`) type-check; this was observable before 1.100 and is unchanged.
- **Do not** use `!` as a "placeholder" generic argument in macros expecting a type; it is genuinely uninhabited and code paths "returning" it are unreachable.

```rust
fn mrrrow(option: Option<u32>) {
    let value = match option {
        Some(x) => x,
        // `return` has type `!`, coerced to u32 — long-standing behavior.
        None => return,
    };
    let _ = value;
}
```

**Fallback change (all editions)**: never-type fallback changed from `()` to `!` in editions 2015/2018/2021 (edition 2024 already did this). Rare breakage: ignoring the result of a function returning a generic parameter, or code relying on `()` fallback inference. If a dependency fails to build, update it first — fixes for known breakage were published in advance.

## Stable `Allocator` API (core of `allocator_api`)

The core `Allocator` trait is stable, enabling custom allocators for std types — currently `Vec` and `Box` (more is planned under the [Allocators 1.0 project goal](https://goals.rust-lang.org/2026/allocators-1.0.html)).

```rust
use std::alloc::{AllocError, Allocator, Global, Layout};
use std::ptr::NonNull;

/// Example only: forwards to `Global`, logging allocations.
struct LoggingAlloc;

unsafe impl Allocator for LoggingAlloc {
    fn allocate(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
        let block = Global.allocate(layout)?;
        eprintln!("alloc {} bytes at {:?}", layout.size(), block);
        Ok(block)
    }

    unsafe fn deallocate(&self, ptr: NonNull<u8>, layout: Layout) {
        // SAFETY: `ptr` was produced by an equivalent allocator (Global).
        unsafe { Global.deallocate(ptr, layout) }
    }
}

fn main() {
    let mut v: Vec<u32, LoggingAlloc> = Vec::new_in(LoggingAlloc);
    v.extend([1, 2, 3]);
}
```

Rules and guidance:

- Required methods: `allocate` and `deallocate`. Provided (overridable): `allocate_zeroed`, `grow`, `grow_zeroed`, `shrink`.
- Unlike `GlobalAlloc`, `Allocator` **must support zero-sized allocations** and returns `Result<NonNull<[u8]>, AllocError>` instead of null pointers — wrap `libc::malloc`-style backends so `0`-size requests return a valid dangling non-null.
- Equivalence matters: an allocator moved/cloned, or referenced via `&A`/`&mut A`/`Box<A>`/`Rc<A>`/`Arc<A>` (blanket impls stabilized in 1.100), is *equivalent* to the original and may deallocate its blocks. Design custom allocators as ZSTs, references, or smart pointers; an immovable `MyAlloc([u8; N])` by value cannot be made sound.
- Construct with the `*_in` constructors (`Vec::new_in`, `Vec::with_capacity_in`, `Box::new_in`); the constructor surface is still growing — check current rustdoc before using less common entry points.
- If your type needs a global allocator (not per-collection), keep using `GlobalAlloc` + `#[global_allocator]`; `Allocator` is for per-collection control.

## `mem::DropGuard` — Closure on Every Exit Path

`DropGuard::new(value, f)` wraps a value; the guard derefs (and deref-muts) to it, and runs `f(value)` when dropped — on every exit path: `return`, `?`, panic. `DropGuard::dismiss(guard)` (an associated function, deliberately not a method, to avoid colliding with inner-type methods) consumes the guard and returns the value without running the closure.

```rust
use std::mem::DropGuard;

// Simple inline destructor:
{
    let s = String::from("Chashu likes tuna");
    let mut s = DropGuard::new(s, |s| println!("{s}")); // prints when scope exits
    s.push_str("!!!");                                  // DerefMut passthrough
}

// All-or-nothing rollback — the pattern DropGuard was designed for:
use std::num::ParseIntError;

/// Parse all `strings` into `nums`; on any failure `nums` is unchanged.
fn parse_all(nums: &mut Vec<u32>, strings: &[&str]) -> Result<(), ParseIntError> {
    let len = nums.len();
    let mut nums = DropGuard::new(nums, move |nums| {
        nums.truncate(len); // rollback runs on `?` early-exit and panics
    });

    for s in strings {
        nums.push(s.parse()?);
    }

    DropGuard::dismiss(nums); // success — cancel the rollback
    Ok(())
}
```

Use it instead of a one-off `struct` + `impl Drop` for transactional/rollback and "run on scope exit" logic. Prefer `dismiss` over `mem::forget`: it returns the wrapped value and drops the closure's captured state instead of leaking it.

## `mem::conjure_zst` — Sanctioned ZST Construction

```rust
// pub const unsafe fn conjure_zst<T>() -> T
unsafe fn make_unit() -> () {
    // SAFETY: `()` is an inhabited zero-sized type.
    unsafe { std::mem::conjure_zst::<()>() }
}
```

`conjure_zst` creates a value of an inhabited zero-sized `T` without a bound like `Default`. Prefer it over `transmute(())`, `MaybeUninit::uninit().assume_init()`, and similar incantations. It **panics if `T` is not zero-sized** and is **unsound for uninhabited types** (`!`, zero-variant enums) or types whose safety invariants gate construction (e.g. zero-sized capability tokens like PyO3's `Python<'py>`, which proves GIL possession by being unconstructible). If you are unsure `T` is an inhabited ZST, use `MaybeUninit` instead.

## `extern "custom"`

Functions may now be declared with `extern "custom"` — an ABI rustc does not define, resolved by other tooling (used by compiler-builtins and custom backends). It exists so such functions can be *named and typechecked*; calling conventions are supplied externally:

```rust
extern "custom" {
    fn some_intrinsics_fn(x: u32) -> u32;
}
```

Application code rarely needs this; treat it as an FFI escape hatch for tool authors.

## Stabilized API Impls

| Impls | Effect |
|---|---|
| `Allocator` for `&A`, `&mut A`, `Box<T, A>`, `Arc<T, A>`, `Rc<T, A>` | share a custom allocator across collections without unsafe |
| `PartialEq<Cow<'_, [U]>>` for `Vec<T, A>`, `&[T]`, `&mut [T]` | `vec == cow` and `slice == cow` comparisons compile now |

Also: `Iterator::{min,max}(_by_key)` switched which `Ord` methods they call — no behavior change for correct `Ord` impls, potentially different results for inconsistent ones. `-Cprofile-sample-use` (sample-profile PGO) is now stable. `wasm32-wasip3` is Tier 2.

## Cargo

### Dependency cooldowns (`min-publish-age`)

Supply-chain hardening: the resolver skips versions published more recently than the configured age — malicious versions are usually caught within hours/days.

```toml
# .cargo/config.toml
[registry]
global-min-publish-age = "3 days"
```

```console
$ cargo update
     Locking 2 packages to highest compatible version as of min-publish-age
      Adding clap 4.6.7 (available: 4.6.9, published 2 days ago)

# opt out for a single update:
$ CARGO_RESOLVER_INCOMPATIBLE_PUBLISH_AGE=allow cargo update clap --precise 4.6.9
```

Caveats: registry must record publish times (versions without `pubtime` are never held back); `cargo install` ignores the setting — pin with `cargo install foo@1.2.3`; this complements but does not replace dependency review. Once a newer version lands in `Cargo.lock`, later `cargo update` re-resolutions keep it.

### Cargo lints (`[lints.cargo]`) + unused-dependency warnings

Cargo's own lint system is stable. `cargo::unused_dependencies` is on by default (`warn`):

```toml
[lints.cargo]
unused_dependencies = "warn"   # or "allow" to silence
```

Limitations: the warning only appears when building *every* target that could use the dependency (`cargo check --bin foo` won't report unused `[dependencies]`); unused `dev-dependencies` are never reported.

### Build-dir layout & install

- The build directory now consistently applies build-configuration hashes (organized by build step). Tools hardcoding `target/debug/...` intermediate paths must switch to [Cargo JSON messages](https://doc.rust-lang.org/stable/cargo/reference/external-tools.html#json-messages). Old workarounds for missing hashes may be removable — see [cargo#17287](https://github.com/rust-lang/cargo/issues/17287).
- `cargo install` now uses the lockfile shipped inside the `.crate` tarball by default; `--locked` became a no-op.

## Migration Checklist

Before upgrading a real codebase, see [references/compatibility.md](references/compatibility.md). Highlights:

- Never-type fallback changed on pre-2024 editions — rare inference breakage; update broken dependencies before patching them yourself.
- **`box` patterns are no longer syntactically allowed** — `box x` in patterns was long-deprecated; migrate to `deref_patterns` (nightly) or explicit matching.
- `Infallible` is now a type alias to `!` — code treating it as its own enum type (e.g. exhaustive matches on `Infallible` variants) no longer compiles.
- Std now uses **Unicode 18.0.0**.

## MSRV Notes

Code using these features needs `rust-version = "1.100"`. On the never type specifically: `-> !` return types worked before, so only *generic* `!` usage (`Result<T, !>`, `impl Trait` over `!`) actually requires 1.100.
