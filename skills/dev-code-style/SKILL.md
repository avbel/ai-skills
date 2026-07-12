---
name: dev-code-style
description: Commenting and code-style discipline for any language — moderate comments, no comment noise, self-documenting code first. Use when writing or editing source code in any project, or when the user asks to clean up comments or complains about over-commented / under-commented code.
---

# Code Style — Comments Discipline

Keep comment density moderate. Code explains **what**; comments explain **why**.
Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

## The Ratio Rule

- Never write more comment lines than the code they describe. 3 comment lines for 1 line of code is noise — delete or compress.
- A good target for application code: roughly 1 comment per 10–20 lines, concentrated where the code is genuinely non-obvious.
- Zero comments is acceptable for straightforward code. Silence beats narration.

## Write Comments Only For

- **Why, not what** — a non-obvious decision, trade-off, or constraint the code cannot express: `// retry once: the vendor API drops ~2% of first attempts`
- **Surprises** — behavior that contradicts a reasonable first reading (intentional fallthrough, deliberate off-by-one, ordering that matters).
- **External contracts** — links to specs, RFCs, issue trackers, or vendor docs the code implements.
- **Warnings** — footguns for the next editor: `// do not reorder: init() must run before config load`
- **Public API docs** — doc comments (JSDoc / rustdoc / godoc) on exported functions and types, in the format the ecosystem's tooling consumes. One concise sentence beats a template with empty `@param` stubs.

## Never Write

- Comments that restate the line: `// increment counter` above `counter += 1`
- Section banners (`// ===== HELPERS =====`) — use file/module structure instead.
- Commented-out code — delete it; git remembers.
- `TODO`/`FIXME` for work that was part of the current task — either do it now or surface it to the user and get an explicit OK to defer. A TODO the user never saw is a silently dropped requirement, not a comment.
- Changelog comments (`// fixed by X on 2024-01-05`, `// updated for ticket-123`) — that's what commit messages are for.
- Comments addressed to a reviewer explaining why the change is correct — put that in the PR description.
- Empty doc-comment templates auto-filled with parameter names.

## Before Commenting, Try To Make The Code Say It

1. Rename: a precise function/variable name deletes most "what" comments.
2. Extract: a well-named small function replaces a paragraph explaining a block.
3. Types/asserts: an enum, a narrow type, or an assertion states an invariant better than prose.

Only when none of these work, write the comment.

## Match the Codebase

- Mirror the surrounding file's comment density, doc-comment style, and language (don't introduce JSDoc into a repo that doesn't use it).
- Follow the project's formatter/linter config as the single source of truth for formatting; never hand-format against it.
- If ecosystem convention skills are installed (`js-conventions`, `rust-conventions`, `move-conventions`), they take precedence for language-specific rules.

## Self-Check Before Finishing an Edit

Scan the diff you produced:

1. Any comment that would survive being deleted with zero information loss? Delete it.
2. Any comment block longer than the code under it? Compress to one line or delete.
3. Any "what" comment fixable by a rename? Rename instead.
