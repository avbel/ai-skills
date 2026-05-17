---
name: manual-testing-node-js
description: Manual testing for Node.js backends — env setup, docker DB + migrations, SUI smart contracts, package.json scripts. Use when manually testing a Node.js project (package.json present), especially when external services, blockchain contracts, or DB-backed workflows are involved.
---

# Manual Testing — Node.js Backends

Walk the user through manually testing a Node.js backend repo end-to-end: detect, provision, plan, execute, report.

Coexists with the generic `manual-testing` skill (which handles non-Node work) and project-specific testers like `ln-522-manual-tester`. This skill fires only when `package.json` is present.

---

## Phase 1 — Detect & prepare environment

### 1.1 Node version

Resolve required version in this order:
1. `.nvmrc`
2. `.node-version`
3. `engines.node` in `package.json`

If installed Node mismatches:
- Propose the install command (`nvm install <v>` or `fnm install <v>`).
- **Ask the user before running it.** Never auto-`brew install node`.

### 1.2 Package manager

Detect from lockfile:
- `pnpm-lock.yaml` → `pnpm`
- `yarn.lock` → `yarn`
- `package-lock.json` → `npm`


The repo's lockfile is authoritative. Do not force `pnpm` even if global rules prefer it — that breaks resolution for repos pinned elsewhere.

### 1.3 `.env` preparation

#### Step A — determine the target env file path

The skill must write to **whatever path the project's scripts actually load**, because most Node scripts hardcode it (e.g. `node --env-file=.env <script>`). Detect in this order:

1. Grep `package.json` scripts for explicit env-file flags:
   - `node --env-file=<path>`
   - `dotenv -e <path>`
   - `dotenvx run -f <path>`
   - `dotenv_config_path=<path>`
   If found → that path is the target.
