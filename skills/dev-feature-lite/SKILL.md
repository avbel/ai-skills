---
name: dev-feature-lite
description: Minimal workflow for straightforward, localized features and changes. Use for "add", "change", or "fix" requests when the behavior and implementation path are obvious and no design decision or plan is needed.
---

# Simple Feature — Lite

For an obvious change with one clear implementation path. Work directly from the request; process must stay cheaper than the change. Part of the `dev-*` skill set (see `dev-cycle`).

If inspection reveals unclear product behavior, sequencing or contract alignment across behavioral surfaces, a cross-cutting migration, or material production risk — state why in one line and route to `dev-feature`, `dev-problem-solving`, or `dev-debug`. File count alone is not a reason to escalate.

## 1. Inspect Just Enough

Read repository instructions, the affected code and tests, and the nearest existing pattern. Get facts from code and tools, not the user. Search before adding a helper or dependency; skip unrelated areas. Paths outside the repository stay read-only unless the user explicitly asks. Proceed once the requested behavior and smallest affected surface are clear.

## 2. Communicate Only Signal

Implement without presenting a plan or awaiting approval. Raise only material concerns (correctness, security, data loss, compatibility, production impact); given a safe default, state the assumption and continue. Ask only when no safe, correct implementation can proceed without the answer. Optional improvements: `Notice: <idea and why it matters>` — offer no choices, seek no confirmation, keep them out of the current diff.

## 3. Make the Smallest Complete Change

Follow the local pattern; reuse existing code. Add only the code, tests, and user-facing docs the request requires — no unrelated cleanup, speculative options, one-use abstractions, or new dependencies where existing code or the standard library suffices. Deliver the full behavior: no stubs, placeholders, silent scope cuts, weakened tests, or hidden follow-up work.

## 4. Verify and Report

Run focused tests and checks on the touched area, plus the standard suite when the repository requires it. Fix failures the change caused; report pre-existing or unrelated ones without expanding scope. Report: what changed, where, exact verification result. `Concern:` only for a material unresolved risk; `Notice:` only for a worthwhile out-of-scope improvement. End without a follow-up question.
