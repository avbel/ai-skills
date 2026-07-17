---
name: dev-e2e-testing
description: End-to-end tests against a production-parity stack — real databases dropped per run, real Valkey and message brokers in disposable mode, local blockchain networks (Sui, EVM), real TCP/UDP/HTTP sockets, mock servers only at external API boundaries, and mandatory network-fault injection. Use when writing e2e tests, when the user asks to "test against a real stack", "test network failures", or to verify an SDK/service end-to-end. For the everyday integration suite see dev-testing.
---

# E2E Testing — Production-Parity Tier

Everything real except other people's clouds. Every dependency the code talks to in production runs locally as the **real engine** — real sockets, real wire protocols, real failure modes. Only external vendor APIs (things you cannot run locally) are mocked, and only at the HTTP boundary. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

**This is a separate, slower tier — not the regular suite.** These tests do NOT run on every `test` invocation, pre-commit, or PR-fast-path. They get their own command (`test:e2e` / `cargo test --features e2e` / a `-tags e2e` build tag) and run on demand and in nightly/pre-release CI. The everyday integration suite is `dev-testing`'s job; never make developers pay the container-startup tax for a parser change.

## When to Use This Tier (and When Not)

Use for:
- Release-gate suites: the critical user journeys through the fully assembled system
- Resilience verification: retries, timeouts, idempotency, recovery under network faults
- SDK verification: does generated/published client code actually work against a live stack
- Blockchain flows: contract deploy + transaction paths that unit tests cannot fake

Do NOT use for: pure logic, single-component behavior, or anything `dev-testing`'s in-memory tier already covers. If a bug is reproducible with `pg-mem` and `msw`, it does not need this tier.

## Stack Rules

### Real transport, always

- The app under test binds a **real socket on an ephemeral port** (port `0`, then read the assigned port) — never in-process request injection (`app.inject`, supertest-against-handler) at this tier. In-process fakes can't lose packets; real sockets can, and the fault-injection layer below depends on it.
- UDP-based code (DNS, metrics, custom protocols) gets a real UDP socket test — UDP silently drops; assert your code tolerates that.
- One shared docker network (or localhost) so every hop is a genuine TCP connection you can break.

### Databases: real server, dropped state

At this tier, skip in-memory shims (`pg-mem`, `mongodb-memory-server`) — use the **real server**:

1. **Testcontainers** (Node/Rust/Go/Java/Python) — one container per suite, unique database per test file/worker.
2. Or a compose-managed instance with **drop-and-recreate before each run**: `DROP DATABASE IF EXISTS e2e; CREATE DATABASE e2e;` then run the real production migrations. Never truncate-and-hope; recreate.
3. Match the production major version exactly (pin the image tag: `postgres:17.4`, not `postgres:latest`).

### Valkey / Redis: real, disposable

