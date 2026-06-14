---
name: rust-nightly
description: Rust nightly workflow — feature gates, unstable language/library/tooling features, obsolete APIs, experimental data types, and target-platform support.
---

# Rust Nightly

Use this skill when a Rust project uses `+nightly`, `#![feature(...)]`, unstable `std` APIs, `-Z` flags, custom targets, `build-std`, Miri, sanitizers, rustc internals, or experimental language syntax.

## Latest Checked Inventory

- Latest checked: Rust nightly docs `1.98.0-nightly (1f087276b 2026-06-13)`, checked `2026-06-14`.
- Primary sources:
  - Unstable Book: <https://doc.rust-lang.org/nightly/unstable-book/>
  - Nightly `std`: <https://doc.rust-lang.org/nightly/std/>
  - Cargo unstable features: <https://doc.rust-lang.org/nightly/cargo/reference/unstable.html>
  - rustc platform support: <https://doc.rust-lang.org/nightly/rustc/platform-support.html>
  - Rustup component history: <https://rust-lang.github.io/rustup-components-history/>
- Nightly APIs may change or disappear without semver compatibility. Always check the feature's tracking issue before depending on it.

## Nightly Adoption Rules

1. Prefer stable Rust unless the task explicitly needs a gated language feature, unstable library API, or nightly-only tool flag.
2. Pin the nightly date for any repository, benchmark, CI job, or reproducibility-sensitive experiment.
3. Keep all feature gates in one root crate-level block and annotate why each one is needed.
4. Use `-Z allow-features=...` in CI for crates that must not grow new nightly dependencies by accident.
5. Avoid `RUSTC_BOOTSTRAP`. It makes stable rustc behave like nightly and exists for compiler bootstrapping, not application builds.
6. Treat `#![allow(incomplete_features)]` as a risk marker. Use it only next to the incomplete gate that requires it and keep a tracking issue link in the comment.

## Toolchain Pinning

Use a dated nightly instead of floating `nightly` for real projects:

```toml
# rust-toolchain.toml
[toolchain]
channel = "nightly-2026-06-13"
profile = "minimal"
components = ["rustfmt", "clippy", "rust-src", "miri", "llvm-tools-preview"]
```

Common commands:

```bash
rustup toolchain install nightly-2026-06-13 --profile minimal \
  --component rustfmt,clippy,rust-src,miri,llvm-tools-preview

cargo +nightly-2026-06-13 fmt --check
cargo +nightly-2026-06-13 clippy --all-targets --all-features
cargo +nightly-2026-06-13 test --all-features
cargo +nightly-2026-06-13 miri test
```

For CI gate control:

```bash
RUSTFLAGS="-Zallow-features=f16,f128,portable_simd" \
  cargo +nightly-2026-06-13 check -Z build-std=std,panic_abort
```

## Language Feature Groups

| Area | Feature gates | Use when | Notes |
|---|---|---|---|
| New floats | `f16`, `f128` | Half/quad precision numeric work | Experimental primitive types; verify FFI, serialization, and target codegen. |
| Never type | `never_type` | Explicit `!` in generics such as `Result<T, !>` | 2024 edition changes never-type fallback toward `!`; test inference edge cases. |
| Const generics | `min_generic_const_args`, `generic_const_args`, `generic_const_exprs`, `adt_const_params`, `generic_const_items` | Type-level sizes and compile-time values | `generic_const_exprs` is incomplete; expect diagnostics and syntax churn. |
| Coroutines | `coroutines`, `coroutine_trait`, `stmt_expr_attributes` | Resumable functions with `yield` | Current spelling is coroutines; old posts may call this generators. |
| Error flow | `try_blocks`, `yeet_expr` | Scoped `?` blocks or experimental early-exit syntax | `yeet_expr` is intentionally placeholder syntax. |
| Trait/type abstraction | `trait_alias`, `type_alias_impl_trait`, `impl_trait_in_assoc_type`, `auto_traits`, `negative_impls` | Hide concrete types or express marker relationships | Be explicit in public API docs; object-safety and coherence can shift. |
| Struct ergonomics | `default_field_values`, `type_changing_struct_update`, `offset_of_enum`, `offset_of_slice` | Defaults, layout/reflection, struct update experiments | Do not promise layout stability unless using `repr(...)` and documenting invariants. |
| Pattern matching | `deref_patterns`, `box_patterns`, `half_open_range_patterns_in_slices`, `postfix_match`, `loop_match` | Matching smart pointers, slices, or expression-postfix style | `box_patterns` is superseded by `deref_patterns`. |
| FFI/ABI | `c_variadic`, `ffi_const`, `ffi_pure`, `explicit_extern_abis`, `transparent_unions`, `abi_vectorcall`, `abi_ptx`, `abi_msp430_interrupt`, `abi_cmse_nonsecure_call` | C/foreign ABI interop | Keep per-target ABI tests; unstable ABI gates are platform-sensitive. |
| Inline asm | `asm_experimental_arch`, `asm_experimental_reg`, `asm_goto_with_outputs`, `asm_unwind` | Low-level target-specific code | Gate by `cfg(target_arch)` and test generated assembly. |
| Conditional compilation | `cfg_version`, `cfg_sanitize`, `cfg_target_object_format`, `doc_cfg`, `doc_notable_trait` | Version/target/doc-aware APIs | Prefer stable `cfg` where enough; unstable cfg keys require nightly docs. |
| Compiler integration | `rustc_private`, `rustc_attrs`, `lang_items`, `intrinsics`, `compiler_builtins` | rustc/std/compiler-plugin work | Internal-only for most application crates. |

