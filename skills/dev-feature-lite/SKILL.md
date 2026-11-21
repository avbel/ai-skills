---
name: dev-feature-lite
description: Minimal workflow for straightforward, localized features and changes. Use for "add", "change", or "fix" requests when the behavior and implementation path are obvious and no design decision or plan is needed.
---

# Simple Feature — Lite

For an obvious change with one clear implementation path: implement, verify, report. Process must stay cheaper than the change. This file is the whole workflow: load no other `dev-*` skill unless you escalate, and run no review, second opinion, or subagent unless the user or the repository's instructions ask. Repository instructions and project skills override this file wherever they cover the same ground; use the commands they list instead of rediscovering them.

Escalate in one line when inspection reveals unclear product behavior, contract alignment across several behavioral surfaces, a cross-cutting migration, or material production risk: route to `dev-feature`, `dev-problem-solving`, or `dev-debug`. File count alone is not a reason.

## Rules

- Present no plan and await no approval. Ask only when no safe, correct implementation can proceed without the answer; otherwise state the assumption and continue.
- Deliver the full behavior: no stubs, placeholders, TODOs for current requirements, or silent scope cuts.
- Never delete, skip, weaken, or narrow a test to get green; a blocking test is a finding to report.
- Paths outside the repository are read-only unless the user explicitly asks.
- Follow the nearest existing pattern. Add only the code, tests, and docs the request needs: no unrelated cleanup, speculative options, forwarding wrappers, or new packages where project code, the standard library, or installed dependencies suffice.
- Preserve validation, error handling, data-loss safeguards, security, and accessibility.
- Precise names and straightforward control flow, no dense one-liners. No comments on obvious code; brief rationale only where the code cannot show it.

## Steps

1. **Inspect.** Read the affected code, its tests, and the nearest existing pattern — targeted ranges, not whole files; batch independent searches and reads into one turn and do not re-read what is already in context. If the change alters a signature, return or error shape, export, config key, persisted format, or behavior other callers rely on (defaults, ordering, side effects), find its callers, fixtures, and tests before editing.
2. **Pin the behavior.** Bug fix: reproduce the failure first and keep a regression check. New nontrivial behavior: add the smallest test at a stable seam that would fail if it broke, unless existing tests already prove it. Trivial edits need no new test.
3. **Implement** the smallest complete change.
4. **Verify.** Iterate with focused checks on the touched area. After the last edit, run the repository-required checks once; rerun a check only when its inputs changed since it passed. Keep output quiet (summary reporter or failure tail) and give long commands a timeout that lets them finish in one call. Fix failures you caused; report pre-existing ones without expanding scope. After two failed fixes for the same failure, stop patching and revisit your hypothesis; if it still fails, route to `dev-debug` or report the exact failure.
5. **Report** what changed and where, then `Checks: <commands> — passed after last edit` (or the exact failure) and any check that could not run; a skipped check is not a pass. Add `Concern:` only for a material unresolved risk and `Notice:` only for a worthwhile out-of-scope idea, kept out of the diff. End without a follow-up question.
