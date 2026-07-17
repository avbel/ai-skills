# Skills Improvement Suggestions

Review of all 82 skills in this repository (July 2026). Findings are grouped by
priority. Code-level claims marked **verified** were checked against crate/package
sources; everything else was confirmed by direct inspection of the skill files.

## Status: applied

Everything in §1–§5 and the actionable parts of §6 have been **fixed on this
branch**, and §7's lint script now exists as `scripts/lint-skills.sh` (run it
from the repo root; it passes on all 82 skills). Notes on the applied fixes:

- Renames (§4): `cookbook_rust` → `rust-cookbook`, `high_assurance_rust` →
  `rust-high-assurance`, `high_performance_rust` → `rust-high-performance`,
  `macros_rust` → `rust-macros`, `hotpath-rs` → `hotpath-rust`. Users with the
  old directory names installed under `~/.claude/skills/` should re-install.
- The dangling `rust-testing` references were retargeted to `dev-testing`
  (no Rust-specific testing skill exists yet — creating one remains open).
- The lint run surfaced 10 additional skills missing an H1 title beyond the two
  in §4; all have one now. It also surfaced 6 more descriptions over 400 chars
  beyond the seven in §5; all 13 are now ≤ ~390 chars.

Intentionally **not** changed (informational items): the review-trio model-name
staleness watch, the `node:ffi` forward-looking section (well-hedged),
the `0x2::balance::send_funds` maintainer sanity check, and the broad
trigger-phrase pass over all descriptions (the existing descriptions are
serviceable; rewriting 60+ of them mechanically risks regressing trigger
accuracy without evals).

The sections below are the original review record.

What checked out clean and needs **no** action: `README.md` is fully in sync with
the skill directories; every frontmatter `name:` matches its directory; version
pins across Rust and JS skills are current (reqwest 0.13, tonic 0.14.6,
opentelemetry 0.32, TS 6.0, Node 26, Vitest 4.1.x, etc.); and no SKILL.md
references a `scripts/` or `references/` file that doesn't exist.

---

## 1. Bugs and factual errors (fix first)

### tokio-stream-rust
- `SKILL.md:69–91` — repeated typo `stream.iter(1..=10)` (method call) should be
  `stream::iter(1..=10)` (module function, as correctly written at lines 45–49).
  The combinator examples will not compile as written. Appears ~7 times.
- `SKILL.md:211, 222` — `try_for_each_concurrent` and `buffer_unordered` are
  `futures::StreamExt` combinators; they do not exist on
  `tokio_stream::StreamExt`. The "Process Stream with Concurrency Limit" example
  won't compile without adding the `futures` crate and importing its trait.

### dotenvy-rust
- `SKILL.md:49` — `use dotenvy::dotenv_ok;` described as a compatibility alias.
  **Verified against dotenvy 0.15.7 source: no such function exists.** Remove the
  line (the surrounding `dotenv()` guidance is correct).

### tempfile-rust
- `SKILL.md:178` — `use tempfile::persist::PersistError;` is a wrong path.
  **Verified against tempfile 3.25.0: `PersistError`/`PathPersistError` are
  re-exported at the crate root** (`tempfile::PersistError`); there is no public
  `persist` module.

### tracing-rust
- `SKILL.md:279` — `use tracing_futures::InstrumentFuture;` — no such trait
  exists; the example only uses `.instrument()`, which comes from
  `tracing::Instrument`.
- `SKILL.md:26` — the `tracing-futures = "0.2"` dependency is obsolete;
  `Instrument` and `WithSubscriber` live in the `tracing` crate itself. Drop the
  dependency and the bogus import.

### eyre-rust
- `SKILL.md:127` — text corruption: "removes喧information" contains a stray CJK
  character.
- `SKILL.md:111` — `use eyre::InstallHook;` is imported but unused (the example
  calls `eyre::set_hook`).

### sui-common-ops
- `scripts/sui-disassemble-package.sh` — `Buffer.from(bytes)` assumes
  `module_map` values are byte arrays. If the client returns base64 strings
  (which the SKILL text itself acknowledges can happen), this writes garbage
  `.mv` files. Detect string vs. array before converting.

---