Real `valkey` — not `ioredis-mock` (fine for `dev-testing`'s tier, not here). Run it in throwaway mode:

```bash
valkey-server --port 6390 --save '' --appendonly no --maxmemory 256mb --enable-debug-command yes
```

- `--save '' --appendonly no` → pure in-memory, nothing to clean up
- `FLUSHALL` in per-test setup, or a unique key prefix per worker for parallel safety
- `--enable-debug-command yes` lets tests use `DEBUG SLEEP` to simulate a stalled server
- Container equivalent: `valkey/valkey:8` with the same flags as the command

### Message queues: real broker, in-memory mode

Never mock the client library. Run the real broker configured for zero persistence:

| Production broker | Local e2e setup |
|---|---|
| Kafka | **Redpanda** single binary/container: `redpanda start --mode dev-container --smp 1` — Kafka API, no ZooKeeper, starts in ~2s |
| NATS / JetStream | `nats-server -js` with `max_file_store: 0` and memory-storage streams |
| RabbitMQ | `rabbitmq:4-management` container, fresh vhost per suite |
| SQS/SNS/etc. | LocalStack container (it's a faithful emulator, closer than a client mock) |

Create topics/queues in setup, unique names per worker (`orders-${WORKER_ID}`), delete nothing — the container dies with the state.

### Blockchains: real local network

- **Sui** → `sui start --force-regenesis` (localnet, clean state each run). Fund via local faucet (`sui client faucet` / `http://127.0.0.1:9123/gas`). Deploy the actual Move packages in setup. See the `sui-cli` and `sui-common-ops` skills for command details.
- **Ethereum-like** → **Anvil** (Foundry): `anvil --port 8545` — instant mining, 10 deterministic funded accounts, `anvil_setBalance`/`evm_mine`/`evm_setNextBlockTimestamp` cheatcodes. Hardhat node is the fallback when the project is already Hardhat-based. Fork mode (`anvil --fork-url $RPC`) when the test needs real mainnet contract state.
- Never point e2e tests at public testnets: they're slow, flaky, rate-limited, and shared — everything this tier exists to avoid. Deterministic accounts + regenesis beat faucet-begging.

### External vendor APIs: the only mock

Anything you genuinely cannot run locally (Stripe, OpenAI, a partner's API) gets a **standalone mock server on a real port** — WireMock container, `msw`'s `setupServer` is not enough here; it must be a separate process reachable over TCP so faults can be injected on that hop too. All of `dev-testing`'s mock-fidelity rules apply verbatim: captured real bodies, schema-diffed, provenance comments, real 429/5xx failure shapes.

### SDKs: generate runnable code, run it

Testing an SDK (yours or a vendor's) means **generating a minimal standalone program** that exercises it against the local stack and executing it as a child process — not importing internals into the test runner:

1. Write the smoke program to a temp dir (real `package.json`/`Cargo.toml` resolving the SDK exactly as a user would — from the packed tarball/`cargo package` output, not a path import; path imports skip packaging bugs like missing `files:` entries or broken `exports` maps).
2. Run it (`npm i && node smoke.mjs` / `cargo run`) pointed at the e2e stack's ports via env vars.
3. Assert on its stdout/exit code.

This catches what in-process tests structurally cannot: broken package exports, ESM/CJS mismatches, engine-version constraints, and docs-vs-reality drift in the SDK's own README examples (run those too).

## Network-Fault Injection — Mandatory

Every e2e suite includes fault tests. A suite that only tests the happy path over real sockets is an integration suite with extra steps.

**Tool: Toxiproxy** (container + client libs for Node/Go/Rust/Python/Java). Route each app→dependency hop through a proxy: app → `toxiproxy:26379` → `valkey:6390`, same for DB, broker, mock-vendor, RPC node. The app under test gets the proxy addresses via env config — which conveniently proves your service addresses aren't hardcoded.

Minimum scenario checklist — run each against at least the most critical dependency hop:

| Fault | Toxiproxy toxic | Must assert |
|---|---|---|
| Added latency (300ms–2s) | `latency` | request still succeeds; client timeout > injected latency is honored |
| Hard timeout / black hole | `timeout` (0 data, hold conn) | client times out at its configured deadline, not TCP default (~15 min) |
| Connection refused | disable proxy | clear error surfaced fast; retry/backoff kicks in |
| Reset mid-stream | `reset_peer` / `limit_data` | no partial writes committed; operation is retried or reported, never half-applied |
| Slow/trickling bandwidth | `bandwidth`, `slicer` | streaming code handles fragmented packets; no unbounded buffering |
| Flapping | disable → enable in a loop | reconnect logic recovers; no duplicate side effects (idempotency) |
| Recovery | remove all toxics | system returns to healthy without restart |

The assertions on the right are the point: fault tests verify **behavior under failure** (deadlines honored, idempotent retries, no corrupt state, clean recovery) — not merely "an error was thrown".

For packet-level UDP faults Toxiproxy doesn't cover, use `tc netem` (loss, reorder, duplication) inside the container: `tc qdisc add dev eth0 root netem loss 20%`.

## Suggested Layout & Config

```
e2e/
  docker-compose.e2e.yml    # everything below
  setup.ts / setup.rs       # wait-for-healthy, migrate, create topics, deploy contracts
  helpers/toxi.ts           # proxy handles per dependency
  journeys/*.e2e.test.*     # happy-path journeys
  faults/*.e2e.test.*       # the checklist above
```

Compose skeleton (pin every tag; healthchecks are what `setup` waits on):

```yaml
services:
  postgres:
    image: postgres:17.4
    environment: { POSTGRES_PASSWORD: e2e }
    healthcheck: { test: ["CMD-SHELL", "pg_isready -U postgres"], interval: 1s, retries: 30 }
  valkey:
    image: valkey/valkey:8
    command: valkey-server --save '' --appendonly no --enable-debug-command yes
  redpanda:
    image: redpandadata/redpanda:v24.3.1
    command: redpanda start --mode dev-container --smp 1
  toxiproxy:
    image: ghcr.io/shopify/toxiproxy:2.11.0
    ports: ["8474:8474"]        # control API; per-dep proxy ports added at runtime
  wiremock:
    image: wiremock/wiremock:3.10.0
```

Wiring:
- `test:e2e` script = `docker compose -f e2e/docker-compose.e2e.yml up -d --wait && <runner> e2e/ ; docker compose ... down -v`
- `down -v` always — volumes are state, state is flake
- CI: nightly schedule + manual dispatch + pre-release gate; never in the per-commit fast path
- Local runs must work with a single command from a clean checkout; if setup needs a README paragraph, move it into `setup.ts`

## Anti-Patterns at This Tier

- **In-process shortcuts** — request injection, in-memory DB shims, client-library mocks. They belong in `dev-testing`'s tier; here they void the warranty.
- **Shared long-lived environments** — a "staging" DB or testnet that accumulates state. Fresh per run or it will flake, and flaky e2e suites get deleted.
- **Sleeps instead of readiness** — poll healthchecks/`--wait`; a `sleep 5` is both too long and too short.
- **Happy-path-only** — if the suite has zero toxics, it isn't finished.
- **Testing the fake** — asserting Toxiproxy/WireMock behavior instead of your system's response to it.
