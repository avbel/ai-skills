
# ai-skills

<p align="center">
  <img src="logo.png" alt="ai-skills logo" width="500">
</p>

A curated collection of coding-convention skills for [Claude Code](https://claude.ai/code), [Codex](https://openai.com/index/openai-codex), [OpenCode](https://opencode.ai), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [GitHub Copilot](https://github.com/features/copilot), [Cursor](https://www.cursor.com), and 50+ more agents. Each skill teaches your AI agent the idioms, patterns, and constraints of a specific library or language so you stop explaining the same things over and over.

## Installation

### via pnpm / npm (recommended)

Install one skill into your Claude Code skills directory:

```bash
# pnpm
pnpm dlx skills add avbel/ai-skills -s vitest-js

# npm
npx skills add avbel/ai-skills -s vitest-js
```

Install multiple skills at once:

```bash
pnpm dlx skills add avbel/ai-skills -s rust-conventions -s anyhow-rust -s tokio -s axum-rust
```

Install all skills from this repo:

```bash
pnpm dlx skills add avbel/ai-skills --all
```

List available skills:

```bash
pnpm dlx skills list avbel/ai-skills
```

The installer auto-detects your agent and copies files to the right location. Pass `--agent` to override.


```bash
# install for Cursor
pnpm dlx skills add avbel/ai-skills -s vitest-js --agent cursor

# install for GitHub Copilot
pnpm dlx skills add avbel/ai-skills -s vitest-js --agent copilot
```

#### Custom destination

```bash
# Install to a project-local .claude/skills directory
pnpm dlx skills add avbel/ai-skills -s vitest-js --dest .claude/skills

# Install to claude.ai project knowledge export directory
pnpm dlx skills add avbel/ai-skills -s vitest-js --dest ./export
```

---

### Manual installation (Claude Code)

Clone the repo once, then copy the skills you need:

```bash
git clone https://github.com/avbel/ai-skills.git /tmp/ai-skills

# single skill
cp -r /tmp/ai-skills/skills/vitest-js ~/.claude/skills/

# multiple skills
cp -r /tmp/ai-skills/skills/rust-conventions \
       /tmp/ai-skills/skills/anyhow-rust \
       /tmp/ai-skills/skills/tokio \
       ~/.claude/skills/
```

---

### claude.ai (Projects)

1. Open your project → **Knowledge** tab → **Add**
2. Paste the contents of `skills/<skill-name>/SKILL.md`

Or drop the file directly — claude.ai accepts markdown uploads.

## Available Skills

### Rust — libs & tools

| Skill | Covers |
|-------|--------|
| `anyhow-rust` | `anyhow::Error`, `bail!`/`ensure!`, error chaining, backtraces |
| `asupersync-rust` | Cx, regions, cancellation, channels, HTTP server demos |
| `axum-rust` | Router, handlers, extractors, State, tower middleware |
| `clap-rust` | Derive Parser, subcommands, env/default, shell completions |
| `divan-rust` | Cargo bench setup, Bencher, counters, allocation profiling |
| `dotenvy-rust` | `.env` loading, override modes, iteration, env-specific config |
| `eyre-rust` | `Report`, `WrapErr`, custom handlers, `eyre!`, anyhow migration |
| `futures-util-rust` | `StreamExt`, `FutureExt`, `TryStreamExt`, `select!`, `join`, sinks |
| `google-cloud-secret-manager-rust` | Secret Manager, ADC/IAM, versioned lookup |
| `hotpath-rs` | Rust profiling: timing, allocations, CPU, Tokio, MCP |
| `high_performance_rust` | Build config, allocators, type sizes, hashers, hot-path I/O, rayon, profiling |
| `hud-tokio-profiler` | eBPF zero-instrumentation profiler for Tokio worker blocking; tool comparison |
| `moka-rust` | `sync::Cache`, `future::Cache`, TTL/TTI, eviction, weighted |
| `nanoprogress-rust` | Terminal progress bar conventions  |
| `otel-observable-handles-rust` | Observable instruments, keep-alive pattern, sdk 0.27+ |
| `opentelemetry-rust` | Traces, metrics, logs, OTLP, propagation, sampling |
| `reqwest-rust` | Async client, TLS, JSON/multipart, streaming, retries |
| `rxrust-rust` | Observables, contexts, subjects, schedulers, async interop |
| `smol-rust` | `block_on`, spawn, Executor, Timer, `Async<T>`, async-compat, smol vs tokio |
| `tempfile-rust` | `NamedTempFile`, `TempDir`, `SpooledTempFile`, `Builder`, persist |
| `tokio-rust` | Patterns, anti-patterns, module reference, sync primitives, alternatives |
| `tokio-stream-rust` | `StreamExt`, `ReceiverStream`, `StreamMap`, timeout, throttle |
| `tonic-rust` | gRPC, protobuf codegen, streaming, interceptors, health checks |
| `tower-rust` | `Service`, `Layer`, timeouts, buffers, rate limits, retries |
| `tracing-rust` | Spans, events, `#[instrument]`, subscriber, layers, structured logging |
| `walkdir-rust` | Recursive directory walk, `DirEntry`, `filter_entry`, depth control |

### Rust — language & patterns

| Skill | Covers |
|-------|--------|
| `rust-conventions` | Rust 2024 naming, ownership, error handling, traits, iterators, concurrency |
| `rust-nightly` | Nightly feature gates, unstable std, -Z tooling, platforms |
| `rust-async-conventions` | Futures, Send/Sync, join/select, streams, pinning, cancellation |
| `rust-wasm-conventions` | wasm-bindgen, wasm-pack, JS interop, binary size |
| `design-patterns-rust` | Idioms, GoF patterns (Builder/Strategy/State/RAII), anti-patterns, principles |
| `cookbook_rust` | Task-to-crate recipe index: random, async, CLI, compression, db, regex, HTTP |
| `macros_rust` | macro_rules! fragments/repetitions/hygiene, TT munchers, proc macros (syn/quote) |
| `high_assurance_rust` | Static/dynamic/operational assurance, threat modeling, unsafe discipline, supply-chain, fuzzing |
| `power-rust` | Prompt patterns that reduce LLM Rust bugs (versions, cancel-safety, SAFETY) |

### JavaScript / TypeScript — libs & tools

| Skill | Covers |
|-------|--------|
| `biome-js` | Biome formatter, linter, XO migration, VS Code |
| `fastify-js` | Fastify 5 plugins, schemas, hooks, error handling, testing |
| `hono-js` | Routing, middleware, validation, RPC, CLI docs/search |
| `vitest-js` | vitest.config, `vi` mocking, snapshots, coverage, browser mode |
| `cacheable-js` | Keyv, L1/L2, wrap/memoize, hooks, distributed sync |
| `clickhouse-js` | MergeTree, schema, aggregates, materialized views, Node client |
| `close-with-grace-js` | Graceful shutdown for servers, queues, workers, CLI daemons |
| `duckdb-js` | SQL, complex types, window functions, Parquet/CSV I/O |
| `google-cloud-secret-manager-js` | Secret Manager setup, ADC/IAM, rotation, typed lookup |
| `opentelemetry-js` | OTel traces, metrics, SDK, auto-instrumentation, exporters |
| `parquet-js` | File structure, encodings, compression, hyparquet, DuckDB |
| `pino-js` | Log levels, child loggers, redaction, transports |
| `postgres-js` | Tagged templates, transactions, dynamic SQL, cursors, TypeScript |

### JavaScript / TypeScript — language & patterns

| Skill | Covers |
|-------|--------|
| `js-conventions` | Node.js 24+, pnpm, ESM, ES2024, async/await, type safety |
| `typescript-6` | TS 6.0 new defaults, `Temporal`, upsert, subpath imports |
| `nodejs-26` | Temporal, V8 14.6, Undici 8, ffi, removals |
| `node-rust-addon` | Rust-backed Node native addons, FFI, async |
| `design-patterns-ts` | GoF patterns with idiomatic TypeScript |
| `manual-testing-node-js` | Env setup, docker DB + migrations, SUI contracts, plan + execute |

### Datastores (Rust & JavaScript / TypeScript)

| Skill | Covers |
|-------|--------|
| `valkey` | Features, Redis differences, Rust/Node clients, Lua, patterns/antipatterns |
| `clickhouse` | OLAP features, JSON/Variant types, async inserts, Rust/Node clients, antipatterns |
| `rocksdb` | LSM architecture, column families, compaction, Rust/Node bindings, antipatterns |

### Development Cycle

Cross-language workflow skills sharing one philosophy: cheapest sufficient process, KISS, second opinions, compounding knowledge. Start with `dev-cycle`.

| Skill | Covers |
|-------|--------|
| `dev-cycle` | Router and shared philosophy for the dev-* skill set |
| `dev-feature` | Fast path for small features: clarify, plan, implement |
| `dev-problem-solving` | Brainstorm approaches, decide, solution doc, reviewed build plan |
| `dev-review` | Orchestrated review: spec audit, security pass, edge cases, second opinion |
| `dev-testing` | Integration tests first, in-memory DBs, verified API mocks |
| `dev-e2e-testing` | Production-parity e2e: real services, local chains, network-fault injection |
| `dev-debug` | Root-cause debugging, debugger configs for IDEs and CLI |
| `dev-knowledge` | Capture solved problems as linked notes in docs/knowledge |
| `dev-code-style` | Moderate comments, no comment noise, self-documenting code |

### Practices

| Skill | Covers |
|-------|--------|
| `code-review` | Production-focused reviews: observability, compat, migrations, idempotency, PR quality |
| `gemini-review-code` | Delegate a local git code review to Antigravity (`agy`) |
| `claude-review-code` | Delegate a local git code review to Claude Code (`claude`, Opus/xhigh) |

### CI / DevOps

| Skill | Covers |
|-------|--------|
| `git` | Auth, merge/rebase, cleanup, executable bits, LFS, performance |
| `github-cli` | gh auth, repos, PRs, issues, runs, releases, API |
| `github-actions-ci` | pnpm/Rust/Docker CI, workflow_dispatch, caching, flow validation |
| `docker-compose` | compose.yaml, services, build/deploy/develop, networks, secrets |
| `k3s` | lightweight Kubernetes, edge, workers, storage, autoscaling, secrets |

### Sui / Move

| Skill | Covers |
|-------|--------|
| `move-conventions` | Aptos/Sui dialect, naming, objects, capabilities, events, OTW |
| `sui-cli` | Network/address management, `ptb`, publish/upgrade, keytool |
| `sui-common-ops` | Common Sui queries and unsigned PTB bytes |
| `sui-local-dev-usdc` | Local Sui dev network, mock USDC coin, faucet, mint balances |
| `sui-kiosk-sdk-js` | `@mysten/kiosk`, KioskTransaction, listings, royalties |
| `sui-sdk-js` | `@mysten/sui`, transactions, keypairs, BCS, zkLogin |
| `walrus-sdk-js` | `@mysten/walrus`, blob reads/writes, upload relay, WASM |

## Usage

Once a skill is installed, Claude Code loads it on-demand when you ask about a relevant topic. You can also invoke it explicitly:

```
/vitest-js
/rust-conventions
```

No extra configuration needed — skills are auto-discovered from `~/.claude/skills/`.

## Creating a New Skill

See [AGENTS.md](./AGENTS.md) for the full authoring guide, directory structure, `SKILL.md` format, and script requirements.

```
skills/
  my-skill/
    SKILL.md        # skill definition (frontmatter + markdown)
    scripts/        # optional bash scripts
      bootstrap.sh
```

## License

MIT
