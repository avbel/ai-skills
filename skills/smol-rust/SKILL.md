---
name: smol-rust
description: smol async runtime conventions for Rust — block_on, global spawn, Executor/LocalExecutor, Timer, Async<T> I/O adapter, Unblock, futures-lite prelude, the smol-rs subcrates, and running tokio-based libraries via async-compat. Use when writing or reviewing async Rust that uses smol, or when choosing between smol and tokio.
---

# smol

smol is a **small, fast, modular** async runtime for Rust. The `smol` crate is a thin facade that re-exports a family of independent [smol-rs] crates (`async-executor`, `async-io`, `async-channel`, `async-lock`, `async-net`, `async-fs`, `async-process`, `blocking`, `futures-lite`). The reactor (`async-io`, built on `polling`) wraps epoll / kqueue / event ports / IOCP. Apply these conventions when building async Rust on smol. Current: smol 2.0.2, dual MIT/Apache-2.0. Upstream README/Cargo.toml now set MSRV to **Rust 1.85** (crates.io metadata for the already-published 2.0.2 still reports 1.63), so target Rust 1.85+.

## Core API (what `smol::` gives you)

- **`smol::block_on(future)`** — run a future to completion on the current thread. The entry point for `fn main` and tests (smol has no required `#[main]` macro).
- **`smol::spawn(future) -> Task<T>`** — spawn onto smol's built-in **global executor**. Worker-thread count comes from the `SMOL_THREADS` env var (**default 1**). You still need a `block_on` somewhere to drive progress on the calling thread.
- **`Task<T>`** — a spawned task handle. **Dropping a `Task` cancels it.** `.await` it for the result, or call **`.detach()`** to let it run independently. Forgetting this silently cancels work; if the program exits while global tasks are still running, their futures are abandoned and destructors may not run.
- **`Executor` / `LocalExecutor`** — composable executors when you don't want the global one. `ex.spawn(fut)`, `ex.spawn_many(...)` for large batches, drive with `block_on(ex.run(future))`. `LocalExecutor` runs `!Send` futures on one thread. See the **`smol-macros`** crate for declarative `main!`/`test!` macros and multi-threaded `Executor` setup without proc-macro dependencies.
- **`Timer`** (`async-io`) — `Timer::after(Duration)`, `Timer::at(Instant)`, `Timer::interval(Duration)`, `Timer::interval_at(Instant, Duration)`, `Timer::never()`, plus `set_after`/`set_at`/`set_interval` reset methods. `.await` a one-shot timer for an `Instant`; poll an interval timer as a stream. Precision is platform-limited (Windows is roughly 16 ms) and timers may sleep longer, never less.
- **`Async<T>`** — wrap a **pollable** OS I/O handle (networking types and OS FDs such as `TcpStream`, `UnixStream`, timerfd, inotify) to make it async via the reactor. `Async::new` puts the handle in non-blocking mode; `Async::new_nonblocking` assumes you already did. `async-net` provides ready-made `TcpStream`/`TcpListener`/`UdpSocket`/Unix types built on it. Regular files and stdio are **not** safe/pollable here — use `async-fs` (or `Unblock`) for those, not `Async`.
- **`unblock(closure)` / `Unblock<T>`** (`blocking` crate) — run **blocking or CPU-heavy** work on a dedicated thread pool. `Unblock::new(std::io::stdout())` adapts blocking I/O (stdio, `std::fs::File`) into async; `unblock(|| expensive())` offloads a closure.
- **Re-exported modules:** `smol::io`, `smol::future`, `smol::stream`, `smol::pin`, `smol::ready` (from `futures-lite`); `smol::channel` (mpmc), `smol::lock` (Mutex/RwLock/Semaphore/Barrier/OnceCell), `smol::net`, `smol::fs`, `smol::process` (`smol::process` is omitted on `target_os = "espidf"`).
- **`use smol::prelude::*;`** — brings in `Future`, `Stream`, and the extension traits (`FutureExt`, `StreamExt`, `AsyncReadExt`, `AsyncWriteExt`, `AsyncBufReadExt`, `AsyncSeekExt`) so `.next()`, `.read_to_end()`, `.race()`, etc. are in scope.

```rust
use smol::{io, net, prelude::*, Unblock};

fn main() -> io::Result<()> {
    smol::block_on(async {
        let mut stream = net::TcpStream::connect("example.com:80").await?;
        stream.write_all(b"GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n").await?;
        let mut stdout = Unblock::new(std::io::stdout()); // blocking stdout → async
        io::copy(stream, &mut stdout).await?;
        Ok(())
    })
}
```

## futures-lite

smol uses **`futures-lite`**, a smaller, faster-compiling subset of `futures`. Prefer its combinators (`future::or`, `future::race`, `future::zip`, `StreamExt`, `io::copy`, `AsyncReadExt`) over pulling in the full `futures` crate. The `futures-util` combinators you know mostly have lighter equivalents here. Only depend on `futures` directly when you need something `futures-lite` lacks (e.g. `Sink`, `select!` macro, `FuturesUnordered`).

## Concurrency primitives

- **Channels:** `smol::channel::{bounded, unbounded}` — async multi-producer multi-consumer. `send().await` / `recv().await`; closes when all senders or receivers drop.
- **Locks (`async-lock`):** `Mutex`, `RwLock`, `Semaphore`, `Barrier`, `OnceCell`. These are **held across `.await`** safely (unlike `std::sync::Mutex`). Use `std::sync::Mutex` only for short non-await critical sections.
- **Run futures concurrently:** `future::zip(a, b).await` (both), `future::or(a, b).await` / `.race()` (first to finish). For many dynamic tasks, `spawn` each and collect the `Task`s, or use an `Executor`.

