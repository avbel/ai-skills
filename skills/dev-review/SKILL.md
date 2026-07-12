---
name: dev-review
description: Orchestrated code review — spec-completeness audit, production checklist, security pass, edge-case test coverage audit, and a second opinion from another AI agent (Gemini/Codex) when available. Use when the user says "review this", "review my changes/PR", "is this ready to merge", or before merging work from dev-feature or dev-problem-solving.
---

# Code Review (Orchestrated)

A review pass that combines three lenses: the production checklist, a test-coverage audit, and — when another agent is installed — an independent second opinion. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

## Workflow

### 1. Scope the diff

- Dirty working tree → review staged + unstaged + untracked.
- Clean tree → review the branch diff against the base (`origin/HEAD` → `main` → `master`).
- Read surrounding code (callers, types, existing tests) — never review a diff in isolation.

### 2. Spec-completeness audit (blocking findings)

If a plan, solution doc, issue, or user request exists for this change (`docs/solutions/`, a `dev-feature` plan message, the conversation), check the diff against it **item by item** before looking at quality. AI-authored diffs habitually drop spec parts silently — hunt for exactly that:

- **Silently skipped requirements** — walk each spec item and point at the code that implements it; anything you can't point at is a blocking finding, even if the code "looks complete".
- **Stubs posing as implementation** — grep the diff for `TODO`, `FIXME`, `XXX`, `unimplemented`, `not implemented`, `NotImplementedError`, `todo!()`, `throw new Error("...later...")`, empty function bodies, and hardcoded placeholder returns. Every hit is either (a) explicitly declared to the user with a reason, or (b) a blocking finding. A TODO the user never heard about is a silently dropped requirement wearing a comment.
- **Quietly narrowed scope** — the spec said "all users", the code handles "active users"; the spec said retry, the code logs and continues. Compare behavior, not just structure.

### 2b. First-party quality review

Apply the production checklist from the `code-review` skill if installed (observability, backward compatibility, migrations, idempotency/concurrency/timeouts, PR quality). Otherwise cover at minimum: correctness, error handling, silent failure paths, backward compatibility of anything another system consumes, and migration safety.

Also check style: comment noise and density per `dev-code-style`.

**Unused-code check (warn and ask, never silently delete):** look for code the diff leaves dead:
- Code **orphaned by this change** — the old implementation kept alongside its replacement, helpers whose last caller was just removed, now-unreferenced imports/exports/config keys/env vars
- **Newly added but never called** — speculative helpers, unused parameters, dead branches behind conditions that can't be true
- Cheap verification: grep for the symbol's usages; run the ecosystem's dead-code tooling when available (`tsc --noUnusedLocals`, `knip`, `cargo +nightly udeps` / `#[warn(dead_code)]` output, `vulture`)

Report each item under "Unused code" in the verdict and **ask the user whether to remove it** — one grouped question, not one per item. Don't flag code that is plausibly used externally (public library API, reflection/DI-loaded, framework hooks) — say it *looks* unused and why you're unsure. If the user approves removal, delete it fully (git remembers) rather than commenting it out.

**Duplication check:** for each nontrivial added function/block, grep the codebase for an existing equivalent (similar name, same signature shape, same constants/regexes/error strings). If the logic already exists as a private helper elsewhere, the finding is "promote and reuse, don't copy" — make it public / move it to a shared module and call it from both places. Two copies of the same logic is a should-fix finding; three or more, or copied *business* logic, is blocking.

### 3. Edge-case test audit

For every new or changed code path, check the diff's tests against the edge-case checklist in `dev-testing` (empty/null input, boundaries, duplicate/concurrent calls, dependency failures, partial failure). Report **which specific edge cases have no test**, as a short list — e.g. "no test for the 429 path in `syncUsers`". Missing edge-case tests are findings, same as bugs.

### 3b. Security pass (every review, findings block by default)

Check the diff — not the whole codebase — against this list. A security finding needs the same rigor as any other: name the concrete attack ("attacker does X, gets Y"), not a vague "could be unsafe".

**Untrusted input reaching a sink.** Trace every new input (request params, headers, file contents, webhook payloads, LLM output) to where it's used:
- SQL/queries built by string concatenation instead of parameters/builders
- Shell commands from `exec`/`spawn` with interpolated input (use arg arrays)
- Paths joined from user input without normalization → traversal (`../`)
- HTML rendering: `innerHTML`, `dangerouslySetInnerHTML`, unescaped template output
- Deserialization of untrusted data (`pickle`, `yaml.load`, Java native); `eval`/`Function(string)` on anything dynamic
- User-supplied URLs that the server fetches → SSRF (validate host allowlist, block internal ranges)

**AuthZ on every new surface.** Each new endpoint/handler/job answers two questions in code you can point to: *who may call this* (authn) and *may they touch THIS object* (object-level authz — the missing-IDOR-check is the most common diff-level hole; filter by owner/tenant in the query, not after fetch).

