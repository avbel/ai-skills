---
name: dev-code-style
description: Compact, readable code with justified abstractions and sparse, purposeful comments. Use when writing, editing, or reviewing source code, or when the user asks to simplify code, avoid overengineering, or remove comment noise.
---

# Code Style — Compact and Readable

Write only what the task needs, with names and control flow a reader can understand directly. Compactness comes from removing unnecessary concepts and indirection; keep normal formatting and useful intermediate variables. Code explains **what**; comments preserve context the code cannot express.
Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

## Before Adding Code

Read the affected flow and its callers, then choose the simplest implementation that meets the actual contract:

1. Reuse suitable code already in the project when its semantics and module boundary fit.
2. Prefer standard-library or native platform capabilities when they cover the required behavior.
3. Use an installed dependency when it fits better; add a dependency only when its benefit justifies the ongoing cost.
4. Otherwise write the small, direct implementation. Omit speculative options, extension points, and scaffolding.

Preserve requested behavior, validation at trust boundaries, necessary error handling, security, accessibility, and meaningful tests. A shorter diff that leaves the root cause or a requirement unresolved is incomplete.

## Make the Code Explain Itself

- Use domain names and explicit units: `timeoutMs` needs no "timeout in milliseconds" comment. Avoid vague names such as `data` or `manager` when a more precise name fits.
- Keep related logic together, with straightforward branches and early returns where they help. Prefer a readable loop or named intermediate value over a dense expression, nested ternaries, or a chain of trivial helper calls.
- Let appropriate types express states and invariants. Do not add a type hierarchy, wrapper, or runtime assertion solely to replace a useful comment.
- Follow the project's formatter and language conventions. Do not shorten names, pack statements onto one line, or merge distinct responsibilities to reduce line/file counts.

## Require a Current Reason for an Abstraction

- Keep short, clear logic inline by default. Avoid forwarding wrappers, factories for a single fixed construction, and interfaces or configuration introduced only for hypothetical future use.
- Extract when it centralizes a rule that must stay consistent, isolates a cohesive complex operation, or serves a current boundary such as resource ownership or an existing test seam. A single caller can justify a helper when the name and boundary make the flow easier to follow.
- Reuse depends on shared meaning and change ownership. Similar syntax or a second occurrence alone does not justify a shared module; a little local repetition can be clearer than coupling unrelated concepts. Do not expose a private helper just to avoid a few repeated lines.
- Before adding a layer, identify what present complexity it removes. If the answer is only "cleaner", "for later", or "to avoid a comment", keep the direct code. Put any substantial design rationale in the review/decision record, not a source-code essay.

## Comments: Only Information the Reader Would Otherwise Miss

Default to no comments for obvious code. There is no comment quota or comment-to-code ratio. First try a clearer name or simpler flow; if important context remains, keep the shortest sufficient comment beside the affected code, usually one sentence.

Keep comments for non-obvious reasons, external constraints, intentional surprises, and invariants a later edit could break. For example, `// Keep the lock through publish: consumers can read immediately.` explains an ordering requirement; `// publish the event` only narrates a call. Explain a necessary workaround or known limit where it matters, with a source/issue link when useful.

Preserve required API documentation, license headers, tooling directives, and safety rationale (including unsafe-code invariants). Document public contracts the signature cannot convey, such as units, errors, ownership, and side effects; follow ecosystem requirements without filling obvious private helpers with doc templates. Correctness may require more than one sentence.

Omit or remove within the edited area:

- Narration of obvious assignments, loops, branches, returns, or test arrange/act/assert steps.
- Section banners, empty doc templates, changelog notes, and commented-out code. Do not create extra modules merely to replace banners.
- Reviewer-facing explanations of the patch; put them in the PR description.
- TODOs or stubs for current requirements: finish the work or explicitly agree on deferral with the user. Do not hide missing behavior in a comment.

## Self-Check Before Finishing an Edit

Review the touched code without expanding into unrelated cleanup:

1. Can a reader follow the behavior from names and local control flow without decoding dense expressions or chasing trivial helpers?
2. Does each new helper, type, option, file, or dependency earn its place today?
3. Does each comment add necessary information, with no removable filler? Keep required documentation and directives even when the code looks obvious.
4. Did simplification preserve behavior and the checks that establish it?

## Inspiration

[Ponytail](https://github.com/DietrichGebert/ponytail), especially its [implementation ladder](https://github.com/DietrichGebert/ponytail/blob/main/skills/ponytail/SKILL.md), informed the preference for reuse, built-ins, and minimal implementation. These rules prioritize readability and the full task contract, without line-count targets, forced one-liners, or branded comments.
