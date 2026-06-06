---
name: node-rust-addon
description: Use when building Rust-backed Node.js native modules with napi-rs, Neon, node-ffi-rs/ffi-rs, node:ffi, WebAssembly, async Rust, async Node.js, packaging, or performance tuning.
---

# Node Rust Addons

Use this skill when a project needs a Node.js module backed by Rust code, or when comparing Node-API, FFI, and WASM approaches.

## 2026 Source Baseline

- Node.js 26.3 docs: Node-API remains the recommended stable addon ABI; `node:ffi` exists in Node 26.1+ but is experimental, gated by `--experimental-ffi`, and unsafe.
- Node-API docs: use Node-API for ABI-stable native addons; use simple async work or ThreadSafeFunction when native work must complete off the main JS thread.
- napi-rs docs: current `napi` 3.x supports Rust Node-API modules, generated TypeScript, `AsyncTask`, `ThreadsafeFunction`, and a `tokio_rt` feature for returning JS Promises from Tokio futures.
- Neon docs: current `neon` 1.1.x provides safe Rust bindings for Node addons, `npm init neon`, module exports, `Channel`, and optional futures/Tokio integration.
- node-ffi-rs / `ffi-rs`: Rust + N-API implementation of runtime FFI for calling C/C++/Rust dynamic libraries from JS. It supports primitive types, arrays, structs, pointers, callbacks, platform prebuilds, and running FFI work in a new thread. Treat pointer and lifetime handling as unsafe boundary code.
- node-addon-api: C++ wrapper over Node-API. Use it for C/C++ addons or when a library already has C++ binding expertise, not as the first choice for Rust.

Primary references:

- https://nodejs.org/api/n-api.html
- https://nodejs.org/api/ffi.html
- https://nodejs.org/api/worker_threads.html
- https://docs.rs/napi/latest/napi/
- https://napi-rs.github.io/napi-rs/cli/
- https://neon-rs.dev/docs/introduction/
- https://docs.neon-bindings.com/neon/event/struct.channel
- https://github.com/zhangyuang/node-ffi-rs

## Choose The Boundary

Default to `napi-rs` for new Rust-authored Node packages. It gives the best mix of Rust ergonomics, Node-API ABI stability, TypeScript output, async Promise support, and npm prebuild workflows.

| Task | Best tool | Why | Avoid when |
|---|---|---|---|
| New Rust implementation exposed as npm package | `napi-rs` | Rust-first, Node-API stable ABI, TS types, async support, strong packaging story | You need a custom Neon-style API or existing Neon code |
| Rust addon with ergonomic JS object/class API | `Neon` | Mature Rust wrapper, safe handles, `Channel` for main-thread callbacks | You need napi-rs prebuild automation or lowest boilerplate |
| Call an existing C ABI dynamic library from Node | `ffi-rs` / node-ffi-rs | No addon source needed; load symbols at runtime | Function is hot, signatures are complex, or memory ownership is hard |
| Try native FFI on Node 26 only | `node:ffi` | Built into Node 26.1+ builds with FFI support | Production, LTS targets, permission model, or crash-sensitive code |
| Existing C++ addon or C++ team | `node-addon-api` | Official C++ wrapper over Node-API | New Rust code; it adds a C++ layer you do not need |
| Browser + Node portability | Rust WASM via `wasm-bindgen` / napi-rs WASM | No native install step; works outside Node native addon environments | Needs OS APIs, threads, sockets, native libraries, or very low call overhead |
| CPU parallelism inside JS only | `node:worker_threads` | No native build; works with pure JS/TS | Rust libraries already provide the core speedup |

## Project Shape

For npm packages, ship a JS wrapper plus per-platform native binaries.

```json
{
  "type": "module",
  "main": "index.js",
  "types": "index.d.ts",
  "scripts": {
    "build": "napi build --release --platform",
    "build:debug": "napi build"
  },
  "devDependencies": {
    "@napi-rs/cli": "^3.6.0"
  },
  "napi": {
    "name": "my_native",
    "triples": {
      "defaults": true,
      "addition": ["aarch64-unknown-linux-gnu", "x86_64-unknown-linux-musl"]
    }
  }
}
```

