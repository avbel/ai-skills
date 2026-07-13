---
name: dev-debug
description: Systematic debugging for hard bugs — reproduce, bisect, root-cause before fixing; generates real debugger setups (VS Code launch.json, JetBrains, node --inspect, lldb/gdb, rr) with a step-by-step manual for the problem location. Use when a bug resists the first fix attempt, when the user says "still broken", "can't figure out why", "help me debug", or asks for a debugger config.
---

# Systematic Debugging

For bugs that survive the first obvious fix. The core discipline: **find the root cause before writing any fix**. A fix without a root cause is a guess, and guesses that "work" hide the real bug. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

## Phase 1 — Reproduce and Localize (always)

1. **Build a feedback loop first — this gate IS the skill.** One command that is red now, deterministic, fast, and runnable without a human — best is a failing test; otherwise a curl against the endpoint, a CLI run diffed against expected output, a throwaway harness script, or a `git bisect run` wrapper. Run it once and watch it fail before anything else. **No red-capable command → no fixing** — gather more data instead (logs, inputs, versions). For flaky bugs, don't chase a clean repro — raise the reproduction rate until the loop is usable: run it 100× in a loop, parallelize, inject sleeps at suspected races.
2. **Read the actual error.** Full stack trace, exact message, line numbers — not a paraphrase.
3. **Recent changes first:** `git log --oneline -20` on the touched files; if the bug is a regression, `git bisect run <failing-command>` finds the exact commit mechanically — prefer it over reading diffs when there are more than a handful of commits.
4. **List 3–5 ranked falsifiable hypotheses, then test only the top one.** Each in the form "if X is the cause, changing Y will make the bug disappear" — show the list to the user before testing. Verify with evidence (a log line, an assertion, a minimized input) before changing any code.
5. **Tag every debug log with one token** (`[DBG-4f2a]`) so cleanup after the hunt is a single grep — never log everything and grep the noise.
6. **After 2 failed hypotheses, stop guessing** and move to Phase 2 — the bug is in your model of the system, not in the place you're looking.

## Phase 2 — Interactive Debugger (hard cases)

When print-debugging stalls — state mutates unexpectedly, timing matters, the failure point is far from the cause — set the **user** up with a real debugger at the suspect location. Generate the config for their environment, don't just describe it.

### What to generate

1. **The config file** for their IDE (detect from repo: `.vscode/` → VS Code, `.idea/` → JetBrains; otherwise ask which they use):
   - **VS Code** → `.vscode/launch.json` entry with the exact program/test, args, env, and `skipFiles`/`sourceMaps` as appropriate. Types: `node` (JS/TS, works for vitest/jest via the test binary), `lldb` via CodeLLDB (Rust — build the specific test with `cargo test --no-run` and point at the binary), `debugpy` (Python), `go` (Delve).
   - **JetBrains** → an `.idea/runConfigurations/<name>.xml` run configuration, or exact click-path instructions when XML formats churn.
2. **A CLI fallback** for no-IDE contexts:
   - Node: `node --inspect-brk <entry>` (or `vitest --inspect-brk --no-file-parallelism <test>`) + `chrome://inspect`
   - Rust: `rust-lldb target/debug/deps/<test-bin>` with `b <file>:<line>`, `run --exact <test_name>`
   - Native/Linux: `gdb`; for non-deterministic bugs, `rr record` + `rr replay` (reverse-continue from the crash to the cause — the single best tool for heisenbugs)
3. **A short manual** tailored to this bug — not generic debugger docs:
   - The 2–4 breakpoint locations to set (`file:line`) and *why each one* (what to inspect there)
   - Which variables/expressions to watch at each stop
   - A conditional-breakpoint expression when the code path runs many times (`id === "the-failing-one"`)
   - What outcome distinguishes hypothesis A from B ("if `cache.size` is already 0 here, the eviction ran early → look at TTL config")

### Special situations

- **Async/await gaps** (Node): enable async stack traces (`--async-stack-traces` is default-on in modern V8; in launch.json ensure `"sourceMaps": true`).
- **Race conditions:** debugger pauses can mask races. Prefer `rr` (native), or targeted logging with timestamps + thread/task IDs, then reconstruct the interleaving.
- **Attach vs launch:** for long-running servers generate an attach config (`--inspect` port / `lldb -p <pid>`) instead of a launch config.

## Phase 3 — Fix and Lock It In

1. Write the failing test **first** (it exists from Phase 1 reproduction — commit it), placed at a stable seam (public interface, entry point). **If no correct seam exists for the regression test, that is itself a finding** — report the architectural gap instead of wedging a test into internals.
2. Fix the root cause, not the symptom. If the honest fix is large, say so — don't band-aid silently.
3. Run the full suite, not just the new test. Record the confirmed root cause in the commit message.
4. Ask "what would have prevented this bug?" — after the fix, not before. If the hunt took real effort, capture the answer via `dev-knowledge` (symptom → root cause → what didn't work → fix) so the next occurrence costs minutes.

## Anti-patterns

- Stacking speculative fixes ("maybe this helps") without evidence between attempts.
- Deleting/weakening a failing assertion to make the failure go away.
- Adding retries/sleeps to hide a race instead of finding it.
- Debugging by re-reading the same code for the third time — get runtime evidence instead (log, breakpoint, bisect).
