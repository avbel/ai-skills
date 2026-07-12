---
name: dev-problem-solving
description: Structured problem solving for non-trivial problems — gather data, brainstorm approaches from different angles, present options the user can pick/modify/extend, produce a solution doc + build plan, then review the plan. Use when the user describes a problem or goal with multiple viable solutions, says "how should we", "I have a problem with", "let's brainstorm", or brings their own solution ideas to evaluate.
---

# Problem Solving — Brainstorm → Decide → Plan → Review

For problems where the *approach* is the hard part. The output is a decision the user owns, a short solution doc, and a reviewed build plan. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

**Downgrade** to `dev-feature` if, after Phase 1, only one sensible approach exists — say so in one line and switch. Don't manufacture alternatives for a solved problem.

## Phase 1 — Understand and Collect Data

1. Restate the problem in one paragraph: current behavior, desired behavior, constraints (perf, compat, deadline, team preferences). Confirm you got it right.
2. If the user brought their own ideas, **treat them as first-class candidates** — they enter Phase 2 alongside yours, evaluated by the same criteria, listed first.
3. Gather evidence before opinions:
   - Codebase: how the affected area works today, existing patterns/utilities that constrain or help
   - Project knowledge base (`docs/knowledge/` — see `dev-knowledge`): has this or a similar problem been solved here before?
   - Externals when relevant: library options and their maintenance state, prior art, known pitfalls (web search)
4. Ask the questions that change the answer — requirements you can't infer, tolerance for new dependencies, operational constraints. Two rules: **facts are looked up, decisions are asked** — if the codebase or docs can answer it, grep instead of asking; and **every question ships with a recommended answer** so the user can just say "yes" or push back on something concrete. Batch the questions; don't drip-feed.

## Phase 2 — Brainstorm From Different Angles

Generate **2–4 genuinely distinct approaches** (not one approach with three knob settings). Force different angles:

- *Minimal:* smallest change that solves it — always include this one
- *Library:* an actively maintained off-the-shelf solution
- *Structural:* fix the design so the problem class disappears
- *Contrarian:* question the premise — is the stated problem the real problem? (include only when the premise is genuinely questionable)

Present as a compact comparison the user can react to:

```
### Options
A. <user's idea, if any> — <essence>
B. <minimal> — <essence>
C. ...

| | effort | risk | maintenance | notes |
|A| ...    | ...  | ...         | <one line> |

Recommendation: <one option + 2–3 sentences why>
Pick one, mix them, or tell me a direction I've missed.
```

**Explicitly invite modification** — the user changing option B or adding option D is the point of this phase, not a detour. Iterate until they commit to one.

## Phase 3 — Solution Doc + Build Plan

Write **one** markdown doc (`docs/solutions/<topic>.md`, or the path the user prefers) — 1–2 pages, not a novel:

```markdown
# <Problem>
## Problem      — 1 paragraph, incl. constraints
## Options considered — the Phase 2 table + why the winner won (1 paragraph)
## Decision     — chosen approach, key design points
## Build plan   — ordered steps, each independently testable/shippable;
                  per step: files/areas touched, test strategy (see dev-testing),
                  and dependencies: `depends on: step N` or `parallel-ok`
## Risks        — top 2–3 with mitigations. No filler.
```

This doc is the only document produced — the implementation itself follows `dev-feature` discipline (no extra summaries).

## Phase 4 — Review the Plan

Before implementing, review the build plan — plans are cheapest to fix now:

1. **Second opinion when available** (same discovery order as `dev-review`): pass the doc to `gemini-review-code`-style / Codex / Gemini CLI with "find holes in this plan: missed cases, ordering problems, hidden risks, simpler alternatives".
2. **Self-review otherwise**, adversarially: What breaks mid-rollout if we stop after step 2? What does this assume about load/data shape that nobody verified? Which step is secretly two steps?
3. Fold findings into the doc, show the user the delta, get the go-ahead.

## Phase 5 — Build (parallelize where the plan allows)

Implement per `dev-feature` discipline for each step, and **fan out independent steps to parallel subagents** instead of running them sequentially — that's why the plan marks dependencies:

- **Parallel-safe:** steps marked `parallel-ok` that touch **disjoint files/modules** (the plan's "files/areas touched" line is the check). Dispatch them as concurrent agents in one batch; each agent gets its plan step verbatim plus the solution doc's Decision section — enough context to work without re-exploring.
- **Also parallelize the always-independent work:** writing test scaffolding/mocks for step N+1 while step N is built; research tasks (capturing real API responses per `dev-testing`); documentation-of-record updates.
- **Keep sequential:** steps sharing files or types (unless isolated in git worktrees and merged deliberately), anything touching the same migration chain, and steps whose output changes a later step's design.
- **Join point after each parallel batch:** run the full test suite on the merged result, not just per-agent tests — cross-step integration is exactly what parallel agents can't see. A green batch is the checkpoint before dispatching the next one.
- Don't force it: for a 3-step plan with a linear dependency chain, sequential is simpler and cheaper. Parallelism pays off from ~2+ genuinely independent steps.

When done, capture lessons via `dev-knowledge` — link the knowledge note to the solution doc.
