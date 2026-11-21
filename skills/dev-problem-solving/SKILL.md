---
name: dev-problem-solving
description: Structured problem solving for non-trivial problems — gather data, brainstorm approaches, present options the user can pick/modify/extend, produce a solution doc + build plan, then review the plan. Use when a problem or goal has multiple viable solutions, the user says "how should we", "let's brainstorm", or brings their own ideas to evaluate.
---

# Problem Solving — Brainstorm → Decide → Plan → Review

For problems where the *approach* is the hard part. The output is a decision the user owns, a short solution doc, and a reviewed build plan. Part of the `dev-*` development-cycle skill set.

**Downgrade** to `dev-feature` if, after Phase 1, only one sensible approach exists — say so in one line and switch. Don't manufacture alternatives for a solved problem.

## Phase 1 — Understand and Collect Data

1. Restate the problem in one paragraph: current behavior, desired behavior, constraints (perf, compat, deadline, team preferences). Confirm you got it right.
2. If the user brought their own ideas, **treat them as first-class candidates** — they enter Phase 2 alongside yours, evaluated by the same criteria, listed first.
3. Gather evidence before opinions:
   - Codebase: how the affected area works today, existing patterns/utilities that constrain or help
   - Configured memory/knowledge store (see `dev-knowledge`): retrieve only relevant prior decisions; do not create or read a parallel store by default.
   - Externals when relevant: library options and their maintenance state, prior art, known pitfalls (web search)
4. Ask the questions that change the answer — requirements you can't infer, tolerance for new dependencies, operational constraints. Two rules: **facts are looked up, decisions are asked** — if the codebase or docs can answer it, grep instead of asking; and **every question ships with a recommended answer** so the user can just say "yes" or push back on something concrete. Batch the questions; don't drip-feed.
5. **Map the decision tree before asking.** List every decision the problem implies (architecture, data model, edge cases, ops) and order questions so earlier answers constrain later ones. A question whose relevance depends on another answer waits for the next batch — never ask both in one batch and never discover the decision mid-implementation.

## Phase 1b — Experiments (spikes)

When an option's feasibility is uncertain — "is the library fast enough?", "does the API return what we think?" — run a small experiment instead of speculating. Rules:

- **Use the project's stack.** Write the spike in the project's language with its package manager, build tool, and test runner — never switch to Python (or any other language) for convenience. The experiment must answer "how does it behave in *our* stack" — a Python approximation of a TypeScript/Rust question answers a different question. Another language is allowed only when the question itself is language-neutral (e.g. probing an external API's response shape) — and say so explicitly.
- **Isolate in `experiments/<topic>/`** at the repo root. All spike files live there — never scattered through `src/`.
- **Copy, don't mutate.** If the spike needs to modify project files, **copy them into the experiment directory first** and edit the copies; original sources stay untouched. Reuse project code by importing it where the toolchain allows — copy only what must be changed. For a spike that needs the whole project built and modified, use a git worktree instead (`git worktree add ../spike-<topic>`) and throw it away after.
- **Keep it disposable and bounded.** Define the question, smallest experiment, success/failure signal, and time or attempt budget first. Stop once the evidence decides the option. Skip production scaffolding, but retain validation, credential protection, cleanup, and reliable exit status; experiments must not mutate live state without authorization.
- **Never committed by default.** Experiment files do not go to git: add `experiments/` to `.gitignore` the first time you create it (and the spike worktree is outside the repo anyway). Before any commit during or after the experiment, check `git status` — no `experiments/` path may be staged. Committing a spike happens only when the user explicitly asks to keep it, and then to the gitignored path lifted deliberately, not by accident.
- **Harvest, then discard.** Record the outcome (numbers, response samples, "works/doesn't because…") in the Phase 2 options table and later in the solution doc — the conclusion is the artifact, not the code. Delete the experiment directory once conclusions are captured, or leave it gitignored; never let spike code migrate into `src/` by copy-paste — the real implementation is written fresh under `dev-feature` discipline.

## Phase 2 — Brainstorm From Different Angles

Generate **2–4 genuinely distinct approaches** (not one approach with three knob settings). Force different angles:

- *Minimal:* smallest complete change using existing code, standard-library/native features, or installed dependencies — always include this one
- *Library:* an actively maintained off-the-shelf solution
- *Structural:* fix the design so the problem class disappears
- *Contrarian:* question the premise — is the stated problem the real problem? (include only when the premise is genuinely questionable)

Judge maintenance by the concepts, dependencies, and boundaries a reader must understand. State what current need justifies each proposed abstraction; future flexibility alone is insufficient. Prefer the direct option when it meets the same contract. Keep useful boundaries and safeguards even when they take more lines (see `dev-code-style`).

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
                  dependencies (`depends on: step N`), and
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

1. **Self-review adversarially:** What breaks mid-rollout if we stop after step 2? What does this assume about load/data shape that nobody verified? Which step is secretly two steps? Which helper, interface, option, or dependency can be omitted without weakening the chosen solution?
2. Fold findings into the doc, show the user the delta, get the go-ahead.

## Phase 5 — Build

Run the build plan with `dev-loop`: the plan's steps are its queue, each step's validation command is its done-check, and the solution doc's Decision section goes into every brief. `dev-loop` owns model choice, fix-round caps, and checks. Extended design rationale stays in the solution doc. One plan-specific rule goes into the dev-loop ledger's Rules line:

- **A step that dev-loop leaves blocked — done-check still failing or a Blocking finding open after the escalation round — stops the plan, not just the step:** the plan's assumption about that step is wrong. Report what each attempt changed and why it failed, then settle it with the user: split the step, revisit the Decision section, or drop it and record why.

When done, capture lessons via `dev-knowledge` — link the knowledge note to the solution doc.
