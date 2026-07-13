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
5. **Map the decision tree before asking.** List every decision the problem implies (architecture, data model, edge cases, ops) and order questions so earlier answers constrain later ones. A question whose relevance depends on another answer waits for the next batch — never ask both in one batch and never discover the decision mid-implementation.

## Phase 1b — Experiments (spikes)

When an option's feasibility is uncertain — "is the library fast enough?", "does the API return what we think?" — run a small experiment instead of speculating. Rules:

- **Use the project's stack.** Write the spike in the project's language with its package manager, build tool, and test runner — never switch to Python (or any other language) for convenience. The experiment must answer "how does it behave in *our* stack" — a Python approximation of a TypeScript/Rust question answers a different question. Another language is allowed only when the question itself is language-neutral (e.g. probing an external API's response shape) — and say so explicitly.
- **Isolate in `experiments/<topic>/`** at the repo root. All spike files live there — never scattered through `src/`.
- **Copy, don't mutate.** If the spike needs to modify project files, **copy them into the experiment directory first** and edit the copies; original sources stay untouched. Reuse project code by importing it where the toolchain allows — copy only what must be changed. For a spike that needs the whole project built and modified, use a git worktree instead (`git worktree add ../spike-<topic>`) and throw it away after.
- **Keep it disposable.** A spike has no tests, no error handling, no style requirements — it exists to produce one answer.
- **Never committed by default.** Experiment files do not go to git: add `experiments/` to `.gitignore` the first time you create it (and the spike worktree is outside the repo anyway). Before any commit during or after the experiment, check `git status` — no `experiments/` path may be staged. Committing a spike happens only when the user explicitly asks to keep it, and then to the gitignored path lifted deliberately, not by accident.
- **Harvest, then discard.** Record the outcome (numbers, response samples, "works/doesn't because…") in the Phase 2 options table and later in the solution doc — the conclusion is the artifact, not the code. Delete the experiment directory once conclusions are captured, or leave it gitignored; never let spike code migrate into `src/` by copy-paste — the real implementation is written fresh under `dev-feature` discipline.

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

**Explicitly invite modification** — the user changing option B or adding option D is the point of this phase, not a detour. Iterate until they commit to one. When two options are too close to call on paper, settle it with a spike (Phase 1b) and put the measured result in the table.

## Phase 3 — Solution Doc + Build Plan

Write **one** markdown doc (`docs/solutions/<topic>.md`, or the path the user prefers) — 1–2 pages, not a novel:

```markdown
# <Problem>
## Problem      — 1 paragraph, incl. constraints
## Options considered — the Phase 2 table + why the winner won (1 paragraph)
## Decision     — chosen approach, key design points
## Open questions — questions you can now state precisely but not yet answer;
                  each blocks only its dependent step, not the whole plan
## Build plan   — ordered steps, each independently testable/shippable
                  and sized to fit one fresh agent context;
                  per step: files/areas touched, test strategy (see dev-testing),
                  dependencies (`depends on: step N` or `parallel-ok`), and
                  validation: the exact command that proves the step done
                  (e.g. `pnpm vitest run tests/sync.test.ts`) — a step without
                  a runnable done-check isn't planned yet.
                  Wide refactors get expand–contract sequencing: add the new
                  path first, migrate callers in batches ordered by blast
                  radius, remove the old path last — never one big flip
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

- **Parallel-safe:** steps marked `parallel-ok` that touch **disjoint files/modules** (the plan's "files/areas touched" line is the check). Dispatch them as concurrent agents in one batch; each agent gets its plan step verbatim, the solution doc's Decision section, and the anti-gaming contract: *do not delete, skip, weaken, or narrow tests to reach green; do not refactor unrelated code; do not add dependencies beyond the plan; if blocked, report back instead of working around*.
- **Also parallelize the always-independent work:** writing test scaffolding/mocks for step N+1 while step N is built; research tasks (capturing real API responses per `dev-testing`); documentation-of-record updates.
- **Keep sequential:** steps sharing files or types (unless isolated in git worktrees and merged deliberately), anything touching the same migration chain, and steps whose output changes a later step's design.
- **Join point after each parallel batch:** run each step's validation command, then the full test suite on the merged result — cross-step integration is exactly what parallel agents can't see. A green batch is the checkpoint before dispatching the next one. More autonomy means more review, not less: diff-review each agent's output before merging it.
- Don't force it: for a 3-step plan with a linear dependency chain, sequential is simpler and cheaper. Parallelism pays off from ~2+ genuinely independent steps.

When done, capture lessons via `dev-knowledge` — link the knowledge note to the solution doc.
