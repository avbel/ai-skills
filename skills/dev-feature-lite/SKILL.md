---
name: dev-feature-lite
description: Minimal workflow for straightforward, localized features and changes. Use for "add", "change", or "fix" requests when the behavior and implementation path are obvious and no design decision or plan is needed.
---

# Simple Feature — Lite

For an obvious change with one clear implementation path. Work directly from the request; process must stay cheaper than the change. This file is the whole workflow: load no other `dev-*` skill unless you escalate below, and run no review, second opinion, or reviewer subagent unless the user or the repository's instructions ask for one.

If inspection reveals unclear product behavior, sequencing or contract alignment across behavioral surfaces, a cross-cutting migration, or material production risk — state why in one line and route to `dev-feature`, `dev-problem-solving`, or `dev-debug`. File count alone is not a reason to escalate.

## 1. Inspect Just Enough

Read repository instructions, the affected code and tests, and the nearest existing pattern. Locate code with targeted search and read the relevant ranges rather than whole files; batch independent searches and reads into one turn, and don't re-read what is already in context. Get facts from code and tools, not the user. Paths outside the repository stay read-only unless the user explicitly asks. Before editing, trace the changed contract to its callers, exports, config, fixtures, and tests; include only surfaces affected by that contract. Proceed once the requested behavior and smallest complete change are clear.

## 2. Communicate Only Signal

Implement without presenting a plan or awaiting approval. Raise only material concerns (correctness, security, data loss, compatibility, production impact); given a safe default, state the assumption and continue. Ask only when no safe, correct implementation can proceed without the answer. Optional improvements: `Notice: <idea and why it matters>` — offer no choices, seek no confirmation, keep them out of the current diff.

## 3. Make the Smallest Complete Change

Follow the local pattern; reuse suitable project code, standard-library/native features, and installed dependencies. Add only the code, tests, and user-facing docs the request requires — no unrelated cleanup, speculative options, forwarding wrappers, or new packages where existing capabilities suffice. Extract only for a current shared rule, meaningful boundary, or clearer complex operation; leave obvious logic inline. Deliver the full behavior: no stubs, placeholders, silent scope cuts, weakened tests, or hidden follow-up work.

Use precise names and straightforward control flow, without packing logic into dense one-liners. Skip comments on obvious code; keep only brief rationale or constraints beside the code that needs them, plus required docs and directives.

## 4. Verify and Report

For a bug fix, reproduce the failure before editing and retain a regression check. For new nontrivial behavior, add or extend the smallest test at a stable seam that would fail if that behavior broke; existing tests suffice if they already prove it. Trivial edits need no new test. Preserve validation, data-loss handling, security, and accessibility.

Iterate with focused tests and checks on the touched area; after a fix, rerun the failed check and any checks invalidated by the fix, then run repository-required checks on the final state. Stop when the requested behavior and required checks pass; expand testing only for a new failure, change, or unresolved risk. Keep output quiet (summary reporter or the failure tail) and give long commands enough timeout to finish in one call instead of polling. Fix failures the change caused; report pre-existing or unrelated ones without expanding scope. Report: what changed, where, exact verification result, and material checks that could not run. A skipped check is not a pass. `Concern:` only for a material unresolved risk; `Notice:` only for a worthwhile out-of-scope improvement. End without a follow-up question.