## Running tokio-based libraries (async-compat)

Many popular crates (reqwest, tonic, tokio-postgres) require a **tokio runtime context** and will panic ("no reactor running") under smol. (Hyper 1.x is runtime-agnostic via its `rt` adapters, but its tokio-based helpers still need a tokio context.) Wrap the offending future with the **`async-compat`** adapter:

```rust
use async_compat::Compat;
let body = smol::block_on(Compat::new(async {
    reqwest::get("https://example.com").await?.text().await
}))?;
```

`Compat` starts a background tokio runtime and binds it for the wrapped future and its I/O. Wrap the **future that touches tokio types**, not your whole program.

## smol vs tokio — which to use

| | smol | tokio |
|---|------|-------|
| Philosophy | Minimal, modular crates you compose | Batteries-included framework |
| Scheduler | `async-executor` (global or your own) | Work-stealing multi-threaded scheduler |
| Reactor | `async-io` / `polling` | `mio` |
| Footprint / compile | Small deps, fast builds | Larger deps, slower builds |
| Ecosystem | Smaller; many libs need `async-compat` | De-facto standard (axum, tonic, hyper, sqlx, …) |
| Entry point | `smol::block_on` (no macro needed) | `#[tokio::main]` / `Runtime` |
| API style | std-like via `futures-lite`; wrap std types with `Async<T>` | First-party async I/O, `tokio::time`, `tokio::sync`, `tokio::fs` |

**Choose smol when:** you want a lean dependency tree and fast builds, are writing a small binary / CLI / tool, want to compose your own executor, need to mix async with blocking std code cleanly (`Async<T>`/`unblock`), or are writing a **runtime-agnostic library** (depend on `futures-io`/`futures-core` traits, not a full runtime; reach for `async-io` only when intentionally targeting smol-rs).

**Choose tokio when:** you need its ecosystem (axum/tonic/hyper/`sqlx`/`tokio-postgres` default to it), want a mature work-stealing scheduler for high-throughput multicore workloads, or the team/codebase already standardizes on it.

**They interoperate:** run tokio libs on smol via `async-compat`. A runtime-agnostic library should avoid hard-coding either — express I/O in terms of `futures-io`/`futures-core` traits rather than depending on a specific runtime.

## Patterns

- Drive everything from one `smol::block_on` at the top; use `smol::spawn`/`Executor` for concurrency underneath.
- Set `SMOL_THREADS` (env) for multi-core throughput with the global executor, or build a multi-threaded `Executor` and run it on N threads (see `smol-macros`).
- Offload blocking syscalls, `std::fs`, and CPU-bound work with `unblock`/`Unblock` so the reactor thread stays responsive.
- Wrap arbitrary std I/O types you must use with `Async::new(...)` to integrate them with the reactor instead of blocking.
- Do not concurrently read from the same `Async<T>` in multiple tasks or concurrently write from multiple tasks; one reader and one writer is fine, but same-direction contention wakes tasks in turn and wastes CPU.
- After `Async::into_inner()`, explicitly restore blocking mode if you need a blocking handle again. `AsyncWriteExt::close()` flushes; use socket `Shutdown` for TCP/Unix half-close semantics.
- Hold `async-lock` guards (not `std::sync`) when a lock must survive an `.await`.

## Antipatterns to Avoid

| Antipattern | Why it hurts | Do instead |
|-------------|-------------|------------|
| `smol::block_on` **inside** an async task | Blocks the executor thread; can deadlock | `.await` the future directly |
| Dropping a `Task` and expecting it to run | Drop **cancels** the task | `.await` it or `.detach()` |
| Blocking/CPU work directly in a task | Stalls a worker thread (with the default single worker, all I/O stalls) | `unblock(...)` / `Unblock` / `blocking` pool |
| Calling tokio-based libs (reqwest/hyper) directly | Panics: no tokio runtime/reactor | Wrap with `async_compat::Compat` |
| Holding `std::sync::Mutex` across `.await` | Can deadlock the executor; not async-aware | `smol::lock::Mutex` |
| Expecting multi-core without configuring threads | Global executor defaults to **1** worker | Set `SMOL_THREADS` or run a multi-threaded `Executor` |
| Assuming spawned task cleanup at process exit | Global tasks can be abandoned without running destructors | Await tasks or shut down an `Executor` explicitly |
| Pulling in the full `futures` crate by habit | Heavier, slower compile | Use `futures-lite` (`smol::future`/`stream`) first |
| Mixing tokio and smol runtimes ad hoc in one binary | Conflicting reactors, surprising panics | Pick one; bridge only via `async-compat` |
| Letting `main` return before spawned tasks finish | Tasks are cancelled at exit | `.await` the `Task`s, or drive them on an `Executor` you `block_on` to completion |

## Quick Reference

| Need | smol API |
|------|----------|
| Run a future | `smol::block_on(fut)` |
| Spawn (global) | `let t = smol::spawn(fut); t.detach()` or `t.await` |
| Custom executor | `Executor::new()` + `block_on(ex.run(fut))` |
| `!Send` tasks | `LocalExecutor` |
| Delay / interval | `Timer::after(d).await` / `Timer::interval(d)` |
| Async TCP/UDP/Unix | `smol::net::{TcpStream, TcpListener, UdpSocket}` |
| Adapt a std I/O type | `smol::Async::new(std_socket)` |
| Blocking work | `smol::unblock(|| ...)` / `Unblock::new(...)` |
| Channel | `smol::channel::bounded(n)` |
| Async lock across await | `smol::lock::Mutex` |
| Run a tokio lib | `async_compat::Compat::new(fut)` |
