---
name: dev-cycle
description: Router for the dev-* development-cycle skill set — picks the right workflow (lite feature, coordinated feature, problem solving, review, testing, debugging, knowledge capture) for the task at hand. Use when starting any development task and unsure which workflow fits, or when the user asks "what dev skills are available" or "how do we work here".
---

# Development Cycle — Router

Pick **one primary workflow** from the table, load that skill (the Skill tool in Claude Code; read its `SKILL.md` elsewhere), and follow it — this router is not a workflow by itself. Each workflow is self-contained: do not open other workflow skills to compare them, and load supporting skills only when the workflow names them.

## Routing

| Situation | Skill |
|---|---|
| Straightforward localized change with an obvious implementation | `dev-feature-lite` |
| Coordinated scoped change where sequencing or contract alignment across behavioral surfaces needs a short in-chat plan | `dev-feature` |
| Open problem, several viable approaches: "how should we…" | `dev-problem-solving` |
| Queue of tasks or plan steps to run unattended: "do tasks 12–15", "execute the plan" | `dev-loop` |
| "Review this / ready to merge?" | `dev-review` |
| Bug resisting the first fix; "still broken", debugger setup | `dev-debug` |
| Writing tests / "how to test this" | `dev-testing` |
| E2E suite against a real stack; network-failure / resilience testing; SDK smoke tests | `dev-e2e-testing` |
| Lesson worth keeping; "remember this"; task start in a repo with `docs/knowledge/` | `dev-knowledge` |
| Writing or reviewing code; simplifying abstractions or comments | `dev-code-style` (supporting skill) |

Ambiguous between lite and coordinated feature work? Start with `dev-feature-lite`; escalate when code inspection finds sequencing or contract alignment across behavioral surfaces, a real design fork, a cross-cutting migration, or material risk. Ambiguous between a coordinated feature and problem-solving? Start with `dev-feature`; it escalates itself when it finds multiple viable architectures.

In every workflow, repository instructions and project-specific skills take precedence over dev-* guidance, and files outside the repository are read-only unless the user confirms an edit.

## Typical Chains

- Simple feature: `dev-feature-lite` with focused verification
- Coordinated feature: `dev-feature` → `dev-review` when the user asks
- Hard problem: `dev-problem-solving` → `dev-loop` (runs the build plan, ends with a review) → `dev-knowledge`
- Several known tasks: `dev-loop`
- Nasty bug: `dev-debug` → `dev-review` (the fix) → `dev-knowledge`
