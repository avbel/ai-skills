---
name: rust-async-conventions
description: Rust async conventions for futures, lifetimes, Send and Sync, join/try_join/select, streams, pinning, cancellation safety, executor blocking, and async channels. Use when writing or modifying async Rust code.
---

# Rust Async Conventions

Apply these conventions in async Rust projects. These rules are written for any coding agent, including Claude Code, Codex, Cursor, and Copilot.

## Async Fundamentals

- An `async fn` returns a `Future`; it does nothing until awaited or driven by an executor.
- Do not call an async function without awaiting or spawning it.
- Use `.await`, not `block_on`, inside async contexts.
- Use `async move` blocks when a future must own captured values and outlive the current scope.

## Lifetimes in Async

- A future returned by an `async fn` borrows its non-`'static` arguments.
- Await such futures while their borrowed arguments remain valid.
- When lifetime issues arise, move owned arguments into an `async` block.
- Futures passed to `tokio::spawn` or similar APIs must be `'static`; move owned data in or use `Arc`.

## Send and Sync

- Futures on multithreaded executors must usually be `Send`.
- Every type held across `.await` points must be `Send` for those futures.
- Do not hold `Rc`, `RefCell`, or other non-`Send` types across `.await`.
- Drop non-`Send` values before awaiting or use `Arc` and async-aware synchronization.
- Use `tokio::sync::Mutex` or `futures::lock::Mutex` instead of `std::sync::Mutex` across `.await`.

## Running Multiple Futures

- Use `join!` when all results are needed.
- Use `try_join!` when all futures share an error type and the operation should short-circuit on the first error.
- Use `select!` to race futures and act on the first completion.
- Awaiting multiple async calls sequentially is serial, not concurrent. Use `join!` or spawn tasks when concurrency is intended.

## `select!`

- `select!` borrows futures mutably; incomplete futures can be reused after the macro returns.
- Use a completion branch in loops to detect when all futures are done.
- Use placeholder terminated futures when filling branches later in loops.
- For many concurrent futures of the same type, use `FuturesUnordered`.

## Streams

- A `Stream` is the async equivalent of `Iterator`.
- Use `StreamExt::next().await` to consume items one at a time.
- Use `for_each_concurrent` for bounded concurrent processing.
- Use `.buffered(n)` or `.buffer_unordered(n)` to limit concurrent future execution in a stream of futures.

## Future Internals and Pinning

- Most code should not implement `Future` manually.
- `Future::poll` returns `Poll::Ready(value)` or `Poll::Pending`.
- Manual pinning is rarely needed; `async` and `.await` handle it.
- Use `Box::pin(async move { ... })` for recursive async functions.

## Cancellation

- Dropping a future cancels it.
- Treat every `.await` point as a possible cancellation point.
- Design cancellation-safe code when futures may be raced, timed out, or dropped.
- Remember that `select!` drops losing futures unless they are borrowed and reused intentionally.

## General Guidelines

- Prefer one executor runtime per binary. Do not mix runtimes.
- Keep `.await` points visible.
- Avoid blocking executor threads.
- Use `tokio::task::spawn_blocking` or an equivalent API for CPU-heavy or blocking I/O work.
- Prefer async channels such as `tokio::sync::mpsc` or `futures::channel::mpsc` over `std::sync::mpsc` in async code.