```toml
[lib]
crate-type = ["cdylib"]

[dependencies]
napi = { version = "3", features = ["napi8", "tokio_rt", "serde-json"] }
napi-derive = "3"
tokio = { version = "1", features = ["fs", "rt-multi-thread", "time"] }
```

## napi-rs Examples

Use sync exports for cheap deterministic work. The call still runs on the JS thread, so it must be short.

```rust
use napi::bindgen_prelude::*;
use napi_derive::napi;

#[napi]
pub fn sum_u64(values: Vec<u64>) -> u64 {
    values.into_iter().sum()
}
```

Use Rust async for real async I/O and return a JS `Promise`.

```rust
use napi::bindgen_prelude::*;
use napi_derive::napi;

#[napi]
pub async fn read_file_async(path: String) -> Result<Buffer> {
    let bytes = tokio::fs::read(path)
        .await
        .map_err(|error| Error::new(Status::GenericFailure, format!("read failed: {error}")))?;

    Ok(bytes.into())
}
```

Use `AsyncTask` for CPU-heavy or blocking work. This uses libuv async work instead of blocking the JS event loop.

```rust
use napi::{bindgen_prelude::*, Task};
use napi_derive::napi;

struct HashTask {
    input: Buffer,
}

impl Task for HashTask {
    type Output = Vec<u8>;
    type JsValue = Buffer;

    fn compute(&mut self) -> Result<Self::Output> {
        Ok(blake3::hash(&self.input).as_bytes().to_vec())
    }

    fn resolve(&mut self, _env: Env, output: Self::Output) -> Result<Self::JsValue> {
        Ok(output.into())
    }
}

#[napi]
pub fn hash_async(input: Buffer) -> AsyncTask<HashTask> {
    AsyncTask::new(HashTask { input })
}
```

JS callers should treat async native exports like any other Promise-returning API.

```js
import { hashAsync, readFileAsync, sumU64 } from './index.js';

const total = sumU64([1n, 2n, 3n]);
const bytes = await readFileAsync(new URL('./package.json', import.meta.url).pathname);
const digest = await hashAsync(bytes);
```

## smol Pattern

napi-rs integrates most directly with Tokio. Use smol when the Rust library already standardizes on smol, or when the addon is a thin wrapper around a smol-based library. Keep smol behind a blocking worker, or own a small executor explicitly.

```rust
use napi::{bindgen_prelude::*, Task};
use napi_derive::napi;

struct SmolRead {
    path: String,
}

impl Task for SmolRead {
    type Output = Vec<u8>;
    type JsValue = Buffer;

    fn compute(&mut self) -> Result<Self::Output> {
        smol::block_on(async {
            smol::fs::read(&self.path)
                .await
                .map_err(|error| Error::new(Status::GenericFailure, format!("read failed: {error}")))
        })
    }

    fn resolve(&mut self, _env: Env, output: Self::Output) -> Result<Self::JsValue> {
        Ok(output.into())
    }
}

#[napi]
pub fn smol_read_async(path: String) -> AsyncTask<SmolRead> {
    AsyncTask::new(SmolRead { path })
}
```

Do not call `smol::block_on` or `tokio::runtime::Runtime::block_on` on the JS main thread for slow work. Put it behind `AsyncTask`, a dedicated Rust thread, or a long-lived runtime that returns a Promise.

## node-ffi-rs / ffi-rs

Use `ffi-rs` when you have an existing dynamic library with a stable C ABI and do not want to write a custom addon. Export Rust functions with `extern "C"` and C-compatible types.

```rust
#[unsafe(no_mangle)]
pub extern "C" fn sum_i32(a: i32, b: i32) -> i32 {
    a + b
}
```

```js
import { DataType, close, load, open } from 'ffi-rs';

open({
  library: 'libmath',
  path: process.platform === 'win32' ? './math.dll' : './libmath.so',
});

const result = load({
  library: 'libmath',
  funcName: 'sum_i32',
  retType: DataType.I32,
  paramsType: [DataType.I32, DataType.I32],
  paramsValue: [20, 22],
});

close('libmath');
```

Rules:

