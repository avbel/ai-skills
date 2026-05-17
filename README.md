# ai-skills

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

#### Supported agents

| Agent | `--agent` flag | Default install path |
|-------|---------------|----------------------|
| [Claude Code](https://claude.ai/code) | `claude-code` | `~/.claude/skills/` |
| [Cursor](https://www.cursor.com) | `cursor` | `.cursor/rules/` |
| [GitHub Copilot](https://github.com/features/copilot) | `copilot` | `.github/copilot-instructions.md` |
| [Windsurf](https://windsurf.ai) | `windsurf` | `.windsurf/rules/` |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `gemini` | `GEMINI.md` (appended) |

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

### Rust

| Skill | Covers |
|-------|--------|
| `rust-conventions` | Rust 2024 naming, ownership, error handling, traits, iterators, concurrency |
| `rust-async-conventions` | Futures, Send/Sync, join/select, streams, pinning, cancellation |
| `rust-wasm-conventions` | wasm-bindgen, wasm-pack, JS interop, binary size |
| `design-patterns-rust` | Builder, Factory, Singleton, Newtype, Strategy, State, RAII |
| `power-rust` | Prompt patterns that reduce LLM Rust bugs (versions, cancel-safety, SAFETY) |
| `anyhow-rust` | `anyhow::Error`, `bail!`/`ensure!`, error chaining, backtraces |
| `axum-rust` | Router, handlers, extractors, State, tower middleware |
| `clap-rust` | Derive Parser, subcommands, env/default, shell completions |
| `moka-rust` | `sync::Cache`, `future::Cache`, TTL/TTI, eviction, weighted |
| `otel-rust-observable-handles` | Observable instruments, keep-alive pattern, sdk 0.27+ |
| `opentelemetry-rust` | Traces, metrics, logs, OTLP, propagation, sampling |
| `reqwest-rust` | Async client, TLS, JSON/multipart, streaming, retries |
| `tokio-rust` | Runtime, channels, sync primitives, async I/O, `select!`, shutdown |
| `tonic-rust` | gRPC, protobuf codegen, streaming, interceptors, health checks |
| `tower-rust` | `Service`, `Layer`, timeouts, buffers, rate limits, retries |

### TypeScript / JavaScript

| Skill | Covers |
|-------|--------|
| `js-conventions` | Node.js 24+, pnpm, ESM, ES2024, async/await, type safety |
| `typescript-6` | TS 6.0 new defaults, `Temporal`, upsert, subpath imports |
| `design-patterns-ts` | GoF patterns with idiomatic TypeScript |
| `fastify-js` | Fastify 5 plugins, schemas, hooks, error handling, testing |
| `vitest-js` | vitest.config, `vi` mocking, snapshots, coverage, browser mode |
| `cacheable-js` | Keyv, L1/L2, wrap/memoize, hooks, distributed sync |
| `clickhouse-js` | MergeTree, schema, aggregates, materialized views, Node client |
| `close-with-grace-js` | Graceful shutdown for servers, queues, workers, CLI daemons |
| `duckdb-js` | SQL, complex types, window functions, Parquet/CSV I/O |
| `nodejs-26` | Temporal, V8 14.6, Undici 8, ffi, removals |
| `opentelemetry-js` | OTel traces, metrics, SDK, auto-instrumentation, exporters |
| `parquet-js` | File structure, encodings, compression, hyparquet, DuckDB |
| `pino-js` | Log levels, child loggers, redaction, transports |
| `postgres-js` | Tagged templates, transactions, dynamic SQL, cursors, TypeScript |

### Sui / Move

| Skill | Covers |
|-------|--------|
| `move-conventions` | Aptos/Sui dialect, naming, objects, capabilities, events, OTW |
| `sui-cli` | Network/address management, `ptb`, publish/upgrade, keytool |
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
