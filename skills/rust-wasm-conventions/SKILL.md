---
name: rust-wasm-conventions
description: Rust WebAssembly conventions for wasm-bindgen, wasm-pack, wasm32-unknown-unknown targets, JS interop, memory, debugging, tests, performance, binary size, and panic strategy. Use only when a Rust project uses wasm-bindgen, wasm-pack, or targets WebAssembly.
---

# Rust WebAssembly Conventions

Apply these conventions only when the project uses `wasm-bindgen`, `wasm-pack`, or targets `wasm32-unknown-unknown`. These rules are written for any coding agent, including Claude Code, Codex, Cursor, and Copilot.

## Project Setup

- Use `wasm-pack` for building, testing, and packaging.
- Build with `wasm-pack build`.
- Set the crate type to `cdylib` in `Cargo.toml`: `crate-type = ["cdylib"]`.
- Use `wasm-bindgen` as the primary bridge between Rust and JavaScript.

## `#[wasm_bindgen]`

- Annotate exported `pub struct`, `pub enum`, and `impl` blocks with `#[wasm_bindgen]`.
- Use `#[repr(u8)]` on enums exposed to JavaScript when compact single-byte representation is useful.
- Expose constructors as `pub fn new() -> Self` inside a `#[wasm_bindgen]` impl block.
- Keep functions intended only for Rust-side tests in impl blocks without `#[wasm_bindgen]`.

## JavaScript Interop and Memory

- Minimize copying across the wasm/JavaScript boundary.
- Keep large data structures in wasm linear memory and expose pointers for JavaScript to read when appropriate.
- Prefer small copyable return values such as `u32`, `f64`, and `bool` over `String` or complex objects in hot paths.
- Import JavaScript functions with `#[wasm_bindgen] extern` blocks.
- Import `memory` from the generated `_bg` module for direct memory access when needed.

## Debugging

- Initialize `console_error_panic_hook` early for readable panic messages in browser consoles.
- Use a `log!` macro wrapping `web_sys::console::log_1` for `println!`-style browser debugging.
- Enable the `console` feature on `web-sys` when using console APIs.
- Use browser `debugger;` statements in JavaScript render loops when stepping through state changes.

## Testing

- Run wasm tests with `wasm-pack test --chrome --headless`, or the appropriate browser/runtime flag.
- Use `#[wasm_bindgen_test]` instead of `#[test]` for wasm-targeted tests.
- Structure tests with helper builders for known input states and expected output states.

## Performance

- Profile before optimizing; bottlenecks are often in JavaScript interop rather than Rust logic.
- Batch expensive JavaScript API calls.
- Avoid division and modulo in hot loops when simpler branch or bitwise alternatives are clearer and measured faster.
- Wrap `console.time` and `console.timeEnd` in an RAII helper for scope-based profiling when useful.
- Use native benchmarks for wasm-targeted core logic when possible.

## Binary Size

- In release profiles, consider `lto = true` and `opt-level = 's'`.
- Post-process with `wasm-opt -Os` or another measured optimization level.
- Use `twiggy` to inspect which functions consume binary size.
- Use `wasm-snip` with `wasm-opt --dce` to remove unreachable code when appropriate.
- Avoid `format!`, `to_string`, and string formatting in release hot paths.
- Consider a smaller allocator only when binary size is a proven priority.

## Panics

- In release builds, consider `panic = "abort"` to reduce binary size.
- Replace `unwrap()` and `expect()` with explicit error handling in production wasm paths unless abort-on-panic is intentional.