## Unstable Standard Library and Library Features

| Area | Feature gates / modules | What it provides | Guidance |
|---|---|---|---|
| Allocation | `allocator_api`, `std::alloc` | Per-collection custom allocators | Check current rustdoc; older docs may use obsolete `AllocRef` terminology. |
| Async traits | `async_fn_traits`, `fn_traits`, `unboxed_closures` | Implement closure-like and async closure-like traits | Prefer stable async traits/closures when possible; keep minimal examples compiling. |
| Async iteration | `async_iterator`, `async_iter_from_iter`, `std::async_iter` | `AsyncIterator`, `IntoAsyncIterator`; `from_iter` needs `async_iter_from_iter` | Poll-based API; adapters and `next` ergonomics may change. |
| Portable SIMD | `portable_simd`, `std::simd` | `Simd<T, N>`, `Mask`, vector aliases | Semantics are portable; performance and subnormal float behavior can vary on older archs. |
| Byte strings | `bstr`, `std::bstr` | `ByteStr`, `ByteString` | Human-readable bytes that are conventionally but not always UTF-8. |
| Random | `random`, `std::random` | `random()`, `RandomSource`, `Distribution` | Use external crates for stable production APIs until stabilized. |
| Autodiff | `autodiff`, `std::autodiff`, `-Zautodiff=Enable` | Forward/reverse automatic differentiation macros | Current limitations include `dyn Trait`, non-fat-LTO builds, and debug-mode fragility. |
| GPU offload | `gpu_offload`, `std::offload`, `-Zoffload=Enable` | `#[offload_kernel]` and kernel dispatch support | Experimental; current launch path uses intrinsics and has device-mapping restrictions. |
| Field reflection | `field_projections`, `std::field` | `Field`, `field_of!`, field representing types | Reflection model is new; do not expose as stable public API. |
| Unsafe binders | `unsafe_binders`, `std::unsafe_binder` | `wrap_binder!`, `unwrap_binder!` | Use only when modeling unsafe binding semantics intentionally. |
| Intrinsics | `core_intrinsics`, `std::intrinsics` | Compiler intrinsics | Prefer stable wrappers; intrinsics can be UB-prone and undocumented. |
| Bench/test internals | `test` | `extern crate test`, `#[bench]`, `Bencher` | Legacy unstable bench API; prefer `divan` or Criterion for app/library benchmarks. |
| Windows internals | `windows_c`, `windows_handle`, `windows_net`, `windows_stdio` | Windows-specific std internals | Avoid unless working inside std or platform support. |

## New and Experimental Data Types

