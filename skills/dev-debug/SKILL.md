---
name: dev-debug
description: Systematic debugging for hard bugs — reproduce, bisect, root-cause before fixing; generates real debugger setups (VS Code launch.json, JetBrains, node --inspect, lldb/gdb, rr) with a step-by-step manual for the problem location. Use when a bug resists the first fix attempt, when the user says "still broken", "can't figure out why", "help me debug", or asks for a debugger config.
---

# Systematic Debugging

For bugs that survive the first obvious fix. The core discipline: **find the root cause before writing any fix**. A fix without a root cause is a guess, and guesses that "work" hide the real bug. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

## Phase 1 — Reproduce and Localize (always)

1. **Reproduce first.** Turn the report into a command that fails deterministically — ideally a failing test. If you can't reproduce, gather more data (logs, inputs, versions); do not "fix" what you can't see fail.
2. **Read the actual error.** Full stack trace, exact message, line numbers — not a paraphrase.
3. **Recent changes first:** `git log --oneline -20` on the touched files; if the bug is a regression, `git bisect run <failing-command>` finds the exact commit mechanically — prefer it over reading diffs when there are more than a handful of commits.
4. **Form one hypothesis, test it with evidence** (a log line, an assertion, a minimized input) before changing code. State the hypothesis explicitly: "I believe X because Y; if true, Z will show it."
5. **After 2 failed hypotheses, stop guessing** and move to Phase 2 — the bug is in your model of the system, not in the place you're looking.

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

1. Write the failing test **first** (it exists from Phase 1 reproduction — commit it).
2. Fix the root cause, not the symptom. If the honest fix is large, say so — don't band-aid silently.
3. Run the full suite, not just the new test.
4. If the hunt took real effort, capture the lesson via `dev-knowledge` (symptom → root cause → fix) so the next occurrence costs minutes.

## Anti-patterns

- Stacking speculative fixes ("maybe this helps") without evidence between attempts.
- Deleting/weakening a failing assertion to make the failure go away.
- Adding retries/sleeps to hide a race instead of finding it.
- Debugging by re-reading the same code for the third time — get runtime evidence instead (log, breakpoint, bisect).
