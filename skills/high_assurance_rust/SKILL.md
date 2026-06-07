---
name: high_assurance_rust
description: Build secure, robust, justifiably-trustworthy Rust — the static/dynamic/operational assurance taxonomy, threat modeling (STRIDE, shift-left, risk = likelihood × severity), what Rust's memory safety does and does NOT prevent (spatial/temporal/type safety, the weird-machine model), disciplined unsafe (#![forbid(unsafe_code)], safe abstractions, soundness), robustness/high-availability (fallible APIs, OOM via try_reserve, no-panic), portability (no_std/heapless, freestanding binaries), supply-chain hardening (cargo-audit/RustSec, reproducible builds, Cargo.lock, rust-toolchain.toml, pinned git deps), the recommended toolchain (clippy lint groups, rustfmt, rustdoc doc-tests, cargo-modules/binutils), differential fuzzing, and formal methods (model checking, deductive verification). Use when assurance, security, robustness, safety-critical, or verification matter — not just "does it compile".
---

# High Assurance Rust

Practices from *High Assurance Rust* (Tiemoko Ndogga) for software you can **justifiably trust** — enough evidence to back confidence in functionality *and* security. Goal: minimize vulnerabilities and make attacks impractical, not "impossible". Complements `rust-conventions`, `rust-testing`, `power-rust`; this skill is about the *assurance* layer above "it compiles".

## Core framing

- **Bug vs. vulnerability** — a vulnerability is a bug an attacker can exploit. "Can't log in with valid creds" is a bug; "can log in with *invalid* creds" is a vulnerability. Assurance targets both robustness (no bugs) and security (no exploitable bugs).
- **Assurance = level of confidence**, built by layering tools/processes. Three categories, applied together:
  - **Static** — checks on code *without running it* (compiler, types, lints, model checking).
  - **Dynamic** — checks by *running* it (tests, fuzzing, sanitizers, benchmarks).
  - **Operational** — measures while it runs in *production* (hardening, isolation, monitoring).
- **No single tool finds all bugs.** Map work onto the static/dynamic × known/unknown quadrant: signature scanners (e.g. `cargo-audit`) catch *known* bugs; fuzzing/verification probe *unknown* ones. Verification can prove the *absence of a class* of bugs (no false negatives for that class) but the class is limited. Combine techniques; assume residual risk.
- **Lean lightweight.** Prefer fast, repeatable techniques that ship quality code faster over heavyweight process. Bias toward development speed, escalate rigor where the threat justifies it.

## Threat modeling (do this first, shift-left)

Cheapest to fix issues before code exists. Workflow:
1. **Identify assets** — data/resources worth protecting.
2. **Enumerate threats** per asset's attack surface — start from sources of *untrusted input*.
3. **Rank** — `risk = likelihood × severity`.
4. **Mitigate** — controls proportional to ranked risk.
5. **Test** the mitigations' efficacy.

Use **STRIDE** as the threat taxonomy: **S**poofing (auth), **T**ampering (integrity), **R**epudiation (non-repudiation), **I**nformation disclosure (confidentiality), **D**enial of service (availability), **E**levation of privilege (authorization). Drive every security decision from the realities of the *production* environment (cloud, client device, embedded ECU…).

## What Rust's safety does — and doesn't — give you

Rust's compiler **proves the absence of memory-corruption bugs** (use-after-free, buffer overflow, data races) for safe code, at bare-metal speed. Know the boundaries:

- **Spatial safety** (in-bounds access), **temporal safety** (no use-after-free/double-free), and **type safety** are enforced for safe code — the exploitation primitives that break "code-data isolation" (the *weird machine* model) are removed.
- Rust does **not** prevent: logic bugs, auth/authorization flaws, integer-overflow *semantics* (wraps in release unless you opt into checks/`checked_*`), resource exhaustion/DoS, supply-chain compromise, side channels, or unsoundness introduced via `unsafe`/FFI.
- So safe Rust shrinks the memory-safety attack surface dramatically — then threat-model and test the *rest*.

## Disciplined `unsafe`

- Default to **`#![forbid(unsafe_code)]`** at the crate root. It turns any `unsafe` into a compile error; building a third-party `#![forbid(unsafe_code)]` dependency from source lets the compiler *verify* the claim.
- When `unsafe` is unavoidable, **encapsulate it in a small, sound safe abstraction** that upholds every invariant the compiler can no longer check. Each `unsafe` block gets a `// SAFETY:` comment stating the invariant relied on (see `power-rust`).
- **Unsafety ≠ unsoundness:** `unsafe` is fine if the surrounding safe API can never trigger UB for *any* input. Unsoundness = a safe caller can cause UB. Audit `unsafe` for soundness, keep it minimal and isolated in dedicated modules; model-check it where stakes are high.

## Robustness & high availability

For software that "must survive" (no patches, no failures):

- **Fallible APIs** — return `Result` instead of panicking on recoverable conditions; reserve `panic!` for truly unreachable contract violations. Prefer `TryFrom`/`TryInto` for fallible conversions, `From`/`Into` for infallible.
- **Handle OOM** — in memory-constrained / long-running systems use **fallible allocation**: `Vec::try_reserve`/`try_reserve_exact` and `HashMap::try_reserve` (stable) surface allocation failure as `Result` instead of aborting; for fallible `Box`/custom-allocator paths use the still-unstable `allocator_api`. Prefer pre-sized + `try_reserve` over infallible `push`/`extend` in hot allocation paths.
- **No-panic posture** — audit for hidden panics (indexing, `unwrap`, integer division, slicing); prefer `get()`, `checked_*`, explicit bounds. Validate all untrusted input at the boundary, fail fast with a typed error.
- **Catch integer overflow in release** — overflow panics in debug but silently wraps in release by default. For high-assurance builds set `overflow-checks = true` under `[profile.release]` (small runtime cost) and/or use `checked_*`/`saturating_*`/`Wrapping` explicitly where wrapping is intended.
- **Encode invariants in types** — newtypes with validating constructors, `NonZero*`, typestate — so invalid states are unrepresentable rather than runtime-checked (see `design-patterns-rust`).

