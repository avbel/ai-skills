---
name: nanoprogress-rust
description: nanoprogress terminal progress bar conventions — builder API, ticks, finalization, TTY/custom writers, thread sharing, and CLI output. Use when writing Rust CLI code that imports 'nanoprogress'.
---

Apply these conventions when using `nanoprogress` in Rust CLI applications.

## Package Fit

- Use `nanoprogress` for one simple determinate progress bar with zero runtime dependencies.
- Prefer heavier crates such as `indicatif` or `kdam` when you need multi-bars, spinners, templates, ETA/rate estimation, redraw throttling, or rich terminal layout.
- Keep progress output out of machine-readable stdout. For CLIs that emit JSON/CSV/data on stdout, send the bar to stderr with `.writer(Box::new(std::io::stderr()))`.
- `nanoprogress` is currently a small standard-library-only crate; do not add terminal/color dependencies around it unless the product requirement exceeds what it provides.

## Dependency

```bash
cargo add nanoprogress
```

```rust
use nanoprogress::ProgressBar;
```

The public API centers on `ProgressBar::new(total)`, the builder returned from it, and the running `ProgressBar` handle.

## Lifecycle

```rust
use nanoprogress::ProgressBar;

let bar = ProgressBar::new(items.len() as u64)
    .message("Processing...")
    .start();

for item in items {
    process(item)?;
    bar.tick(1);
}

bar.success("Processing complete");
```

- Always call `.start()` after configuring the builder; it renders the initial `0/total` state immediately.
- Call `.tick(amount)` only after work is committed. Ticks saturate and clamp at `total`.
- `ProgressBar::new(0)` normalizes the total to `1`; handle empty inputs yourself if displaying `0/0` semantics matters.
- Finish exactly once with `.success(message)` or `.fail(message)`. After finalization, later ticks and finalization calls are no-ops.
- If the last handle is dropped without explicit finalization, `Drop` writes a cleanup newline; do not rely on this as user-facing success/failure reporting.

## Builder Options

```rust
let bar = ProgressBar::new(50)
    .width(30)
    .fill('#')
    .empty('-')
    .message("Installing...")
    .start();
```

- `.width(usize)` sets the bar track width; default is `40`.
- `.fill(char)` sets the completed segment; default is `█`.
- `.empty(char)` sets the remaining segment; default is `░`.
- `.message(&str)` sets the initial text after the count.
- `.writer(Box<dyn std::io::Write + Send>)` redirects output from stdout.
- `.tty(bool)` overrides TTY detection; use sparingly and prefer default detection for stdout.

## TTY and Custom Writers

- Stdout auto-detects TTY mode. TTY output uses carriage-return redraws and colored final symbols.
- Non-TTY output skips ANSI codes and writes each update on its own line, making logs readable when piped or redirected.
- Custom writers default to non-TTY mode. If the custom writer is an actual terminal stream and redraw behavior is desired, opt in with `.tty(true)`.
- Use stderr for progress in data-producing CLIs:

```rust
use nanoprogress::ProgressBar;
use std::io;

let bar = ProgressBar::new(total)
    .writer(Box::new(io::stderr()))
    .message("Uploading...")
    .start();
```

## Error Handling

Finalize failures on every fallible path that starts a bar:

```rust
use nanoprogress::ProgressBar;

let bar = ProgressBar::new(total).message("Migrating...").start();
let result = run_migration(&bar);

match result {
    Ok(()) => bar.success("Migration complete"),
    Err(error) => {
        bar.fail("Migration failed");
        return Err(error);
    }
}
```

- Do not print errors on the same line as a live TTY bar; finalize first, then return/log the error.
- Prefer terse progress messages. Long messages redraw poorly and bloat non-TTY logs.
- Avoid secrets in `.message()`, `.success()`, or `.fail()`; non-TTY mode may persist every update in logs.

## Updating Messages

```rust
let bar = ProgressBar::new(steps).message("Step 1...").start();

bar.set_message("Step 2...");
bar.tick(1);
```

- `set_message()` changes state but does not render immediately; the next `tick()` displays it.
- `success()` and `fail()` ignore the stored progress message and display only their own message argument.
- If an immediate message-only refresh is required, call `tick(0)` after `set_message()`.

## Thread Sharing

`ProgressBar` is `Clone + Send + Sync`; clone the running handle for worker threads.

```rust
use nanoprogress::ProgressBar;
use std::thread;

let bar = ProgressBar::new(100).message("Working...").start();
let handles: Vec<_> = (0..4)
    .map(|_| {
        let bar = bar.clone();
        thread::spawn(move || {
            for _ in 0..25 {
                do_unit_of_work();
                bar.tick(1);
            }
        })
    })
    .collect();

for handle in handles {
    handle.join().expect("worker thread panicked");
}

bar.success("Done");
```

- Clone only the started `ProgressBar`, not the builder.
- Join workers before calling `success()` or `fail()`, otherwise later worker ticks are ignored.
- Very high-frequency ticks serialize through an internal mutex and flush on every render; aggregate small units before ticking.

## Testing

Use a custom writer and non-TTY assertions instead of writing to real stdout/stderr in tests.

```rust
use nanoprogress::ProgressBar;
use std::io::{self, Write};
use std::sync::{Arc, Mutex};

#[derive(Clone)]
struct TestWriter(Arc<Mutex<Vec<u8>>>);

impl Write for TestWriter {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.0.lock().expect("test writer poisoned").extend_from_slice(buffer);
        Ok(buffer.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

let buffer = Arc::new(Mutex::new(Vec::new()));
let writer = TestWriter(buffer.clone());
let bar = ProgressBar::new(10).writer(Box::new(writer)).start();
bar.tick(5);
bar.success("done");

let output_bytes = buffer.lock().expect("test writer poisoned").clone();
let output = String::from_utf8_lossy(&output_bytes);
assert!(output.contains("5/10"));
assert!(output.contains("✔ done"));
```

- Custom writers default to non-TTY; assert no ANSI escapes unless explicitly testing `.tty(true)`.
- Assert counts and final symbols rather than the full bar string when tests should tolerate width/character changes.

## API Reference

| Operation | API |
|---|---|
| Create builder | `ProgressBar::new(total: u64)` |
| Start rendering | `ProgressBarBuilder::start()` |
| Initial text | `ProgressBarBuilder::message(&str)` |
| Bar width | `ProgressBarBuilder::width(usize)` |
| Fill/empty chars | `ProgressBarBuilder::fill(char)`, `.empty(char)` |
| Custom destination | `ProgressBarBuilder::writer(Box<dyn Write + Send>)` |
| Force TTY mode | `ProgressBarBuilder::tty(bool)` |
| Increment | `ProgressBar::tick(amount: u64)` |
| Change text | `ProgressBar::set_message(&str)` |
| Success/failure | `ProgressBar::success(&str)`, `.fail(&str)` |