- Prefer `ffi-rs` for coarse, infrequent calls. Avoid it for tiny hot calls inside tight loops; FFI marshalling overhead can dominate.
- Export a C ABI from Rust. Do not expose Rust structs, `String`, `Vec`, `Result`, `Future`, or trait objects across raw FFI.
- Define who owns every pointer. If native code allocates memory, also export a free function and call it.
- Keep signatures in one TypeScript module. Add runtime smoke tests that load the actual dynamic library.
- Prefer `ffi-rs` over old `node-ffi`/`ffi-napi` for new work, but still treat it as a sharp tool.

## Node 26 `node:ffi`

Node 26.1+ has experimental `node:ffi`, but it is not a default production choice yet.

```js
import ffi from 'node:ffi';

// Run with: node --experimental-ffi index.js
// Keep this behind a typed wrapper and verify the exact API against Node docs.
```

Use it for experiments, internal diagnostics, and Node-current-only tools. Do not depend on it for public npm packages until it stabilizes and target Node releases commonly include FFI support.

## When To Use Async

Use async:

- Native work waits on network, disk, timers, subprocesses, IPC, or many independent operations.
- The Rust side already uses Tokio or smol and exposes futures naturally.
- The JS caller must keep the event loop responsive.
- The operation can take more than a few milliseconds or can block unpredictably.

Use sync:

- The operation is fast, bounded, CPU-local, and simpler than a Promise API.
- It is called during startup or build tooling where blocking is acceptable.
- The function is a tiny pure transform and users expect a direct return value.

Use worker/async task instead of Rust async:

- The job is CPU-bound and does not `.await` on real I/O.
- The Rust code calls blocking C APIs, compression, crypto, parsing, image/video codecs, or filesystem APIs without async support.
- You would otherwise block the JS event loop or a Tokio/smol executor thread.

Avoid async:

- Do not mark every function async by default. Promise allocation and scheduling add overhead and complicate call sites.
- Do not hold `std::sync::Mutex` across `.await`; use an async mutex or drop the lock first.
- Do not create a Tokio runtime per function call. Create one runtime per addon/process when needed.
- Do not call JS APIs from arbitrary Rust threads. Use napi-rs ThreadsafeFunction, Neon Channel, or Node-API thread-safe functions.

## Performance Checklist

- Batch across the boundary: one call processing 10,000 rows is usually better than 10,000 calls processing one row.
- Prefer `Buffer`, typed arrays, external buffers, or binary formats over JSON for large data.
- Keep ownership clear. Copies are often more expensive than the Rust computation.
- Preallocate Rust output buffers when size is known.
- Avoid per-call runtime construction, regex compilation, schema parsing, and dynamic library open/close.
- Use `--release`, LTO only after measuring, and target-specific CPU features only when your prebuild matrix can support them.
- Profile both sides: Node with `node --prof`, `performance.timerify`, or `clinic`; Rust with `cargo flamegraph`, `divan`, `criterion`, or tracing spans.
- Control concurrency with bounded queues/semaphores. Unbounded Promise fan-out can just move the bottleneck into Rust.
- For Tokio, put blocking code in `spawn_blocking`; for smol, use `smol::unblock` or a blocking worker.
- For `ffi-rs`, open libraries once, reuse `define()`d signatures, and close during shutdown.
- For callbacks from Rust to JS, use bounded queues where available and make JS callback bodies short.

## Packaging And CI

- Build precompiled binaries for macOS arm64/x64, Linux glibc x64/arm64, Linux musl when needed, and Windows x64.
- Test each binary by importing the published JS wrapper, not only by running Rust unit tests.
- Keep native binaries in optional dependencies or platform-specific packages so unsupported platforms fail cleanly.
- Rebuild native addons when `NODE_MODULE_VERSION` changes for non-Node-API bindings. Node-API based addons avoid most Node-major rebuild churn, but still test on every supported Node line.
- Include a pure JS or WASM fallback only when it is actually maintained and tested.

Run the bundled bootstrap script only when you want a minimal napi-rs skeleton:

```bash
bash /mnt/skills/user/node-rust-addon/scripts/bootstrap-napi-rs.sh my-native-package
```