| Type/module | Gate | Data shape | Use cases | Production cautions |
|---|---|---|---|---|
| `f16` / `std::f16` | `f16` | IEEE 754 binary16 primitive and constants | ML tensors, graphics formats, compact numeric storage | Check hardware support, ABI, serialization, and math precision. |
| `f128` / `std::f128` | `f128` | IEEE 754 binary128 primitive and constants | High-precision numeric experiments | Often slower/software-backed; avoid FFI assumptions. |
| `!` | `never_type` | Uninhabited primitive type | Infallible errors, diverging APIs, exhaustive generic matches | Explicit use still nightly; type fallback/inference can surprise older editions. |
| `std::range::{Range, RangeFrom, RangeFull, RangeInclusive, RangeTo, RangeToInclusive}` | `new_range` | Replacement range structs | Future edition range semantics and slicing experiments | Legacy `std::ops` range types remain the stable default. |
| `std::bstr::{ByteStr, ByteString}` | `bstr` | Borrowed/owned human-readable byte strings | File paths, logs, protocol text that may be non-UTF-8 | API is experimental; compare against `bstr` crate for stable needs. |
| `std::simd::{Simd<T, N>, Mask<_, N>}` | `portable_simd` | Lane vectors and masks | Portable vectorized numeric code | Measure on every target; scalar fallback is allowed. |
| `std::async_iter::{AsyncIterator, IntoAsyncIterator}` | `async_iterator`; `from_iter` also needs `async_iter_from_iter` | Poll-driven async streams | Standard-library async stream experiments | Runtime ecosystem still mostly uses `futures::Stream` / `tokio-stream`. |
| `std::random::{DefaultRandomSource, RandomSource, Distribution}` | `random` | Random source and distribution traits | Experiments with std-provided random generation | Prefer `rand` for stable API surface. |
| `std::field::{Field, FieldRepresentingType}` | `field_projections` | Type-level field representations | Reflection/projection experiments | High churn risk. |

## Cargo Nightly Features

| Feature | Enable with | Use when |
|---|---|---|
| Build std | `-Z build-std`, `-Z build-std-features` | Custom targets, sanitizers, panic strategy experiments, `no_std` + alloc/std builds. |
| Resolver testing | `-Z minimal-versions`, `-Z direct-minimal-versions`, `-Z msrv-policy`, `-Z precise-pre-release`, `-Z update-breaking` | Dependency lower-bound/MSRV and breaking-update checks. |
| SBOM | `-Z sbom` | Generate SBOM precursor files for compiled artifacts. |
| Artifact control | `--artifact-dir ... -Z unstable-options`, `-Z build-dir-new-layout`, `--root-dir ... -Z unstable-options` | Deterministic artifact collection and build output layout experiments. |
| Host/target config | `-Z host-config`, `-Z target-applies-to-host`, `-Z per-package-target` | Cross builds with different host/build-target behavior. |
| Rustdoc | `-Z rustdoc-map`, `-Z scrape-examples`, `-Z rustdoc-depinfo`, `--output-format json -Z unstable-options` | Docs.rs-style linking, example scraping, rustdoc JSON consumers. |
| Metadata | `-Z unit-graph`, `cargo rustc --print ... -Z unstable-options`, `-Z build-analysis` | Tooling that needs Cargo's internal graph or build metrics. |
| Cache/control | `-Z gc`, `-Z checksum-freshness`, `-Z fine-grain-locking`, `-Z no-index-update` | Build-cache experiments and offline/index behavior. |
| Single-file packages | `-Z script` | Cargo-managed single-file `.rs` scripts. |
| Manifest extensions | `cargo-features = [...]`; `[lints.cargo]` uses `-Zcargo-lints` | `codegen-backend`, `trim-paths`, `path-bases`, `unstable-editions`, artifact dependencies, Cargo lint configuration. |

## rustc Nightly Flags

Use `rustc +nightly -Z help` and `cargo +nightly rustc -- -Z help` for the current list.

| Flag family | Examples | Use when |
|---|---|---|
| Safety tools | `-Zsanitizer=address`, `hwaddress`, `leak`, `memory`, `thread`, `cfi`, `kcfi`, `dataflow`, `memtag`, `realtime`, `safestack`, `shadow-call-stack` | Fuzzing, CI hardening, undefined-behavior detection. |
| Feature containment | `-Zallow-features=f16,portable_simd` | Restrict allowed `#![feature]` gates in CI. |
| Codegen | `-Zcodegen-backend=...`, `-Zdylib-lto`, `-Zvirtual-function-elimination`, `-Zbranch-protection`, `-Zcf-protection`, `-Zcontrol-flow-guard` | Backend experiments, LTO, CFI/hardening, platform security features. |
| Layout/randomization | `-Zrandomize-layout`, `-Zprint-type-sizes`, `-Zemit-stack-sizes` | Find unsafe layout assumptions and stack pressure. |
| Diagnostics/profiling | `-Zself-profile`, `-Ztime-passes`, `-Zreport-time`, `-Zmacro-stats`, `-Ztrack-diagnostics` | Compiler performance and macro/debug diagnostics. |
| Autodiff/offload | `-Zautodiff=Enable`, `-Zoffload=...` | Experimental differentiation and GPU offload work. |
| Target/introspection | `-Zprint-supported-crate-types`, `-Zprint-check-cfg`, `-Zunstable-options` | Tooling and target capability discovery. |

