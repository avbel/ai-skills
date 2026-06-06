---
name: hud-tokio-profiler
description: Use when a Rust Tokio service has latency spikes, stalled tasks, starved workers, or suspected blocking-in-async (sync I/O, lock contention, CPU-bound work on the runtime) and you need to profile a running process on Linux without rebuilding or instrumenting it. Also use when choosing between hud, tokio-console, tokio_unstable, and perf/flamegraphs.
---

# hud — Tokio Worker Profiler (eBPF)

## Overview

`hud` ([github.com/cong-or/hud](https://github.com/cong-or/hud)) is a zero-instrumentation, eBPF-based profiler that finds code **blocking Tokio async runtime workers**. It attaches to a running process and watches the Linux scheduler: when a worker thread spends too long off-CPU in `TASK_RUNNING` (preempted, not sleeping), it captures a stack trace. No code changes, no rebuild for attach, no recompile of the profiler into your app.

**Core principle:** it measures the *symptom* (scheduling latency on worker threads), then you read the captured stacks to find the *cause* (sync I/O, locks, compute on the runtime).

Written in Rust. Dual-licensed MIT / Apache-2.0.

## When to Use

Use hud when:
- A Tokio service has tail-latency spikes, periodic stalls, or "tasks queue up then burst."
- You suspect blocking-in-async: `std::fs`, `std::sync::Mutex`, crypto, compression, big `serde_json` parses, per-request file reads.
- You need to profile a **running** prod/staging process and **cannot rebuild it** to attach.
- You want fast triage before reaching for heavier instrumentation.

Do NOT use hud when:
- Not on Linux 5.8+ (no macOS, no Windows — it needs eBPF/BTF/ring buffer).
- You can't get root on the host.
- The runtime isn't Tokio 1.x.
- You need exact per-task poll durations → use tokio-console instead.
- You need to see the *blocker's* stack directly → use `tokio_unstable` blocking detection.

## Requirements

- Linux **5.8+**, x86_64 or aarch64, **root** (sudo).
- Target app built with debug symbols + frame pointers, or symbol resolution degrades to hex/prefix guesses:
  ```toml
  [profile.release]
  debug = true
  force-frame-pointers = true
  ```
- Don't `strip` the target binary.

## Install

```bash
# Pre-built binary
curl -L https://github.com/cong-or/hud/releases/latest/download/hud-linux-x86_64.tar.gz | tar xz
sudo ./hud my-app

# From source (needs: cargo install bpf-linker; rustup nightly + rust-src; LLVM/clang)
git clone https://github.com/cong-or/hud.git && cd hud
cargo xtask build-ebpf --release && cargo build --release
sudo ./target/release/hud my-app
```

## Quick Reference

| Command | What it does |
|---------|--------------|
| `sudo hud my-app` | Attach by process name, interactive TUI |
| `sudo hud --pid 1234` | Attach by PID (use when name is ambiguous) |
| `sudo hud my-app --threshold 10` | Min off-CPU ms before reporting (default **5**) |
| `sudo hud my-app --window 30` | Rolling display window: only last 30s of events |
| `sudo hud my-app --workers my-pool` | Override worker-thread name prefix (custom runtime) |
| `sudo hud my-app --headless --export trace.json --duration 60` | CI/scripting: no TUI, write trace, stop after 60s |
| `RUST_LOG=info sudo hud my-app` | Debug worker discovery (`workers: 0` issues) |

TUI: `Enter` drills into a hotspot's full call stack; `Q` quits. The status panel shows **Debug %** — amber (<50%) means rebuild with debug symbols.

## Threshold & Window Tuning

**Threshold** = minimum off-CPU duration (ms) before a stack is captured. Checked on *return* to CPU. Blocks during real `.await` I/O sleeps don't trigger — only busy-wait/compute/preemption.

| Threshold | Use case |
|-----------|----------|
| `1` | Latency-critical paths; noisy, includes scheduler jitter |
| `5` (default) | General profiling |
| `10–20` | Containers, batch, noisy hosts |
| `50+` | Initial triage — only severe offenders surface |

Raise threshold by 1–2ms in containers; raise it on >80% CPU hosts (legitimate preemption looks like blocking).

**Window** (`--window N`): without it, metrics accumulate forever and never decay (good for finding rare patterns over a long run). With it, percentages reflect *current* behavior — use `--window 30` for interactive debugging, **no window** for before/after captures.

Impact math: `affected_requests ≈ req/s × block_duration` (a 5ms block at 10k req/s stalls ~50 concurrent requests).

## Debugging Workflow

1. **Triage** — `sudo hud my-app --threshold 50`. Find functions that repeat. Those are the offenders.
2. **Isolate** — `sudo hud my-app --threshold 5`, `Enter` to read full stack. Your code or a dependency?
3. **Validate** — capture before/after under identical load with `--export`, compare.

Reading stacks → common patterns and fixes:
- `std::fs::read` in handler → move to async or `spawn_blocking`.
- `std::sync::Mutex::lock → futex_wait` → shrink critical section, use async mutex, or shard.
- `serde_json::from_str` deep stack → `spawn_blocking` for big payloads, or stream.
- `some_crate::init → std::fs::read` per request → initialize once at startup.

Signal vs noise: real blocking shows **consistent stacks with your code** in the chain; noise is random preemption with stacks entirely in runtime/stdlib that don't repeat.

## Exports (CI / before-after)

`--export` writes **Chrome Trace Event** JSON — open in [Perfetto](https://ui.perfetto.dev), [Speedscope](https://www.speedscope.app), or `chrome://tracing`. `--headless` requires `--export`.

```json
{ "traceEvents": [ {
  "name": "your_code::handler", "cat": "execution",
  "ph": "B", "ts": 1234.56, "pid": 12345, "tid": 12346,
  "args": { "worker_id": 0, "detection_method": 2 }
} ] }
```
`ph`: `B` = block start, `E` = end. `detection_method: 2` = exceeded off-CPU threshold.

Compare blocking-event counts with `jq`:
```bash
jq '[.traceEvents[] | select(.ph=="B")] | length' before.json   # 847
jq '[.traceEvents[] | select(.ph=="B")] | length' after.json     # 312  → 63% fewer
# confirm a specific function is gone, and no NEW hotspots appeared:
jq -r '.traceEvents[]|select(.ph=="B").name' after.json | sort | uniq -c | sort -rn | head -5
```
CI gate example: fail the build if `B` event count exceeds a budget.

## Pros & Cons vs Similar Tools

| Tool | Best for | Trade-off vs hud |
|------|----------|-------------------|
| **hud** | Quick triage of a running, un-instrumented process | Measures symptom (scheduling latency), not the blocker directly; Linux+root+Tokio only |
| **tokio-console** | Precise per-task poll times, task/resource state, live task list | Requires `console-subscriber` instrumentation + `tokio_unstable` build; can't attach to an arbitrary running binary |
| **Tokio `tokio_unstable` block detection** | Pinpoints the blocking call directly | Requires rebuild with `RUSTFLAGS=--cfg tokio_unstable` |
| **perf + flamegraphs** | Broad CPU profiling, on-CPU hotspots, any language | Shows where CPU is spent, not *off-CPU* worker starvation; manual interpretation; doesn't understand Tokio workers |

### Why pick hud (pros)
- **Zero instrumentation / zero rebuild to attach** — the only one here you can point at a process you didn't compile specially. Huge for prod incidents.
- **Tokio-aware** — auto-detects worker threads (4-step discovery) and filters `spawn_blocking` pool noise; perf/flamegraphs don't know what a worker is.
- **Whole-program visibility** — catches blocking inside dependencies you can't easily instrument.
- **Low overhead** — <5% typical (99 Hz sampling, cached symbol resolution).
- **Fast feedback loop** — TUI hotspots vanish live as you fix them; export gives empirical CI gates in Chrome Trace format (Perfetto/Speedscope ready).

### Why it might not fit (cons)
- **Symptom, not cause** — it captures the *victim* worker's stack during latency, not the blocker's. You infer the culprit by pattern across traces. tokio-console / `tokio_unstable` point more directly.
- **Platform-locked** — Linux 5.8+, x86_64/aarch64, root, Tokio 1.x only. Nothing on macOS/Windows/dev laptops.
- **Needs debug symbols + frame pointers** for readable output; stripped/optimized binaries give hex addresses and short stacks.
- **False positives under load** — system CPU pressure (>80%), containers, VM jitter, cross-NUMA migration all look like blocking. Raise `--threshold`.
- **No per-task semantics** — it won't tell you *which task* or give poll-time distributions the way tokio-console does.

**Rule of thumb:** reach for hud **first** when triaging a live, un-instrumented Tokio service on Linux. Switch to **tokio-console** or **`tokio_unstable`** once you can rebuild and need to nail the exact blocking task/call. Use **perf/flamegraphs** for on-CPU compute hotspots unrelated to runtime starvation.

## Common Mistakes / Troubleshooting

| Symptom | Cause → Fix |
|---------|-------------|
| `workers: 0` | Custom thread names. Check `ps -T -p <PID>`; pass `--workers <prefix>`; debug with `RUST_LOG=info`. App must be doing Tokio work during the 500ms stack-discovery window. |
| No events, `workers: N` ok | App idle (generate load), threshold too high (`--threshold 1`), or multiple process matches (use `--pid`). |
| `<unknown>` / hex names, Debug % amber | Missing DWARF. Add `debug = true`, rebuild; don't `strip`; or point `--target /path/to/binary`. |
| Only 1–2 stack frames | Add `force-frame-pointers = true`, rebuild. |
| `BPF program verification failed` | Kernel <5.8 or no BTF/ring buffer. `uname -r`. |
| Garbled TUI | Use a modern terminal, or run `--headless --export`. |
| Permission denied | Run with `sudo`. |
| eBPF build fails (from source) | `cargo install bpf-linker`; `rustup toolchain install nightly --component rust-src`; install LLVM/clang (`apt install llvm-dev libclang-dev` / `dnf install llvm-devel clang`). |

## How It Works (1-paragraph mental model)

eBPF on the `sched_switch` tracepoint detects workers going off/on CPU and reports when off-CPU duration > threshold; a 99 Hz `perf_event` sampler captures stacks (99 Hz dodges the 100 Hz timer alias). Events flow through a ring buffer to userspace, which resolves raw addresses via `/proc/<pid>/maps` + DWARF and demangles Rust symbols, then renders the TUI or writes the export. See `docs/ARCHITECTURE.md` in the repo.
