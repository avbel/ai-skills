---
name: dev-loop
description: Work through a queue of development tasks unattended — a fresh worker per task, verification, risk-based review, capped fix rounds, progress kept in an on-disk ledger — until the queue is done. Use for "do tasks 12, 14 and 15", "execute the build plan", "work through these issues", "keep going until all are done". Not for recurring schedules.
---

# Dev Loop — Work Through a Task Queue

Execute a queue of tasks — a user list, a plan's build steps, or issues from a tracker the project's skills can read — without check-ins between tasks. Cost grows with context size and turn count, so the controller stays small: tasks run in fresh workers, artifacts move as files, and progress lives in a ledger instead of conversation memory. Repository instructions and user rules (commits, branches, model choice) override this file.

## Setup

1. **Queue.** Read the tasks once. Each needs a done-check — a test, command, or observable behavior; write a one-line done-check for any that lacks one. Before the loop starts, ask in one batch every question that blocks a done-check, plus "commit per task?" when the queue has more than 3 tasks and the user has not said. After that, run unattended.
2. **Tree.** Run `git status --short` once. Pre-existing changes are off-limits: workers do not edit, stage, or revert them, and reviews exclude them. If they overlap files the queue will touch, add that to the question batch.
3. **Ledger.** Keep it at `.dev-loop/ledger.md` in the repository root, out of git: append `.dev-loop/` to the file `git rev-parse --git-path info/exclude` prints, or keep it out of every commit when that file is not writable. A ledger for the same queue source means resume: read it and `git log --oneline <BASE>..`, skip tasks marked complete, and continue an unfinished task from the current tree with its notes file and recorded round. A ledger for a different queue: ask before replacing it. Start a new ledger with:

   ```
   # dev-loop ledger — <queue source>
   BASE <sha> · commits: per-task | none · off-limits: <paths or none>
   Rules: 2 fix rounds + 1 escalation round per task; an open Blocking finding blocks the task; pause only for the stop conditions; never weaken tests; update this file before each next step.
   ```

   Copy any extra rules the queue source sets (for example, a build plan that stops when a step stays blocked) into the Rules line. After compaction or resume, reread this skill once, then trust the ledger and `git log` over memory.
4. **Commits decide review cadence.** Commit per task only if the user authorized commits for this loop, following repository and user rules for how commits are made; then tasks that trigger review (Per Task, step 3) get a per-task review. Without commits, only the final review runs. Never create branches, push, or merge unless the user asked.
5. **Mode.** Tasks run one at a time.
   - **Inline** — at most 3 tasks that `dev-feature-lite` covers and none in a review area (Per Task, step 3), or no subagent tool: do each task in this session under `dev-feature-lite` (`dev-feature` if the task needs a plan) and record its ledger line.
   - **Delegated** — otherwise: one fresh worker per task.

   Parallel workers need isolated worktrees and an integration step this skill does not define; run them only when the user explicitly asks, and then run the required checks on the combined result.

## Model per Role

Set each worker's model explicitly whenever an omitted one would inherit the session's, which is often the most expensive. A model the user named for a role overrides this.

- **Implementer:** the standard mid-tier model. Use the cheapest tier only when the brief contains the complete change: cheap tiers take more turns on multi-step work, and turns cost more than the per-token price saves.
- **Reviewer:** scaled to the diff's risk — mid-tier for routine diffs, the strongest available for concurrency, security, or data-migration changes.
- **Escalation round and design-judgment tasks:** the strongest available model.

## Per Task

1. **Brief.** Record `Task <N>: base <git rev-parse HEAD>` in the ledger, then dispatch this, with nothing from earlier tasks except the interfaces and decisions this task depends on:

   ```
   Task <N>/<M>: <title> — <one line on where it fits>
   Requirements: <task text or path>; done-check: <command or behavior>
   Depends on: <interfaces/decisions from earlier tasks, if any>
   Off-limits paths: <pre-existing changes, or none>
   Commit: no | yes — commit when done per <commit rules>; stage only this task's paths, never .dev-loop/
   Load dev-feature-lite (dev-feature if the task needs a plan) and follow it, with these overrides:
   - Wherever it says to ask or tell the user, or to escalate to dev-problem-solving, stop and return
     NEEDS_DECISION with the question and a recommended answer. Switching to dev-feature is fine.
   - If checks still fail after two fix attempts, return BLOCKED with the exact failure and the paths you
     changed. With Commit: yes, restore them to the task base and delete files you created; otherwise
     leave them as they are — never git checkout or git restore a path, which would wipe earlier tasks.
   - Do not spawn subagents or reviewers. Do not push or branch.
   - Write full notes to <absolute repo path>/.dev-loop/task-<N>.md. Return only the contract below;
     it replaces the workflow's report.
   Return at most 10 lines: STATUS (DONE | DONE_WITH_CONCERNS | NEEDS_DECISION | BLOCKED), changed paths,
   Risk: none | contract | persistence | auth | concurrency, "Checks: <commands> — passed after last edit",
   concerns or the question.
   ```