## Obsolete, Superseded, or Internal-Only Items

| Item | Status | Use instead / rule |
|---|---|---|
| `box_patterns` | Superseded | Use `deref_patterns` for smart-pointer pattern matching experiments. |
| `try!` macro | Deprecated | Use `?`. |
| `std::{i8,i16,i32,i64,i128,isize,u8,u16,u32,u64,u128,usize}` constants modules | Deprecation planned | Use primitive associated constants, e.g. `i32::MAX`, `usize::BITS`. |
| `std::range::legacy` | Compatibility layer | Use stable `std::ops` ranges, or `std::range` only when explicitly testing `new_range`. |
| `extern crate test` / `#[bench]` | Unstable legacy benchmarking | Use `divan` or Criterion unless you need libtest compatibility. |
| `RUSTC_BOOTSTRAP=1` | Bootstrap escape hatch | Use `+nightly`; if absolutely required for rustc/std work, scope to `RUSTC_BOOTSTRAP=crate_name`. |
| `allocator_internals`, `compiler_builtins`, `libstd_sys_internals`, `fmt_internals`, `print_internals`, `str_internals`, `thread_local_internals`, `rt` | std/rustc implementation details | Do not use in ordinary crates. |
| `rustc_private` | Compiler-internal crates | Only for compiler tools; install `rustc-dev` and `llvm-tools-preview`, and expect viral linkage issues. |
| `core_intrinsics` / `intrinsics` | Unstable compiler intrinsics | Prefer safe/stable wrappers; write SAFETY comments and tests if unavoidable. |
| Old generator terminology | Renamed concept | Current docs use `coroutines`, `coroutine_trait`, and `#[coroutine]`. |

## Supported Platforms

Rust target support is tiered. Component availability for a given nightly can still vary; check rustup component history before assuming `rustfmt`, `clippy`, `miri`, `rust-src`, or std artifacts exist for a target.

### Tier 1 with host tools

Tier 1 targets are guaranteed to build and pass automated tests. Host-tools targets can run `rustc` and `cargo` natively and support full `std`.

- `aarch64-apple-darwin` — ARM64 macOS 11+.
- `aarch64-pc-windows-msvc` — ARM64 Windows MSVC.
- `aarch64-unknown-linux-gnu` — ARM64 Linux, kernel 4.1+, glibc 2.17+.
- `i686-pc-windows-msvc` — 32-bit Windows MSVC.
- `i686-unknown-linux-gnu` — 32-bit Linux, kernel 3.2+, glibc 2.17+.
- `x86_64-pc-windows-gnu` — 64-bit MinGW Windows.
- `x86_64-pc-windows-msvc` — 64-bit Windows MSVC.
- `x86_64-unknown-linux-gnu` — 64-bit Linux, kernel 3.2+, glibc 2.17+.

### Tier 2 with host tools

Tier 2 targets are guaranteed to build, but tests may not run on every change. These also build host tools:

`aarch64-pc-windows-gnullvm`, `aarch64-unknown-freebsd`, `aarch64-unknown-linux-musl`, `aarch64-unknown-linux-ohos`, `arm-unknown-linux-gnueabi`, `arm-unknown-linux-gnueabihf`, `armv7-unknown-linux-gnueabihf`, `armv7-unknown-linux-ohos`, `loongarch64-unknown-linux-gnu`, `loongarch64-unknown-linux-musl`, `i686-pc-windows-gnu`, `powerpc-unknown-linux-gnu`, `powerpc64-unknown-linux-gnu`, `powerpc64-unknown-linux-musl`, `powerpc64le-unknown-linux-gnu`, `powerpc64le-unknown-linux-musl`, `riscv64gc-unknown-linux-gnu`, `s390x-unknown-linux-gnu`, `x86_64-apple-darwin`, `x86_64-pc-windows-gnullvm`, `x86_64-unknown-freebsd`, `x86_64-unknown-illumos`, `x86_64-unknown-linux-musl`, `x86_64-unknown-linux-ohos`, `x86_64-unknown-netbsd`, `x86_64-pc-solaris`, `sparcv9-sun-solaris`.

### Tier 2 without host tools

