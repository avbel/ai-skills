---
name: dev-feature
description: Scoped workflow for coordinated features and changes — clarify real ambiguities, show a compact in-chat plan, implement immediately. Use when a change is larger than a localized dev-feature-lite edit but still has one clear architecture, such as an endpoint spanning API, storage, and tests.
---

# Coordinated Feature — Fast Path

For coordinated changes scoped to hours: one in-chat plan, then code. The enemy is ceremony — no design docs, no multi-phase process, no summary documents afterwards. This file is the whole workflow: load no other `dev-*` skill unless a step below names it, and run no review, second opinion, or reviewer subagent unless the user or the repository's instructions ask for one.

**Downgrade instead** to `dev-feature-lite` when the behavior and implementation path are obvious and the change can proceed without a plan or user decision.

**Escalate instead** when the task smells bigger: unknown root cause → `dev-debug`; multiple viable architectures or "how should we..." → `dev-problem-solving`. Say you're escalating and why, in one line.

## Step 1 — Clarify (only if genuinely needed)

Skip this step when nothing is ambiguous. Otherwise ask **at most 3 questions in one batch**, each with a recommended answer the user can approve in one word, and only about what changes the implementation:

- Concerns that fork the design: "should this be per-user or global?"
- Tool/library choices when the codebase shows no precedent
- Behavior at a boundary the request doesn't cover: "what happens on duplicate?"

Look up facts and conventions in the code instead of asking; put obvious defaults in the plan's assumptions; skip preferences that don't change the diff.

## Step 2 — Plan (one short in-chat message, then go)

If `docs/knowledge/INDEX.md` exists, read it and open only the notes that match this task — a past lesson may cover the exact pitfall.

Present a compact plan and **proceed straight to implementation** — the plan is a courtesy heads-up the user can interrupt, not a gate to wait on (unless the user or their setup requires plan approval):

```
Plan: <one-line goal>
- <change 1 — file/area>
- <change 2>
- Tests: <scenarios to cover>
Assumptions: <anything you decided instead of asking>
```

Keep it under ~10 lines: no alternatives-considered section, no risk matrix. Keep the plan in the conversation; write a plan file only when the user asks.

## Step 3 — Implement, KISS

- **Explore cheaply:** locate code with targeted search and read the relevant ranges rather than whole files; batch independent searches and reads into one turn; don't re-read what is already in context.
- **Use what fits already:** project utilities, standard-library/native features, and installed dependencies before custom code or a new package — chosen by required behavior and maintenance cost, not popularity or line count. Share code when meaning and ownership align; don't widen a private API or couple unrelated modules just to remove similar lines.
- **Direct code first:** keep short, clear logic local. Add a helper, interface, or option only when it removes current complexity, centralizes a shared rule, or serves a real boundary; a single caller is neither a ban nor a reason to abstract. No speculative configuration, extension points, or pass-through layers.
- **No silent scope cuts:** implement every part of the plan. If a part turns out harder than planned, or a `TODO`/stub is tempting — **stop and tell the user first**; never commit a placeholder or "not implemented" path the user hasn't approved. Approved leftovers go under "Deferred" in the final report.
- **Out-of-project files are read-only:** paths outside the repo root are inputs, never targets — copy what you need into the project and adapt the copy. Editing outside the repo requires explicit user confirmation.
- **Names over comments:** precise names and readable control flow, without dense one-liners; skip obvious comments and keep necessary rationale brief and beside the code. Preserve required docs, safety invariants, and directives.
- **Tests:** follow the project's existing setup — usually 1–2 integration tests through the real entry point plus the edge cases that apply (empty or boundary input, duplicates, dependency failure). Take expected values from the spec, never recomputed by the code under test. Load `dev-testing` only when the project has no test pattern for this kind of code.

## Step 4 — Finish

- Check your changes — already in context, so skip a full diff dump; `git status --short` catches stray files — for unnecessary layers, speculative code, and comment narration. Simplify within scope without weakening the contract or the tests.
- Iterate with focused tests; after a fix, rerun only what failed, then run the full test and lint commands once at the end. Keep output quiet (summary reporter or the failure tail) and give long commands enough timeout to finish in one call instead of polling. Fix what you broke. **Never delete, skip, weaken, or narrow a test to get green** — a test blocking you is a finding to raise with the user. No unrelated refactors, no dependencies beyond the plan.
- Report in a few sentences: what changed, where, test results, and any "Deferred" items. **Do not** generate `SUMMARY.md`, `CHANGES.md`, or any doc file unless asked.
- End by offering `dev-review` in one line instead of running it. Capture a `dev-knowledge` note only when a non-obvious pitfall surprised you.
