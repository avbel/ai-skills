---
name: dev-feature
description: Scoped workflow for coordinated features and changes — clarify real ambiguities, show a compact in-chat plan, implement immediately. Use when a change is larger than a localized dev-feature-lite edit but still has one clear architecture, such as an endpoint spanning API, storage, and tests.
---

# Coordinated Feature — Fast Path

For coordinated changes scoped to hours: one short in-chat plan, then code. No design docs, multi-phase process, or summary files. This file is the whole workflow: load no other `dev-*` skill unless a step names it, and run no review, second opinion, or subagent unless the user or the repository's instructions ask. Repository instructions and project skills override this file wherever they cover the same ground; use the commands and conventions they list instead of rediscovering them.

**Downgrade** to `dev-feature-lite` when the path is obvious and needs no plan or user decision. **Escalate** when the root cause is unknown → `dev-debug`, or several architectures are viable → `dev-problem-solving`. Say which and why in one line.

## Rules

- **No silent scope cuts.** Implement every part of the plan. If a part proves harder than planned, or a stub or `TODO` is tempting, stop and tell the user first. Approved leftovers go under "Deferred" in the report.
- **Never delete, skip, weaken, or narrow a test to get green** — a blocking test is a finding to raise with the user.
- **Paths outside the repository are read-only** unless the user explicitly confirms an edit; copy what you need into the project and adapt the copy.
- **Reuse before building:** project utilities, standard-library/native features, and installed dependencies before custom code; no new package unless the plan names it. Share code only when meaning and ownership align — don't widen a private API or couple unrelated modules to remove similar lines.
- **Direct code:** add a helper, interface, or option only when it removes current complexity, centralizes a shared rule, or serves a real boundary. No speculative configuration, extension points, pass-through layers, or unrelated refactors.
- **Names over comments:** precise names and readable control flow, no dense one-liners; brief rationale only where the code cannot show it. Keep required docs, safety invariants, and directives.
- **No extra documents:** no `SUMMARY.md`, `CHANGES.md`, or plan file unless asked.

## Step 1 — Clarify (only if needed)

Skip when nothing is ambiguous. Otherwise ask **at most 3 questions in one batch**, each with a recommended answer the user can approve in one word, and only about what changes the implementation: a design fork ("per-user or global?"), a tool or library choice with no precedent in the codebase, or boundary behavior the request doesn't cover ("what happens on duplicate?"). Look facts up in the code instead of asking; put obvious defaults in the plan's assumptions.

## Step 2 — Plan, then go

If repository or user instructions name a lessons store, or `docs/knowledge/INDEX.md` exists, consult it and read only the notes matching the task. Then post a plan of at most ~10 lines and **start implementing without waiting** — it is a heads-up the user can interrupt, not a gate (unless the user or their setup requires approval):

```
Plan: <one-line goal>
- <change 1 — file/area>
- <change 2>
- Tests: <scenarios to cover>
Assumptions: <anything you decided instead of asking>
```

No alternatives section, no risk matrix.

## Step 3 — Implement

- Read targeted ranges, not whole files; batch independent searches and reads into one turn and do not re-read what is already in context.
- If the change alters a signature, return or error shape, export, config key, persisted format, or behavior other callers rely on (defaults, ordering, side effects), find its callers, fixtures, and tests and include the necessary downstream updates.
- **Tests:** follow the project's setup; use the smallest stable seam that proves the changed behavior, plus its relevant failure cases. Storage and protocol contracts need integration checks, not mocks. Reproduce a bug before fixing it and keep the regression test. Existing coverage can suffice; trivial edits need no new test. Take expected values from the spec, never recomputed by the code under test. Load `dev-testing` only when the project has no test pattern for this kind of code.

## Step 4 — Finish

- Check what you wrote against the Rules: unnecessary layers, speculative code, comment narration, unplanned scope. Use what is already in context; read the diff only for files written by subagents, scripts, or code generators. Run `git status --short` once to catch stray debug, temp, or generated files. Simplify within scope without weakening the contract or the tests.
- Iterate with focused checks; after the last edit, run the repository-required checks once and rerun a check only when its inputs changed since it passed. Keep output quiet (summary reporter or failure tail) and give long commands a timeout that lets them finish in one call. Fix what you broke. After two failed fixes for the same failure, stop patching and revisit the plan's assumption with the user.
- Report in a few sentences: what changed and where, `Checks: <commands> — passed after last edit` (or the exact failure), checks that could not run, and any "Deferred" items. Never present a skipped check as a pass.
- Write a `dev-knowledge` note only when a non-obvious pitfall surprised you and the project permits capture. No review offer or extra workflow after completion.