These are build targets only. Common groups include Apple mobile/vision/watch targets, Android, Fuchsia, UEFI, bare-metal ARM/RISC-V/thumb targets, CUDA `nvptx64-nvidia-cuda`, WebAssembly (`wasm32-unknown-unknown`, `wasm32-wasip1`, `wasm32-wasip1-threads`, `wasm32-wasip2`, `wasm32v1-none`), Redox, SGX, and sanitizer Linux targets.

Full current Tier 2 no-host triples from the checked docs:

`aarch64-apple-ios`, `aarch64-apple-ios-macabi`, `aarch64-apple-ios-sim`, `aarch64-apple-tvos`, `aarch64-apple-tvos-sim`, `aarch64-apple-visionos`, `aarch64-apple-visionos-sim`, `aarch64-apple-watchos`, `aarch64-apple-watchos-sim`, `aarch64-linux-android`, `aarch64-unknown-fuchsia`, `aarch64-unknown-none`, `aarch64-unknown-none-softfloat`, `aarch64-unknown-uefi`, `arm-linux-androideabi`, `arm-unknown-linux-musleabi`, `arm-unknown-linux-musleabihf`, `arm64ec-pc-windows-msvc`, `armv5te-unknown-linux-gnueabi`, `armv5te-unknown-linux-musleabi`, `armv7-linux-androideabi`, `armv7-unknown-linux-gnueabi`, `armv7-unknown-linux-musleabi`, `armv7-unknown-linux-musleabihf`, `armv7a-none-eabi`, `armv7a-none-eabihf`, `armv7r-none-eabi`, `armv7r-none-eabihf`, `armv8r-none-eabihf`, `thumbv7a-none-eabi`, `thumbv7a-none-eabihf`, `thumbv7r-none-eabi`, `thumbv7r-none-eabihf`, `thumbv8r-none-eabihf`, `i586-unknown-linux-gnu`, `i586-unknown-linux-musl`, `i686-linux-android`, `i686-pc-windows-gnullvm`, `i686-unknown-freebsd`, `i686-unknown-linux-musl`, `i686-unknown-uefi`, `loongarch64-unknown-none`, `loongarch64-unknown-none-softfloat`, `nvptx64-nvidia-cuda`, `riscv32i-unknown-none-elf`, `riscv32im-unknown-none-elf`, `riscv32imac-unknown-none-elf`, `riscv32imafc-unknown-none-elf`, `riscv32imc-unknown-none-elf`, `riscv64a23-unknown-linux-gnu`, `riscv64gc-unknown-linux-musl`, `riscv64gc-unknown-none-elf`, `riscv64im-unknown-none-elf`, `riscv64imac-unknown-none-elf`, `sparc64-unknown-linux-gnu`, `s390x-unknown-none-softfloat`, `thumbv6m-none-eabi`, `thumbv7em-none-eabi`, `thumbv7em-none-eabihf`, `thumbv7m-none-eabi`, `thumbv7neon-linux-androideabi`, `thumbv7neon-unknown-linux-gnueabihf`, `thumbv8m.base-none-eabi`, `thumbv8m.main-none-eabi`, `thumbv8m.main-none-eabihf`, `wasm32-unknown-emscripten`, `wasm32-unknown-unknown`, `wasm32-wasip1`, `wasm32-wasip1-threads`, `wasm32-wasip2`, `wasm32v1-none`, `x86_64-apple-ios`, `x86_64-apple-ios-macabi`, `x86_64-fortanix-unknown-sgx`, `x86_64-linux-android`, `x86_64-unknown-linux-gnuasan`, `x86_64-unknown-linux-gnumsan`, `x86_64-unknown-linux-gnutsan`, `x86_64-unknown-fuchsia`, `x86_64-unknown-linux-gnux32`, `x86_64-unknown-none`, `x86_64-unknown-redox`, `x86_64-unknown-uefi`.

### Tier 3

Tier 3 targets are community-maintained and may not have official binaries, std builds, or CI coverage. Use custom target JSON plus `-Z build-std` when needed, and document linker, runner, and panic/allocator constraints in `.cargo/config.toml`.

## Verification Checklist

- Run `rustc +nightly --version --verbose` and record the exact date/commit in bug reports.
- Run `rustup component list --toolchain <nightly> --installed` before assuming components exist.
- Run stable and nightly jobs separately if the crate supports both.
- For `std::simd`, sanitizers, `f16`/`f128`, FFI, and custom targets, add target-specific tests or compile-only jobs.
- For public crates, document each nightly gate, tracking issue, fallback plan, and expected stabilization/removal path.