## 2. Dangling cross-references between skills

- **`rust-patterns` does not exist** — it's a stale name for
  `design-patterns-rust`. Referenced in:
  - `cookbook_rust/SKILL.md:268`
  - `high_performance_rust/SKILL.md:149`
  - `macros_rust/SKILL.md:195`
- **`rust-testing` does not exist** — referenced 3× in
  `high_assurance_rust/SKILL.md` (lines 8, 82, 105). Either create a
  `rust-testing` skill (testing mechanics currently live nowhere) or retarget
  these references.
- **`dev-review` §4 is out of sync with the review trio.** It hardwires the
  `gemini-review-code` skill plus *inline* `codex exec` / OpenCode invocations,
  and never mentions `codex-review-code` or `claude-review-code`, which now exist
  and do that job with sandboxing, timeouts, and prompt-injection fencing the
  inline snippets lack. §4 should route to whichever of the three skills is
  installed, in a defined preference order. This is the single most impactful
  cross-family fix.

---

## 3. Contradictions between sibling skills

Agents commonly load several of these skills together, so conflicting absolutes
are worse than individually imperfect advice.

- **JSON-RPC ban vs. kiosk requirement.** `sui-sdk-js/SKILL.md:12` says "Do not
  use `SuiJsonRpcClient` under any circumstances", while `sui-kiosk-sdk-js`
  *requires* it (line 17 and the primary client-setup example) for event queries
  the gRPC transport lacks — a legitimate reason. Fix in `sui-sdk-js`: soften the
  absolute with a documented kiosk carve-out and cross-link.
- **`public entry` ban violated.** `move-conventions/SKILL.md:44` says "Do not
  use `public entry`", but `sui-local-dev-usdc` uses `public entry fun mint` in
  both `SKILL.md:120` and `scripts/sui-local-dev-usdc-bootstrap.sh:46`.
- **Faucet endpoint drift.** `sui-local-dev-usdc` (lines 45, 264) uses the
  deprecated v1 path `http://127.0.0.1:9123/gas`; `sui-sdk-js` (line 50)
  correctly uses `http://127.0.0.1:9123/v2/gas`. Standardize on v2 across all
  Sui skills.
- **Move style drift.** The `sui-local-dev-usdc` sample module uses explicit
  `use sui::coin/transfer/tx_context` imports and block-style `module { }`,
  which `move-conventions` calls unnecessary/deprecated under 2024.beta.
- **Constant naming.** `js-conventions` bans `UPPER_SNAKE_CASE` constants
  outright, while `biome-js`'s recommended `style.useNamingConvention` config
  permits `CONSTANT_CASE` for module-level consts. Both are prescriptive over
  the same files — align them or state which wins.
- **Internal inconsistency in `sui-sdk-js`**: result checking is shown two ways
  (`result.FailedTransaction?.status.error` at ~371–375 vs.
  `result.FailedTransaction.status.error?.message` at ~501–508). Pick one shape.
- Minor: `design-patterns-ts` examples use `console.log` and omit semicolons,
  contradicting the `biome-js`/`js-conventions` lint posture. Illustrative-only,
  low priority.

---

## 4. Repository convention violations (per CLAUDE.md)

- **Naming (kebab-case is mandated):** `cookbook_rust`, `high_assurance_rust`,
  `high_performance_rust`, `macros_rust` use snake_case. Also `hotpath-rs` is
  the only skill using an `-rs` suffix where every other Rust skill uses
  `-rust`. Renaming is churn (installs reference the directory name), but at
  minimum new skills should not copy these patterns; ideally rename with a
  README note.
- **500-line limit exceeded:** `sui-sdk-js` (818), `design-patterns-rust` (693),
  `design-patterns-ts` (628). At/near the limit: `sui-common-ops` (499),
  `google-cloud-secret-manager-rust` (490), `tokio-rust` (487),
  `asupersync-rust` (475). See §5 for what to split out.
- **Missing `# {Title}` H1:** `design-patterns-rust` and `nanoprogress-rust`
  start with body text right after the frontmatter; every other skill has the
  heading the template specifies.