## Portability (no_std, embedded, freestanding)

- **`#![no_std]`** drops the standard library so code runs on bare metal / any OS; use `core` + (optionally) `alloc`. Pair with `heapless` for fixed-capacity, allocation-free collections when there's no allocator.
- **Freestanding binary** — for hardened deployment, strip the runtime, **strip debug symbols** (`strip = "symbols"` / `cargo-binutils`), and minimize the trusted surface.
- **CFFI** — expose a hardened Rust component to other languages via `extern "C"` + `#[no_mangle]` (callable from C/Python). The FFI boundary is `unsafe` by nature — validate at the edge and keep the unsafe surface tiny.

## Supply-chain hardening

- **`cargo-audit`** — scan the whole dependency graph (direct + transitive) against the **RustSec Advisory Database** for known-vulnerable / unmaintained crates. Run in CI; fail on advisories.
- **Reproducible builds** — commit **`Cargo.lock`** for anything that builds an executable so everyone builds identical dependency versions; add **`rust-toolchain.toml`** to pin the compiler version and target. `cargo update` deliberately, then `cargo test`.
- **Pin/self-host critical deps** — git dependencies can lock to a `rev` (commit hash) and live in a private/self-hosted repo: `clap = { git = "…", rev = "31bd0b5" }`. Keep a known-good internal version while you vet upstream.
- **Minimize and vet** the dependency graph — fewer, well-trusted deps; ban duplicate versions of security-critical crates (e.g. allowlist crypto publishers). Consider `cargo-vet`/`cargo-deny` to enforce policy.

## Recommended toolchain

| Tool | Role |
|------|------|
| `rustc` + types | the primary static prover — make the compiler do the work |
| **clippy** | 500+ lints. The default `clippy::all` group bundles `correctness` (**deny**) + `suspicious`/`style`/`complexity`/`perf` (warn). The high-assurance opt-in groups are `clippy::pedantic`, `clippy::nursery`, and `clippy::cargo` (all allow-by-default). Run `cargo clippy` in CI with `-D warnings`. |
| **rustfmt** | consistent formatting → smaller diffs, easier review |
| **rustdoc** | `///` docs render to a site **and run as tests** (`cargo test --doc`) — keeps examples correct. Use `//!` for crate docs. |
| `cargo-modules` | text render of module architecture for review |
| `cargo-audit` | dependency vulnerability scan (above) |
| `cargo-binutils` | inspect/strip binaries (`size`, `nm`, `objdump`, `strip`) |

## Dynamic assurance — testing & fuzzing

- **Unit + integration + doc tests** are the baseline; fallible and incomplete but high-value (see `rust-testing`). Test with officially-released **test vectors** where they exist (e.g. crypto).
- **Property-based testing** (`proptest`/`quickcheck`) — assert invariants over generated inputs, not hand-picked cases.
- **Differential fuzzing** — run your implementation and a trusted reference (e.g. std collection) on the same fuzzer-generated inputs and assert identical behavior; surfaces divergences pure unit tests miss. Use `cargo-fuzz` (libFuzzer) or `afl.rs`.
- **Sanitizers / `Miri`** — run tests under `Miri` to catch UB in `unsafe` Rust. Note `Miri` **cannot execute FFI / `extern` calls** — for FFI-heavy code pivot to `cargo-careful` or build with ASan/TSan (`-Zsanitizer`, nightly).
- **Lesson:** dynamic testing can *miss* intentional backdoors (the book demos an RC4 backdoor passing tests). Dynamic ≠ sufficient — pair it with manual static review and verification for trust-critical code.

## Formal methods (escalate for trust-critical code)

- **Model checking** — `kani` (bounded model checker) exhaustively verifies harnessed properties over all inputs within bounds, including `unsafe` code. Good cost/rigor trade-off for critical functions.
- **Deductive verification / refinement types** — heavier tools that prove functional-correctness contracts: `creusot` and `verus` for functional correctness, `flux` for refinement types. (Prefer these over the largely-unmaintained `prusti`.) Reserve for the highest-assurance kernels.
- Treat these as the top of the rigor ladder: most value comes from compiler + lints + tests + fuzzing; reach for proofs where a defect is unacceptable.

## Quick checklist

- [ ] Threat model written; assets, untrusted inputs, STRIDE threats ranked by `likelihood × severity`
- [ ] `#![forbid(unsafe_code)]` (or every `unsafe` isolated, `// SAFETY:`-documented, sound, Miri-checked)
- [ ] `cargo clippy -D warnings`, `cargo fmt --check`, `cargo test` (incl. `--doc`) green in CI
- [ ] `cargo-audit` clean; `Cargo.lock` + `rust-toolchain.toml` committed; deps minimized/pinned
- [ ] Boundaries validated; fallible APIs (`Result`/`try_reserve`) over panics; invariants encoded in types
- [ ] Fuzz/property tests for parsers & untrusted-input paths; model-check trust-critical functions

## Cross-references

- Testing mechanics → `rust-testing` · General style → `rust-conventions` · LLM-bug reduction → `power-rust`
- Types/invariants → `design-patterns-rust` · Errors → `anyhow-rust`, `eyre-rust` · Binary hardening/size → `high_performance_rust`
