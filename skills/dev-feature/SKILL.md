---
name: dev-feature
description: Scoped workflow for coordinated features and changes — clarify real ambiguities, show a compact in-chat plan, implement immediately. Use when a change is larger than a localized dev-feature-lite edit but still has one clear architecture, such as an endpoint spanning API, storage, and tests.
---

# Coordinated Feature — Fast Path

For coordinated changes scoped to hours: one in-chat plan, then code. The enemy is ceremony — no design docs, no multi-phase process, no summary documents afterwards. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

**Downgrade instead** to `dev-feature-lite` when the behavior and implementation path are obvious and the change can proceed without a plan or user decision.

**Escalate instead** when the task smells bigger: unknown root cause → `dev-debug`; multiple viable architectures or "how should we..." → `dev-problem-solving`. Say you're escalating and why, in one line.

## Step 1 — Clarify (only if genuinely needed)

Ask **at most 3 questions in one batch**, and only about things that change the implementation:

- Concerns that fork the design: "should this be per-user or global?"
- Tool/library choices when the codebase shows no precedent
- Behavior at a boundary the request doesn't cover: "what happens on duplicate?"

Attach a recommended answer to each question so the user can approve with one word.

Do **not** ask about things you can resolve yourself: facts findable in the codebase (grep, don't ask), existing conventions (read the code), defaults with an obvious answer (state your assumption in the plan instead), or preferences that don't change the diff. If nothing is ambiguous, skip this step entirely.

## Step 2 — Plan (one short in-chat message, then go)

Check the project knowledge base first if one exists (`docs/knowledge/` — see `dev-knowledge`): a past lesson may already cover the exact pitfall.

Present a compact plan and **proceed straight to implementation** — the plan is a courtesy heads-up the user can interrupt, not a gate to wait on (unless the user or their setup requires plan approval):

```
Plan: <one-line goal>
- <change 1 — file/area>
- <change 2>
- Tests: <what will be covered — see dev-testing>
Assumptions: <anything you decided instead of asking>
```

Keep it under ~10 lines. No alternatives-considered section, no risk matrix — that's `dev-problem-solving` territory.

Keep this plan in the conversation. Create a plan or solution Markdown file only when the user explicitly asks for one.

## Step 3 — Implement, KISS

- **Use what fits already:** inspect project utilities, standard-library/native features, and installed dependencies before writing custom code or adding a package. Choose by required behavior and maintenance cost, not popularity or line count alone.
- **Direct code first:** keep short, clear logic local. Extract a helper or introduce an interface only when it removes current complexity, centralizes a shared rule, or serves a real boundary. A single caller is neither a ban nor a reason to abstract.
- **Reuse with boundaries:** search for existing equivalents. Share code when semantics and ownership align; do not widen a private API or couple unrelated modules solely to eliminate similar lines. Follow `dev-code-style` for the decision criteria.
- **No silent scope cuts:** implement every part of the agreed plan. If a part turns out harder than planned, or you're tempted to leave a `TODO`/stub — **stop and tell the user first**; never commit a TODO, placeholder, or "not implemented" path the user hasn't explicitly approved. The final report must list any approved leftovers under "Deferred", so nothing is dropped silently.
- **No speculative generality:** implement what was asked, not what might be asked next. No unused configuration, extension points, pass-through layers, or scaffolding for future implementations.
- **Out-of-project files are read-only:** paths the user gave as samples or references that resolve outside the repo root are inputs, never targets — copy what you need into the project and adapt the copy. Editing anything outside the repo requires explicit user confirmation first.
- Use precise names and readable control flow per `dev-code-style`; skip obvious comments and keep necessary rationale brief and beside the relevant code. Preserve required docs, safety invariants, and directives.
- Tests per `dev-testing` — for a small feature that usually means 1–2 integration tests plus the edge cases that apply.

## Step 4 — Finish

- Review the diff for unnecessary layers, speculative code, and comment narration. Simplify within scope while preserving the full contract and meaningful tests; do not compress readable code into clever one-liners.
- Run the project's tests/linter; fix what you broke. **Never delete, skip, weaken, or narrow a test to get green** — a test blocking you is a finding to raise with the user, not an obstacle to remove. Equally: no unrelated refactors, no dependencies beyond the plan — green via scope discipline, not via gaming the signal.
- Report in a few sentences: what changed, where, test results. **Do not** generate `SUMMARY.md`, `CHANGES.md`, or any doc file unless asked.
- Offer `dev-review` for a review pass; if the solution surprised you (non-obvious pitfall), capture it via `dev-knowledge` — otherwise skip that too.
