---
name: dev-cycle
description: Router and shared philosophy for the dev-* development-cycle skill set — picks the right workflow (lite feature, coordinated feature, problem solving, review, testing, debugging, knowledge capture) for the task at hand. Use when starting any development task and unsure which workflow fits, or when the user asks "what dev skills are available" or "how do we work here".
---

# Development Cycle — Router

Pick **one primary workflow** per task and follow it. Load supporting skills only when needed; `dev-code-style` supplies the shared code and comment guidance for implementation and review.

## Routing

| Situation | Skill |
|---|---|
| Straightforward localized change with an obvious implementation | `dev-feature-lite` |
| Coordinated scoped change where sequencing or contract alignment across behavioral surfaces needs a short in-chat plan | `dev-feature` |
| Open problem, several viable approaches: "how should we…" | `dev-problem-solving` |
| "Review this / ready to merge?" | `dev-review` |
| Bug resisting the first fix; "still broken", debugger setup | `dev-debug` |
| Writing tests / "how to test this" | `dev-testing` |
| E2E suite against a real stack; network-failure / resilience testing; SDK smoke tests | `dev-e2e-testing` |
| Lesson worth keeping; "remember this"; task start in a repo with `docs/knowledge/` | `dev-knowledge` |
| Writing or reviewing code; simplifying abstractions or comments | `dev-code-style` (supporting skill) |

Ambiguous between lite and coordinated feature work? Start with `dev-feature-lite`; escalate when code inspection finds sequencing or contract alignment across behavioral surfaces, a real design fork, a cross-cutting migration, or material risk. Ambiguous between a coordinated feature and problem-solving? Start with `dev-feature`; it escalates itself when it finds multiple viable architectures.

## Shared Philosophy (applies inside every dev-* skill)

1. **Cheapest sufficient process.** No plan for an obvious localized change; one in-chat plan for a coordinated feature. Neither feature workflow persists a planning document unless the user asks; deeper problem-solving follows its own solution-doc contract.
2. **Small, readable implementation.** Reuse suitable project code, standard-library/native capabilities, or installed dependencies before adding custom machinery. Add abstractions only for current needs; use clear names and direct control flow, with brief comments only for context the code cannot express (see `dev-code-style`). Preserve the complete behavior and necessary safeguards; fewer lines alone is not success.
3. **Ask only blockers and real forks.** Resolve facts from code, state safe assumptions, and never turn optional improvements into approval requests.
4. **Evidence over vibes.** Read the code before proposing; reproduce before fixing; capture real API data before mocking.
5. **Second opinions for judgment calls.** Reviews and plans get an independent agent's pass when one is installed (see `dev-review` §4).
6. **Compound.** Check `docs/knowledge/INDEX.md` at task start; leave a note when a lesson was expensive (see `dev-knowledge`).
7. **Files outside the project are read-only.** When the user attaches or points to a path outside the repo root (a sample, a reference implementation, a config from another project) — read it, quote it, copy it into the project if it's needed as a starting point, but **never edit the original**. If a task seems to require changing an out-of-project file, stop and confirm with the user first.

## Typical Chains

- Simple feature: `dev-feature-lite` with focused verification
- Coordinated feature: `dev-feature` → (`dev-testing` inline) → `dev-review`
- Hard problem: `dev-problem-solving` → build (parallel agents for independent steps) → `dev-review` → `dev-knowledge`
- Nasty bug: `dev-debug` → `dev-review` (the fix) → `dev-knowledge`