2. Otherwise, default to `.env` (Node's `--env-file=.env`, `dotenv/config`, and the standard `dotenv.config()` all read it).

Call this resolved path `$ENV_PATH`. **There is no separate `.env.test` unless the project's scripts already point at one.**

#### Step B — protect any existing real env file

Read `$ENV_PATH` if it exists. A file is **safe to overwrite** if and only if it already contains a line matching `^NODE_ENV=test\b` (i.e. it's a leftover test env from a prior run).

Otherwise it's the user's real env:
1. Rename it to `$ENV_PATH.backup-<timestamp>`.
2. Record the rename in `tests/manual/.state.json`.
3. Teardown restores it (success or failure).

#### Step C — generate the test env

1. Copy `.env.example` / `.env.sample` / `.env.template` → `$ENV_PATH`.
2. Always set `NODE_ENV=test` (and verify the line is present before writing).
3. Fill sensible defaults (localhost DB URLs, dev ports, etc.) silently.
4. For each value that is empty, placeholder (`CHANGE_ME`, `<...>`), or unclear, **ask the user**.
5. Before continuing, show the **final `$ENV_PATH` to the user and ask for confirmation**.

#### Keypair detection (first run only)

Scan `.env` for keys matching `/PRIVATE_KEY|SECRET_KEY|SIGNING_KEY|SIGNATURE_SECRET_KEY|MNEMONIC/i`, or for adjacent comment lines containing `/pub|public|address|0x[a-f0-9]{40,}/i`.

If found, present them to the user and offer regeneration:
- SUI: `sui keytool generate ed25519`
- Generic Ed25519/RSA: `openssl genpkey`

On accept: write fresh values back to `.env`, update the public-key comment, and surface the new public key / address so the user can fund it.

### 1.4 Secret hygiene (applies to every phase)

- **Never echo full secret values to chat.** Mask as `****<last4>`.
- **Never write secrets to the plan file or repro bundles.** Sanitize env dumps.
- Only `.env` holds plaintext.

### 1.5 Idempotency / re-runs

If any of these exist, ask the user `reuse / wipe / abort`:
- A `$ENV_PATH` whose content starts with `NODE_ENV=test` (test env from a prior run)
- Running docker containers from a previous run
- Prior `tests/manual/PLAN-*.md`
- A `$ENV_PATH.backup-<timestamp>` left over from a prior run — suggests teardown was skipped. **Offer to restore it first before anything else**, since it represents the user's real env.

Don't silently pick up partial state. Files at `$ENV_PATH` *without* `NODE_ENV=test` are the user's real env — they are always preserved by rename, never wiped.

---

## Phase 2 — Infrastructure bring-up

### 2.1 Database

- If `docker-compose.yml` declares a DB service → `docker compose up -d <db>`.
- Otherwise, detect from `package.json` deps (`pg`, `mysql2`, `mongoose`, `redis`, `ioredis`, etc.) and run a one-off `docker run` (use the version from compose if any related service references it; else latest stable).

### 2.2 Migrations

Try in this order; show the command before running:
1. A `package.json` script: `db:migrate`, `migrate`, `migration:run`, `prisma:migrate`, etc.
2. The ORM CLI for the detected tool: `prisma migrate deploy`, `drizzle-kit push`, `typeorm migration:run`, `knex migrate:latest`, `sequelize db:migrate`.

If none can be found, ask the user.

### 2.3 External services

Scan `.env.example` for URLs not pointing at `localhost`/`127.0.0.1`/internal domains and for `*_API_KEY`/`*_TOKEN` pairs. Cross-grep the codebase for `fetch`/`axios`/SDK calls using those env vars. If `.env.example` is absent, scan `$ENV_PATH` instead and grep the source tree for env reads whose values look like URLs.

For each external service found, ask the user:
- **Provide a real test URL / credentials**, or
- **Mock it** — spin up a local Express/Hono stub on a free port, derive the response shape from the calling code, and point the relevant env var at `http://localhost:<port>`.

Never invent endpoints. Never assume sandbox availability.

### 2.4 SUI smart contracts (when `Move.toml` detected)

1. Start a local network with faucet: `sui start --with-faucet --force-regenesis` (background). The deploy address needs gas, and tests usually need to top up additional addresses.
2. **Switch the CLI to the local env before anything else**:
   ```sh
   sui client new-env --alias local --rpc http://127.0.0.1:9000
   sui client switch --env local
   sui client faucet
   ```
   Skipping this step is dangerous — if a mainnet/testnet env is active, `sui client test-publish` will publish there using whatever key is loaded.
3. `Move.toml` dependencies resolve automatically at build time. Only deploy a dependency manually if it is a local path dep that hasn't been published yet; in that case, publish leaves first and substitute the resulting address back into the dependent package's `Move.toml` `[addresses]` table.
4. Run publish with JSON output so the result is machine-parseable: `sui client test-publish --build-env=local --with-unpublished-dependencies --json > tests/manual/logs/publish-<timestamp>.json`.
5. **Autodetect every object created by the publish and write it to `$ENV_PATH`.** A single publish typically creates more than just the package — capability objects, treasury caps, shared config objects, the upgrade cap, etc. Parse the JSON output and walk `objectChanges[]` + `effects.created[]`:

   For each created object, derive an env var name from its type:

   | Object type pattern | Suggested env var |
   |---|---|
   | The published package itself | `PACKAGE_ID` |
   | `0x2::package::UpgradeCap` | `UPGRADE_CAP_ID` |
   | `0x2::package::Publisher` | `PUBLISHER_ID` |
   | `0x2::coin::TreasuryCap<…::X>` | `<X>_TREASURY_CAP_ID` (uppercase the coin name) |
   | `0x2::coin::CoinMetadata<…::X>` | `<X>_COIN_METADATA_ID` |
   | `0x2::display::Display<…::X>` | `<X>_DISPLAY_ID` |
   | `…::<module>::<X>Cap` (any `*Cap` struct from the deployed package) | `<X>_CAP_ID` (snake-cased) |
   | Shared objects (`owner: { Shared: {…} }`) from the deployed package | `<TYPE_NAME>_ID` |
   | Anything else | ask the user for a name; never silently drop it |

   Disambiguation rules:
   - Strip generic params and namespaces when building the env var name; keep only the leaf struct name.
   - If the same type is created multiple times, suffix with `_1`, `_2`, … in creation order and ask the user to rename if semantics differ.
   - Skip plain `Coin<T>` balance objects from the initial mint — those rotate every run; the `TreasuryCap` is what tests need.

   Before writing, **show the user the full mapping** (`PACKAGE_ID=0x… USDC_TREASURY_CAP_ID=0x… …`) and confirm. Append confirmed entries to `$ENV_PATH`; record the publish digest as a comment on the line above so re-runs can detect drift.

If the contract integrates USDC (grep `Move.toml` / sources for `usdc`, `USDC`, or a Circle dependency), use the [`sui-local-dev-usdc`](../sui-local-dev-usdc/SKILL.md) skill to deploy a mock USDC package on the local network and write the resulting `USDC_PACKAGE_ID` (plus its `USDC_TREASURY_CAP_ID`, picked up by the same autodetection pass) back to `$ENV_PATH`. Mainnet USDC will not exist on `--force-regenesis`, so any code path that constructs `Coin<USDC>` will fail without the mock. Deploy the USDC mock **before** the target package whenever the target's `Move.toml` lists USDC as a dependency.

### 2.5 Long-running processes

Start the app (`pnpm dev`/`npm start`/etc.), the SUI local net, and mock servers with `run_in_background=true`.

- Tee stdout/stderr to `tests/manual/logs/<service>-<timestamp>.log`.
- Track PIDs in `tests/manual/.state.json`.
- Teardown: SIGTERM → 5s grace → SIGKILL.

### 2.6 Healthcheck

Before executing any test steps:
- Poll the DB port until reachable.
- Hit the app's `/health` (or `/`) until it returns 200 or 404.
- Verify the migrations table is populated (`SELECT COUNT(*) FROM <migrations_table>`).

Hard-fail at **60 seconds** with a clear message.

### 2.7 Test data

Default: empty DB after migrations.

Seed only when a specific test step requires preconditions. Insert the data **in that step** (visible in the plan), using deterministic values (fixed UUIDs, fixed timestamps, `--seed=42` for fakers). Avoid hidden state.

---

## Phase 3 — Plan generation

Write to `tests/manual/PLAN-<timestamp>.md`. Each run gets its own file.

### Plan structure

Markdown with checkbox items and sub-items. Every item contains:

- **Action** — exact command, HTTP call, or UI interaction.
- **Expected** — plain-English outcome.
- **Verification** — concrete check: SQL query, log grep, HTTP assertion, etc.

Example item:

```markdown
- [ ] Create a payment request via CLI
  - **Action**: `pnpm cli create-payment --amount 100 --currency USD --user alice`
  - **Expected**: returns a request ID and writes a row to `payment_requests`.
  - **Verification**:
    ```sql
    SELECT id, amount, status FROM payment_requests WHERE user_email = 'alice@example.com';
    ```
    Status should be `pending`.
```

### Deriving arguments for package.json scripts

For each script the plan invokes:
1. Read the script body and trace through to the entrypoint's arg parsing (`process.argv`, `yargs`, `commander`).
2. For each required flag without a sensible default, ask the user with examples drawn from comments, README, or recent git history.
3. Record the final invocation verbatim in the plan.

### Edge cases — always propose

In addition to the happy path, draft at least one item from each category:

- **Invalid input / boundaries** — empty strings, null, huge payloads, wrong types, malformed JSON, off-by-one numeric ranges.
- **Auth / authz** — missing/expired token, wrong role, cross-tenant access, replay.
- **External service failures** — mock returns 500 / times out / malformed body; unreachable; slow.
- **Concurrency / races** — parallel requests on the same resource, double-spend on chain ops, idempotency-key collisions.

### Confirmation gate

**Always ask the user to confirm the plan before executing.** Adjust based on their feedback. Re-confirm if edge cases are added mid-execution.

---

## Phase 4 — Execute

Run items top-to-bottom. For each:

1. Print a one-line "starting step N…" to chat.
2. Execute the action.
3. Run the verification.
4. On success: tick the checkbox in `PLAN-<timestamp>.md` on disk, print `✅ step N` to chat.
5. On failure: see below.

### DB validation queries

Use `psql "$DATABASE_URL" -c "..."` or `mongosh "$MONGO_URI" --eval "..."` first. If the CLI is not installed, fall back to inline Node:

```bash
node -e 'import("postgres").then(async({default:postgres})=>{const sql=postgres(process.env.DATABASE_URL);console.log(await sql`SELECT ...`);await sql.end();})'
```

Use low-level drivers (`postgres`, `mongodb`, `ioredis`) rather than the app's ORM — keeps verification independent of the code under test.

### On failure — stop and report

1. **Halt execution.** Do not auto-fix. Do not continue to later steps.
2. Save a repro bundle to `tests/manual/failures/<step>-<timestamp>/`:
   - `command.sh` — the exact invocation.
   - `env.sanitized` — env at execution time with secrets masked.
   - `stderr.log`, `stdout.log` — full output.
   - `app.log` — relevant slice of the app log.
   - **No DB snapshot.** Leave the DB instance running and surface the connection string (with password masked) so the user can inspect interactively.
3. Ask the user: `fix now / skip this step / abort the run`.

---

## Phase 5 — Wrap up

- **All steps passed** → tear everything down: stop background processes, `docker compose down`, remove temp mock servers. **Then: delete the test `$ENV_PATH` and restore the user's real env from `$ENV_PATH.backup-<timestamp>` if one was created.** Remove `tests/manual/.state.json`.
- **Any failure** → leave docker, app, mocks, and SUI net running for forensics. **Still restore the real env file** if a backup exists (safety invariant — the user's `.env` must never be left clobbered, regardless of run outcome). The test env file at `$ENV_PATH` may be kept *only if* there is no backup to restore (nothing to restore over). Print connection strings and log paths.

### Final artifact

The `PLAN-<timestamp>.md` is the durable record (all boxes ticked, failures cross-referenced to their `failures/<step>-<timestamp>/` directory).

In chat, end with a 5-line summary:

```
Total: N
Passed: N
Failed: N
Skipped: N
Plan: tests/manual/PLAN-20260517-143022.md
Failures: tests/manual/failures/  (or "none")
```

---

## Quick checklist

- [ ] Node version detected and matches `.nvmrc` / `engines.node`
- [ ] Lockfile-appropriate package manager used
- [ ] `$ENV_PATH` resolved from scripts (defaults to `.env`); test env generated with `NODE_ENV=test`, user-confirmed, keypairs regenerated if present; real env preserved (renamed to `$ENV_PATH.backup-<ts>` unless the existing file already has `NODE_ENV=test`)
- [ ] DB running (compose or ad-hoc), migrations applied
- [ ] External services either real or mocked on local port
- [ ] SUI CLI switched to `local` env before publish; contract deployed and `PACKAGE_ID` in `$ENV_PATH` (if applicable)
- [ ] If contract uses USDC: mock USDC deployed via `sui-local-dev-usdc`, `USDC_PACKAGE_ID` in `$ENV_PATH`
- [ ] Healthcheck passed
- [ ] Plan written to `tests/manual/PLAN-<ts>.md`, user-confirmed
- [ ] Plan covers happy path + all four edge-case categories
- [ ] Execution ticked boxes on disk in real time
- [ ] On failure: stopped, repro bundle saved, services left running
- [ ] On success: torn down cleanly, summary printed