**Secrets & sensitive data:**
- No credentials, API keys, or tokens in the diff (grep for `key=`, `secret`, `Bearer`, PEM headers, high-entropy literals) — env/secret-manager only
- Nothing sensitive in logs or error responses: no passwords/tokens/PII in log lines, no stack traces or internal paths sent to clients
- New PII fields: are they excluded from logging/serialization defaults?

**Crypto & randomness:** no hand-rolled crypto; passwords hashed with argon2/bcrypt/scrypt (never plain SHA/MD5); security tokens from a CSPRNG (`crypto.randomBytes`/`rand::rngs::OsRng`), never `Math.random()`; comparisons of secrets constant-time.

**New dependencies:** before accepting one, check it's actively maintained, the name isn't a typosquat of the package you meant, and `npm audit`/`cargo audit`/`pip-audit` is clean for it. Pin the version.

**Money/quota/state-machine paths:** check for TOCTOU races — balance read then written without a transaction/lock lets two concurrent requests double-spend.

**Escalate** beyond this pass when the diff touches auth flows, session handling, crypto, payments, sandboxing, or file upload handling: run the platform's dedicated security review (`/security-review` in Claude Code) or a security-focused second opinion (step 4 with the hint "adversarial security review"), and say in the verdict that you did.

### 3c. Embedded-language check

Code inside strings gets zero help from the host language's compiler — a typo in embedded SQL/HTML/GraphQL passes typecheck and fails at runtime. For every string in the diff containing another language (SQL, HTML, GraphQL, regex, shell, CSS, JSON, XPath):

**Validate the syntax, don't eyeball it.** In order of preference:
1. **Execute against the real engine** — prepare the SQL on the local/test database (`PREPARE q AS <query>` in Postgres parses *and* type-checks without running), parse GraphQL with the project's graphql lib, compile the regex in a REPL, render the template.
2. **Run a linter/parser** if available: `sqlfluff`/`pgsql-parser` (SQL), `graphql validate` against the schema, HTML validator.
3. Only as a last resort, manual parse: matched quotes/parens, correct placeholder count and order (`$1..$n` vs args passed), keywords in valid positions.

**Cross-boundary consistency:** placeholder count matches the argument list; column names/types match the current schema (check migrations in the same diff); GraphQL fields exist in the schema; HTML ids/classes referenced from JS/CSS actually exist.

**Postgres-specific traps (check every SQL string):**
- **Missing explicit casts on parameters.** Drivers send parameters as `unknown`/text; anything non-obvious needs a cast in the SQL: `$1::uuid`, `$1::jsonb`, `$1::timestamptz`, `= ANY($1::text[])`, and **enum comparisons** — `status = $1::my_schema.order_status`, never a bare `status = $1`. Also literal-to-enum: `'active'::my_schema.order_status`.
- **Unqualified custom types.** Enums, domains, and composite types must be schema-qualified everywhere they appear — casts, `CREATE TABLE` columns, function signatures, migrations: `my_schema.my_enumeration`, not `my_enumeration`. A bare name only works while `search_path` happens to include the schema — it differs between the app, migration runner, `psql`, and pg_dump/restore, so this breaks exactly where it wasn't tested. Same rule for functions and tables outside `public` when `search_path` isn't guaranteed.
- `NULL` handling in comparisons (`= NULL` instead of `IS NULL`), and `IN ($1)` with an array argument instead of `= ANY($1)`.

**Tie-in with `dev-testing`:** every embedded SQL/GraphQL string changed in the diff must be executed by at least one integration test against the real engine (in-memory/testcontainer) — that's the only durable guard for embedded-language errors. An untested new query is a missing edge-case-test finding.

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

### Spec gaps & undisclosed TODOs
- <spec item> — not implemented / stubbed at file.ts:42, user was not told

### Security
- file.ts:57 — <attack scenario → impact, suggested fix> (blocking unless argued down)

### Blocking
- file.ts:42 — <issue, why it breaks, suggested fix>

### Should fix
- file.ts:88 — duplicates private helper `parseRange` in util/range.ts — promote it and reuse
- ...

### Missing edge-case tests
- <path> — no test for <case>

### Unused code (remove? y/n per group)
- old util/legacyParser.ts — last caller removed by this diff
- newHelper() in sync.ts — added but never called

### Second opinion (<agent> | none available)
- <agreements / new findings / disagreements>

Verdict: ready to merge | needs changes
```

## Rules

- Review-only by default: report findings, let the user decide. Fix only when explicitly asked ("review and fix").
- No nitpick padding — if formatting is linter-enforced, don't comment on it. Fewer, higher-confidence findings beat exhaustive noise.
- Every blocking finding needs a concrete failure scenario ("when X happens, Y breaks"), not a vibe.
- For self-authored code (you wrote the diff earlier in the session), always prefer the second opinion step — you share blind spots with yourself.