2. **Handle the result.**
   - **DONE / DONE_WITH_CONCERNS:** when the done-check is a single command, run it yourself once; a failure goes back to the worker as a fix round. Concerns go to the ledger.
   - **NEEDS_DECISION:** unless the question hits a stop condition, decide — from the spec, plan, or code when they settle it, otherwise by taking the worker's recommended answer — record `Ruling: <decision> — <why> — <cost if wrong>`, and resume the worker.
   - **BLOCKED:** retry once with the missing context; if still blocked, mark the task blocked with the paths it left changed, continue with tasks that neither depend on it nor touch those paths, and report it at the end.
3. **Review** (per-task commits only) when the task is in a review area — it changes a public contract, a persisted format or migration, authentication or another trust boundary, or concurrency (the worker's Risk field; in inline mode, your own judgment) — or `git diff --shortstat <task base>..HEAD` exceeds ~300 changed lines; leave other tasks to the final review. Write `git diff --stat --patch <task base>..HEAD` to `.dev-loop/task-<N>.diff` — never diff from `HEAD~1`, which drops earlier commits of a multi-commit task — and give the reviewer that path, the requirements, the worker's `Checks:` line, and the instruction to load `dev-review`. The reviewer does not rerun checks the worker reported. Blocking and Should-fix findings enter the fix loop; Optional findings go to the ledger.
4. **Fix loop.** A round is one fix plus a re-review of the fix diff only; record `Task <N>: round <K> from <sha>` in the ledger, where the sha is the head the previous review saw. Resume the same worker with the findings verbatim (or start a fresh one with the notes file when the harness cannot resume). After 2 rounds with findings still open, run one round with a fresh worker on the strongest available model, given the notes file. After that, an open Blocking finding marks the task blocked, and each open Should-fix finding is parked as `Parked — <finding> — <why deferring is safe>`. When later tasks build on a parked finding, rule the smallest unblocking change and carry it into their briefs. In delegated mode never fix code in the controller, and never drop a finding without a ledger entry.
5. **Record** `Task <N>: complete (<commits or changed paths>; review clean | <K> parked | final only) Checks: <...>` before dispatching the next task.

## Stop Conditions — the Only Reasons to Pause

Ask the user only before an irreversible or destructive operation; a security-sensitive action (credentials, production data, permissions); a side effect outside the repository the user has not authorized (push, merge, publish, deploy, paid API calls); when a defect leaves every path forward a guess; when two consecutive tasks are blocked for the same cause, such as a broken environment; or when a rule copied from the queue source says to stop. Everything else is a ruling recorded in the ledger. A scope cut or stub is never a ruling: mark the task `Deferred` with the reason, continue with tasks that do not depend on it, and raise it in the final report. Never delete, skip, or weaken tests to get green.

## Context Hygiene

- Hand artifacts over as file paths; never paste diffs, logs, or earlier task history into a brief.
- Wait for worker completion notifications instead of polling. If the harness requires explicit waiting, wait in stretches of several minutes with one status line between them.
- Between tasks, write at most one status line — no progress summaries or "should I continue?" prompts.

## Finish

1. **Final review** — in delegated mode always; in inline mode only when a task was in a review area (Per Task, step 3) or the user asked. Run one `dev-review` of BASE..HEAD, or without commits of the working tree against BASE excluding off-limits paths; pass the reviewer `git status --short` so it also reads the files the tasks created, and stage nothing. Use the reviewer tier for the riskiest change, and give it the ledger's parked and Optional items. Send its Blocking and Should-fix findings to one worker as a single fix wave (in inline mode, fix them yourself).
2. **Checks:** run the repository-required checks once on the final state, reusing a passing run when nothing has changed since. If they fail, run one fix wave for the failures, then report whatever still fails.
3. **Report:** tasks complete, deferred, blocked, and parked with their rulings; `Checks: <commands> — passed after last edit`; anything that needs the user. Delete `.dev-loop/` unless tasks remain — blocked and deferred ones count — or the user wants it kept.
