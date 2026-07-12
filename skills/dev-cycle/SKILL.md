---
name: dev-cycle
description: Router and shared philosophy for the dev-* development-cycle skill set — picks the right workflow (small feature, problem solving, review, testing, debugging, knowledge capture) for the task at hand. Use when starting any development task and unsure which workflow fits, or when the user asks "what dev skills are available" or "how do we work here".
---

# Development Cycle — Router

Pick **one** workflow per task and follow it. Each is a separate skill loaded only when needed — don't load more than the one you're routing to.

## Routing

| Situation | Skill |
|---|---|
| Scoped change, hours of work: "add / change / fix X" | `dev-feature` |
| Open problem, several viable approaches: "how should we…" | `dev-problem-solving` |
| "Review this / ready to merge?" | `dev-review` |
| Bug resisting the first fix; "still broken", debugger setup | `dev-debug` |
| Writing tests / "how to test this" | `dev-testing` |
| Lesson worth keeping; "remember this"; task start in a repo with `docs/knowledge/` | `dev-knowledge` |
| Writing any code (comments discipline) | `dev-code-style` |

Ambiguous between feature and problem-solving? Start with `dev-feature`; it escalates itself when it finds multiple viable architectures.

## Shared Philosophy (applies inside every dev-* skill)

1. **Cheapest sufficient process.** One plan message for a small feature; a 2-page doc only when the approach was genuinely contested. Never produce documents nobody asked for.
2. **KISS / library-first.** An actively maintained library or 2 lines of stdlib beat custom code. No speculative generality.
3. **Ask only forks.** Questions to the user only when the answer changes the diff; batch them; state assumptions instead of asking about defaults.
4. **Evidence over vibes.** Read the code before proposing; reproduce before fixing; capture real API data before mocking.
5. **Second opinions for judgment calls.** Reviews and plans get an independent agent's pass when one is installed (see `dev-review` §4).
6. **Compound.** Check `docs/knowledge/INDEX.md` at task start; leave a note when a lesson was expensive (see `dev-knowledge`).

## Typical Chains

- Small feature: `dev-feature` → (`dev-testing` inline) → `dev-review`
- Hard problem: `dev-problem-solving` → implement via `dev-feature` per step → `dev-review` → `dev-knowledge`
- Nasty bug: `dev-debug` → `dev-review` (the fix) → `dev-knowledge`
