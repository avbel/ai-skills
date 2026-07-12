---
name: dev-feature
description: Fast path for small features and changes — clarify only real ambiguities, show a compact plan, implement immediately. No design docs, no ceremony. Use when the user asks to "add", "implement", "change", or "fix" something scoped to hours not days; e.g. "add an endpoint", "add a flag", "support X in Y".
---

# Small Feature — Fast Path

For changes scoped to hours: one plan message, then code. The enemy is ceremony — no design docs, no multi-phase process, no summary documents afterwards. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

**Escalate instead** when the task smells bigger: unknown root cause → `dev-debug`; multiple viable architectures or "how should we..." → `dev-problem-solving`. Say you're escalating and why, in one line.

## Step 1 — Clarify (only if genuinely needed)

Ask **at most 3 questions in one batch**, and only about things that change the implementation:

- Concerns that fork the design: "should this be per-user or global?"
- Tool/library choices when the codebase shows no precedent
- Behavior at a boundary the request doesn't cover: "what happens on duplicate?"

Attach a recommended answer to each question so the user can approve with one word.

Do **not** ask about things you can resolve yourself: facts findable in the codebase (grep, don't ask), existing conventions (read the code), defaults with an obvious answer (state your assumption in the plan instead), or preferences that don't change the diff. If nothing is ambiguous, skip this step entirely.

## Step 2 — Plan (one short message, then go)

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

## Step 3 — Implement, KISS

- **Library first:** if an actively maintained library solves it (recent releases, adoption), use it instead of writing custom code. Check the lockfile first — the project may already depend on something that does the job.
- **1–2 lines beat 20:** if the stdlib or an existing utility in the repo solves it, use that. Do not build abstractions for one call site.
- **Reuse, never copy:** before writing a helper, search the repo for existing code doing the same job. If it exists but is private to another module, **change its visibility or move it to a shared module and import it** — copying it creates two diverging implementations. Refactoring access is always cheaper than a future double-fix.
- **No silent scope cuts:** implement every part of the agreed plan. If a part turns out harder than planned, or you're tempted to leave a `TODO`/stub — **stop and tell the user first**; never commit a TODO, placeholder, or "not implemented" path the user hasn't explicitly approved. The final report must list any approved leftovers under "Deferred", so nothing is dropped silently.
- **No speculative generality:** implement what was asked, not what might be asked next. No config options nobody requested, no interfaces with one implementation.
- Follow existing code patterns in the repo; comment per `dev-code-style`.
- Tests per `dev-testing` — for a small feature that usually means 1–2 integration tests plus the edge cases that apply.

## Step 4 — Finish

- Run the project's tests/linter; fix what you broke.
- Report in a few sentences: what changed, where, test results. **Do not** generate `SUMMARY.md`, `CHANGES.md`, or any doc file unless asked.
- Offer `dev-review` for a review pass; if the solution surprised you (non-obvious pitfall), capture it via `dev-knowledge` — otherwise skip that too.
