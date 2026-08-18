---
name: dev-feature-lite
description: Minimal workflow for straightforward, localized features and changes — inspect, make the smallest correct diff, verify, report. Use for "add", "change", or "fix" requests when the behavior and implementation path are obvious and no design decision or plan is needed.
---

# Simple Feature — Lite

For an obvious change with one clear implementation path. Work directly from the request; process must stay cheaper than the change. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

If inspection reveals unclear product behavior, sequencing or contract alignment across behavioral surfaces, a cross-cutting migration, or material production risk, state why in one line and route to `dev-feature`, `dev-problem-solving`, or `dev-debug`. File count alone is not a reason to escalate.

## 1. Inspect Just Enough

- Read repository instructions, the affected code and tests, and the nearest existing pattern.
- Resolve facts from code and tools instead of asking the user.
- Search before adding a helper or dependency, but do not audit unrelated areas.
- Keep paths outside the repository read-only unless the user explicitly asks to edit them.

Proceed once the requested behavior and smallest affected surface are clear.

## 2. Communicate Only Signal

- Start implementation without presenting a plan or waiting for approval.
- Create a plan or solution Markdown file only when the user explicitly asks for one.
- Raise only material concerns: correctness, security, data loss, compatibility, or production impact. If a safe default exists, state the assumption and continue.
- Ask a critical question only when no safe, correct implementation can proceed without the answer.
- Mention optional improvements as `Notice: <idea and why it matters>`. Do not ask the user to choose, do not request confirmation, and do not include the improvement in the current diff.

## 3. Make the Smallest Complete Change

- Follow the existing local pattern and reuse existing code.
- Add only the code, tests, and user-facing documentation required by the request.
- Avoid unrelated cleanup, speculative options, one-use abstractions, and new dependencies when existing code or the standard library is sufficient.
- Complete the requested behavior without stubs, placeholders, silent scope cuts, weakened tests, or hidden follow-up work.

## 4. Verify and Report

- Run the focused tests and checks covering the touched area; run the standard suite when the repository requires it.
- Fix failures caused by the change. Report pre-existing or unrelated failures without expanding scope.
- Finish concisely: what changed, where, and the exact verification result. Include `Concern:` only for a material unresolved risk and `Notice:` only for a worthwhile out-of-scope improvement. End without a follow-up question.
