---
name: dev-review
description: Review a specified change for completeness, correctness, security, expected load, meaningful tests, and unnecessary complexity. Use for "review this", "review my changes/PR", or "is this ready to merge".
---

# Code Review

Review the requested change and the connected behavior it can break. Correctness, security, data integrity, and compatibility take priority over shortening code. Review-only unless the user asks for fixes.

## 1. Establish Scope and Evidence

- Honor an explicit target first: staged, uncommitted, commit, branch/base, PR, or named files. Unrelated dirty files do not change that target.
- Without a target, use staged + unstaged + untracked changes when dirty. Otherwise use the branch diff from its actual PR/tracking base; if unavailable, resolve `origin/HEAD`, then `main`/`master`. Use merge-base comparison for branch reviews. If the result is empty or the base ambiguous, say so; do not silently review an arbitrary commit.
- For staged/commit/PR reviews, read source at that target revision (index for staged), not a newer working-tree version. Checks run against a different state are explicitly limited evidence; use an isolated snapshot when exact-state execution is needed, preserving user changes.
- Read the diff, then trace changed contracts through callers, callees, types, config, exports, and tests. Expand only where a reachable dependency can affect the result; do not audit the whole repository.
- Establish relevant runtime assumptions from deployment/config/docs: process count, input sizes, trust boundaries, persistence. Label unknowns; do not invent scale requirements.
- Use targeted searches and source ranges. Reuse evidence already in context; inspect the final changed state after fixes. Do not load other review skills merely because they are installed.

## 2. Review the Applicable Risks

**Completeness:** map each requested requirement to behavior. Block silent omissions, unauthorized scope cuts, and stubs for current requirements. A TODO or workaround comment alone is not a defect; verify what remains unimplemented and whether deferral was agreed.

**Correctness and compatibility:** trace inputs to outputs and side effects. Check changed return/error contracts, persisted formats, migrations, partial failures, and affected callers. A local fix must not leave the same root cause reachable elsewhere.

**Security:** every review screens for changed trust boundaries, authorization, secrets, unsafe sinks, and sensitive output. If any applies, load [security details](references/security.md) and trace the relevant flow. Cosmetic changes need no unrelated security audit. Findings need a concrete attack and impact.

**Expected load and failure:** where relevant, check concurrent requests/processes, check-then-write races, retries and duplicate side effects, bounded memory/queues, timeouts, N+1 queries, and input-dependent complexity. Tie a finding to the actual contract or supported operating envelope. A documented limit is acceptable only while that contract fits within it; comments cannot waive correctness or security.

**Tests:** identify changed nontrivial behavior with no check that would fail if it broke. Examine relevant empty/boundary inputs, duplicates/concurrency, dependency failures, and partial state. Existing tests can suffice; do not demand tests for every changed line or every hypothetical combination. Name the missing scenario and its consequence. Load `dev-testing` only when test design or fidelity needs deeper evaluation.

**Embedded languages:** for changed SQL, GraphQL, regex, templates, or shell strings, load [embedded-language checks](references/embedded-languages.md). Host-language typechecks do not establish their validity. Use local/test engines, not production mutations.

**Necessity and readability:** prefer suitable project code, built-ins, and installed dependencies. Report speculative layers/options or duplication only with a concrete simplification and maintenance benefit. Shared meaning and ownership justify reuse; similar syntax alone does not. Preserve useful boundaries, error handling, validation, accessibility, and required documentation. No line-count targets or style-only padding.

**Dead code:** check usages, exports, registration, and dynamic/public consumers before claiming code is unused. Tooling and a green suite are supporting evidence, not proof of unreachability. Never delete code experimentally in the user's working tree during a review. Report uncertainty; remove only within an authorized fix scope.

## 3. Validate Findings and Stop

For each finding confirm the reachable trigger, actual behavior, violated expectation, and smallest sufficient fix. Discard findings disproved by surrounding code. Distinguish hard violations from judgment calls; avoid duplicating compiler/linter findings already reported.

Run checks needed to settle uncertainty and repository-required review checks. Record exact commands/results, including unavailable checks. Reuse unchanged results; after fixes rerun checks of affected behavior. Stop when the scoped risks are resolved, not after an arbitrary number of review passes.

Use separate reviewers only when required or when a large change has independent risk areas worth the extra context cost. Give each the exact scope, contract, relevant paths, and verification evidence rather than the entire conversation. Consolidate duplicate findings and rank by severity. A review of fixes covers changed areas and invalidated assumptions, not a repeat of every completed axis.

When authorized to fix, two failed rounds on the same finding trigger a hypothesis/plan reassessment. Report the evidence and unresolved decision; do not weaken the finding or try a third speculative patch.

## 4. Report

Lead with the verdict and scope. List findings by severity, omitting empty groups:

- **Blocking:** broken requirement, correctness/security/data-loss failure, or failure under supported load.
- **Should fix:** meaningful missing regression coverage or demonstrated maintenance/performance risk.
- **Optional:** only a concrete worthwhile improvement, clearly non-blocking.

Each finding: `file:line — trigger → wrong behavior and impact; smallest fix`. Label debatable design choices as judgment calls. Keep spec gaps, security issues, and missing tests identifiable without duplicating them across sections. End with checks performed and material verification gaps. If nothing is found, say so with the scope and checks; do not imply unrun checks passed.

## Inspiration

[Ponytail review](https://github.com/DietrichGebert/ponytail/blob/main/skills/ponytail-review/SKILL.md) informed connected-code inspection, expected-load reasoning, and evidence-backed findings. This workflow keeps review scope explicit and loads detailed checks only when relevant.