- **Script requirements:**
  - `sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh` is not
    executable (`chmod +x`).
  - Temp files without a cleanup `trap` (required by CLAUDE.md):
    `sui-common-ops/scripts/sui-disassemble-package.sh` and the
    `sui-local-dev-usdc` bootstrap.
- Minor: `otel-observable-handles-rust` carries a non-standard frontmatter key
  (`origin:`); harmless, but not part of the template.

---

## 5. Context efficiency

Only 2 of 82 skills use `references/` for progressive disclosure
(`docker-compose`, `k3s`), even though CLAUDE.md recommends it. Concrete splits:

- **`sui-sdk-js` (818 → ~450 lines):** keep Client Choice/Transport,
  Coins & Balances, Transactions, Keypairs/Signing, and the Review Checklist
  inline; move Query Patterns, BCS, Utils (a bare 30-line import dump), Faucet,
  zkLogin/Multisig, Offline/Sponsored, Gas, and gRPC service clients to
  `references/`.
- **`sui-common-ops` (499):** move the nine Operation Recipes (~lines 120–470)
  to `references/operations.md`; keep Hard Rules, Tool Choice, the Node-26
  skeleton, and the arg parser inline.
- **`design-patterns-rust` (693) / `design-patterns-ts` (628):** move the GoF
  pattern code catalogs to `references/`; keep intent descriptions and the
  quick-reference tables inline.
- **`google-cloud-secret-manager-rust` (490):** the ~120-line inline `secret.rs`
  module (lines 124–285) duplicates what its own
  `scripts/create-secret-module.sh` generates. Keep key snippets, drop the full
  listing.
- **Overlong descriptions** load into *every* session at startup. Trim to the
  trigger-bearing essentials (aim ≤ ~350 chars): `high_assurance_rust` (904),
  `design-patterns-rust` (644), `macros_rust` (608), `high_performance_rust`
  (596), `clickhouse` (548), `typescript-6` (533), `cookbook_rust` (525).
- **Duplication:** `opentelemetry-rust` (lines 208, 237) restates the
  observable-handle-leak guidance that `otel-observable-handles-rust` covers in
  depth, without referencing it — add a cross-link. `parquet-js` restates the
  `@duckdb/node-api` client setup from `duckdb-js`; point to the sibling
  instead.

---

## 6. Minor polish

- `clickhouse/SKILL.md:61` and `valkey/SKILL.md:49,64` use bare
  `[js-conventions]` bracket syntax with no link target — renders as literal
  text; make it plain prose or a real link.
- The review-trio descriptions bake in volatile model names
  (`Gemini 3.1 Pro (High)`, `gpt-5.3-codex`, Opus `--effort xhigh`). They're
  overridable and documented, but these are the lines most likely to go stale —
  worth a periodic check.
- `node-rust-addon`'s `node:ffi` section is forward-looking and well-hedged;
  confirm the API shipped as described before leaning on it.
- `sui-common-ops` / `sui-sdk-js` reference `0x2::balance::send_funds` and the
  `serialized-tx`/`serialized-tx-kind` CLI subcommands — consistent between the
  two files, but novel enough to deserve a maintainer sanity check against the
  current SDK/CLI.
- Most descriptions (64 of 82) omit the quoted trigger phrases the CLAUDE.md
  template calls for ("Deploy my app", "Check logs", …). Not every skill needs
  them, but a pass over the ones most likely to under-trigger (the `dev-*`
  family already does this well) would improve activation accuracy.

---

## 7. Process suggestion: lint the conventions in CI

Nearly everything in §4 is mechanically checkable. A small
`scripts/lint-skills.sh` run in CI (or as a pre-merge step) could enforce:

1. frontmatter `name:` equals the directory name, kebab-case;
2. `description:` present, non-empty, ≤ ~400 chars;
3. SKILL.md ≤ 500 lines and starts with an H1 after the frontmatter;
4. every `scripts/*.sh` has `#!/bin/bash`, `set -e`, is executable, and has a
   `trap` if it references `mktemp`/`/tmp`;
5. every skill has a matching README row (and vice versa);
6. cross-references to `skills/{name}` targets that actually exist — this alone
   would have caught the `rust-patterns`/`rust-testing` dangling references.
