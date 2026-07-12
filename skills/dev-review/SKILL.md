---
name: dev-review
description: Orchestrated code review — production checklist, edge-case test coverage audit, and a second opinion from another AI agent (Gemini/Codex) when available. Use when the user says "review this", "review my changes/PR", "is this ready to merge", or before merging work from dev-feature or dev-problem-solving.
---

# Code Review (Orchestrated)

A review pass that combines three lenses: the production checklist, a test-coverage audit, and — when another agent is installed — an independent second opinion. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

## Workflow

### 1. Scope the diff

- Dirty working tree → review staged + unstaged + untracked.
- Clean tree → review the branch diff against the base (`origin/HEAD` → `main` → `master`).
- Read surrounding code (callers, types, existing tests) — never review a diff in isolation.

### 2. First-party review

**Spec compliance first, quality second.** If a plan or solution doc exists for this change (`docs/solutions/`, a `dev-feature` plan message, an issue), first check the diff actually does what was agreed — missing steps and silent scope changes are the highest-value findings. Then review quality.

Apply the production checklist from the `code-review` skill if installed (observability, backward compatibility, migrations, idempotency/concurrency/timeouts, PR quality). Otherwise cover at minimum: correctness, error handling, silent failure paths, backward compatibility of anything another system consumes, and migration safety.

Also check style: comment noise and density per `dev-code-style`.

### 3. Edge-case test audit

For every new or changed code path, check the diff's tests against the edge-case checklist in `dev-testing` (empty/null input, boundaries, duplicate/concurrent calls, dependency failures, partial failure). Report **which specific edge cases have no test**, as a short list — e.g. "no test for the 429 path in `syncUsers`". Missing edge-case tests are findings, same as bugs.

### 4. Second opinion (when available)

An independent reviewer catches blind spots the authoring agent shares with itself. Check for installed cross-agent review paths, in order:

1. `gemini-review-code` skill → `bash ~/.claude/skills/gemini-review-code/scripts/review.sh` (add `--adversarial` for risky changes)
2. Codex CLI on PATH → `codex review` / a non-interactive `codex exec` review of the diff
3. OpenCode / Gemini CLI on PATH → non-interactive review prompt with the diff

Run **one** second-opinion pass, not all of them. If none is available, say so in the verdict ("no second opinion available") — don't silently skip. If the second reviewer contradicts your finding, present both views; don't suppress either.

### 5. Verdict

Present results in this order, most severe first:

```
## Review: <scope, N files>

### Blocking
- file.ts:42 — <issue, why it breaks, suggested fix>

### Should fix
- ...

### Missing edge-case tests
- <path> — no test for <case>

### Second opinion (<agent> | none available)
- <agreements / new findings / disagreements>

Verdict: ready to merge | needs changes
```

## Rules

- Review-only by default: report findings, let the user decide. Fix only when explicitly asked ("review and fix").
- No nitpick padding — if formatting is linter-enforced, don't comment on it. Fewer, higher-confidence findings beat exhaustive noise.
- Every blocking finding needs a concrete failure scenario ("when X happens, Y breaks"), not a vibe.
- For self-authored code (you wrote the diff earlier in the session), always prefer the second opinion step — you share blind spots with yourself.
