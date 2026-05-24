---
name: valkey
description: Valkey in-memory datastore conventions for Rust and Node.js developers — features, how it differs from Redis, client libraries (redis-rs, fred, valkey-glide, iovalkey, node-redis), Lua/Functions scripting, and common usage patterns and antipatterns. Use when building, reviewing, or debugging code that connects to Valkey (or a Redis-compatible server) for caching, queues, rate limiting, locks, pub/sub, or streams.
---

# Valkey

Valkey is an open-source (BSD-3-Clause), high-performance in-memory key-value datastore governed by the Linux Foundation. It is a community fork of Redis 7.2.4, created in March 2024 after Redis Inc. dropped the BSD license. Apply these conventions when writing Rust or Node.js code that talks to Valkey.

## What Valkey Is and How It Differs From Redis

- **Wire-compatible** with Redis OSS ≤ 7.2 — same RESP2/RESP3 protocol and command set. Any Redis client speaks to Valkey. Migration from open-source Redis ≤ 7.2 is effectively an in-place upgrade.
- **Data-file compatibility:** Valkey reads RDB/AOF from Redis OSS ≤ 7.2. Redis CE 7.4+ data files are **not** compatible (Redis changed format under its new non-open license).
- **License:** Valkey is BSD-3-Clause. Redis 7.4+ is SSPL/RSALv2 (and added AGPL in 2025). Choose Valkey when you need a permissive, vendor-neutral license.
- **Execution model:** command execution remains **single-threaded** (preserving atomic semantics). Valkey 8.0+ added multi-threaded *I/O* (connection accept, RESP parsing, write-buffer flush on dedicated threads) for ~2–3x throughput. Do not assume commands run concurrently — they do not.
- **Version landmarks:**
  - **8.0** — async I/O threading; dual-channel replication; experimental Valkey-over-RDMA.
  - **8.1** — new hashtable (~20 bytes/key less memory, ~30 with TTL), iterator prefetching, TLS-negotiation offload to I/O threads, lower fork copy-on-write overhead.
  - **9.0** — hash field expiration (`HEXPIRE` family), numbered logical DBs in cluster mode, atomic slot migration.
- **Feature divergence from Redis 8.x:** Redis moved JSON, time-series, probabilistic structures, and native vector sets into its core. Valkey keeps the core lean and ships those as **separate official modules**: `valkey-json`, `valkey-bloom`, `valkey-search` (vector/secondary index), `valkey-ldap`. If a project needs JSON documents or vector search, confirm the corresponding module is loaded — it is not built in.
- **Lua difference:** Valkey exposes a `server` global in scripts alongside the Redis-compatible `redis` global (identical API). Prefer `server.*` in new Valkey-only scripts; use `redis.*` for portability.

## Core Capabilities (shared with Redis)

- **Data types:** strings, lists, sets, sorted sets (ZSET), hashes, streams, geospatial indexes, bitmaps/bitfields, HyperLogLog, bloom filters (module).
- **Per-key TTL** via `EXPIRE`/`PEXPIRE`/`SET ... EX`; **per-hash-field TTL** via `HEXPIRE`/`HSETEX`/`HGETEX` (9.0+).
- **Pub/Sub** (`PUBLISH`/`SUBSCRIBE`, sharded pub/sub in cluster), **Streams** with consumer groups, **transactions** (`MULTI`/`EXEC`/`WATCH`), **pipelining**, **keyspace notifications**.
- **Server-assisted client-side caching** (RESP3 tracking / `CLIENT TRACKING`).
- **HA & scale:** replication, Sentinel failover, Cluster mode (hash-slot sharding).
- **Security:** ACLs, TLS, LDAP (module).

## Client Libraries

### Rust
- **`redis` (redis-rs)** — the de-facto standard. Explicitly supports Valkey (CI runs against Valkey 7+). Low-level but ergonomic via the `Commands`/`AsyncCommands` traits. Enable async with a feature flag (`tokio-comp` or `smol-comp`). Connection managers and cluster support available.
- **`fred`** — full-featured async client. No `&mut self` for commands (clones cheaply, friendly with `OnceLock`/`Arc`), built-in reconnection, pooling, cluster, pub/sub, and a `RedisJSON`/scripting interface. Good when you want batteries-included connection management. Works against Valkey over RESP.
- **Valkey GLIDE** core is written in Rust (on top of redis-rs) but is primarily exposed through language wrappers; there is no first-class standalone Rust public API yet — use `redis` or `fred` directly in Rust.

```rust
use redis::AsyncCommands;

let client = redis::Client::open("redis://127.0.0.1:6379")?;
let mut conn = client.get_multiplexed_async_connection().await?; // share this; it pipelines safely
conn.set_ex::<_, _, ()>("session:42", "token", 3600).await?;     // SET ... EX
let token: Option<String> = conn.get("session:42").await?;
```

### Node.js
- **`@valkey/valkey-glide`** — the **official** Valkey client. Rust core with a thin Node binding; cluster-aware topology tracking, robust reconnection, consistent cross-language API. Prefer for new production projects, especially cluster deployments. Has an ioredis migration guide.
- **`iovalkey`** — community fork of `ioredis` (MIT). Drop-in: change `import Redis from 'ioredis'` to `import Redis from 'iovalkey'`. Good when you have existing ioredis code.
- **`redis` (node-redis)** and **`ioredis`** — original Redis clients; work unchanged against Valkey ≤ 7.2 features.

```js
import {GlideClient, TimeUnit} from '@valkey/valkey-glide';

const client = await GlideClient.createClient({
  addresses: [{host: '127.0.0.1', port: 6379}],
});
await client.set('session:42', 'token', {expiry: {type: TimeUnit.Seconds, count: 3600}});
const token = await client.get('session:42');
client.close();
```

Use ESM and a single long-lived client (see [js-conventions]). Never open a connection per request.

## Lua Scripting

Run server-side atomic logic. The whole script executes atomically on the single command thread — keep it fast.

- **`EVAL script numkeys key [key ...] arg [arg ...]`** — run an ephemeral script. **`EVALSHA sha1 ...`** — run a cached script by digest. **`SCRIPT LOAD`** returns the SHA1.
- **Pattern:** call `EVALSHA` first; on `NOSCRIPT` error, fall back to `SCRIPT LOAD` + retry. Most clients (redis-rs `Script`, fred, GLIDE `Script`, ioredis `defineCommand`) do this caching automatically — use their script wrappers instead of raw `EVAL`.
- **Inside scripts:**
  - `server.call(cmd, ...)` raises on error; `server.pcall(cmd, ...)` returns the error as a table. Use `pcall` when you want to handle failure.
  - **All keys must be passed via `KEYS`** (never hard-code or compute key names) — required for cluster slot routing. Non-key data goes in `ARGV`.
  - `server.error_reply(msg)` / `server.status_reply(msg)` build typed replies. `server.sha1hex(s)`, `server.log(level, msg)`.
  - Available libs: `cjson`, `cmsgpack`, `struct`, `bit`, plus `string`/`table`/`math`. `require()` is disabled.
  - **No global variables** — everything must be `local`. Keys are still required to be declared (cluster routing), even though limited non-determinism (`TIME`, randomness) is allowed because only effects replicate.
- **Effects replication (default since 7.0):** only the resulting writes replicate, not the script text — so limited non-determinism is safe. Control with one mode at a time, e.g. `server.set_repl(server.REPL_NONE)` then `server.set_repl(server.REPL_ALL)` to fence which writes propagate (modes: `REPL_ALL`, `REPL_AOF`, `REPL_REPLICA`, `REPL_NONE`).
- **Functions API (persistent, preferred for libraries):** `FUNCTION LOAD "#!lua name=mylib\n..."` registering callbacks via `server.register_function('name', cb)`, invoked with **`FCALL name numkeys ...`** (or `FCALL_RO` for read-only). Functions persist across restarts and replicate; `EVAL` scripts are ephemeral and must be reloaded.
- **Script flags** (functions / shebang EVAL): `no-writes` (enables `_RO` + stale-replica reads), `allow-stale`, `allow-oom`, `no-cluster`, `allow-cross-slot-keys`.

```lua
-- Atomic compare-and-delete (safe distributed-lock release). KEYS[1]=lock, ARGV[1]=token
if server.call('GET', KEYS[1]) == ARGV[1] then
  return server.call('DEL', KEYS[1])
else
  return 0
end
```

## Common Usage Patterns

- **Cache-aside (lazy loading):** `GET` → on miss, load from source, `SET key val EX ttl`. Add **random jitter to TTLs** to prevent synchronized expiry (thundering herd / cache stampede).
- **Atomic counters / rate limiting:** `INCR` + `EXPIRE` (fixed window). For smoother limits use a sliding-window `ZSET` (score = timestamp, trim with `ZREMRANGEBYSCORE`) or a token bucket implemented in one Lua script for atomicity.
- **Distributed lock:** acquire with `SET lock token NX PX ttl`; release with the compare-and-delete Lua above (never a bare `DEL` — you might delete someone else's lock). Understand Redlock's limitations before relying on locks for correctness across nodes.
- **Queues / streams:** prefer **Streams** (`XADD` + consumer groups `XREADGROUP`/`XACK`) over `LPUSH`/`BRPOP` lists when you need acknowledgements, replay, or multiple consumers.
- **Leaderboards / time-ordered data:** sorted sets (`ZADD`, `ZRANGE ... REV`, `ZRANGEBYSCORE`).
- **Session / object fields with independent TTLs:** hashes + `HEXPIRE` (9.0+) instead of many top-level keys.
- **Throughput:** batch round-trips with **pipelining** (or a multiplexed connection); group atomic reads/writes in **Lua** or `MULTI`/`EXEC`.
- **Read scaling:** route reads to replicas (`READONLY` in cluster) when slightly stale data is acceptable; keep writes on the primary.
- **Client-side caching:** enable RESP3 `CLIENT TRACKING` for hot, rarely-changing keys to cut latency and server load.
- Always configure **`maxmemory` + an eviction policy** (`allkeys-lru`, `volatile-ttl`, etc.) when using Valkey as a cache; default `noeviction` will start returning errors on writes when full.

## Antipatterns to Avoid

| Antipattern | Why it hurts | Do instead |
|-------------|-------------|------------|
| `KEYS pattern` in app code | O(N) scan blocks the single command thread | `SCAN` with `MATCH`/`COUNT` (cursor) |
| `DEL bigkey` | Synchronous free blocks the server | `UNLINK` (async reclaim) |
| `HGETALL`/`SMEMBERS`/`LRANGE 0 -1` on huge collections | Large reply spikes memory + latency | `HSCAN`/`SSCAN`/`ZSCAN`, paginate (`LRANGE 0 99`) |
| `FLUSHDB`/`FLUSHALL` | Blocks until everything is freed | `FLUSHDB ASYNC` / `FLUSHALL ASYNC` |
| **Big keys** (multi-MB/GB values, giant hashes) | Memory pressure, slow ops, blocks cluster slot migration (>256MB) | Split into smaller keys; use field-level access (`HGET`/`HMGET`) |
| **Hot keys** (one key, huge traffic) | Saturates a single shard/CPU | Shard the value, add a local/client-side cache, read replicas |
| Heavy/long-running Lua or O(N) commands | Stalls *all* clients (single-threaded execution) | Keep scripts tiny; chunk work; use `SCAN`-based iteration |
| Raw `EVAL` on every call | Resends full script each time | `EVALSHA`/`Script` wrapper or Functions |
| New connection per request | Handshake + FD churn, exhausts limits | One long-lived (multiplexed/pooled) client |
| No `maxmemory`/eviction policy as a cache | OOM or write errors | Set `maxmemory` + eviction policy |
| Keys without TTL in a cache | Unbounded growth | Set TTLs (with jitter) |
| Multi-key ops across slots in cluster | `CROSSSLOT` errors | Co-locate with `{hashtag}` in key names |
| Using `SELECT`/multiple logical DBs for isolation | Not supported in cluster (pre-9.0), confuses tooling | Use key prefixes or separate instances |
| Treating it as a durable primary DB without understanding persistence | Data loss on crash if misconfigured | Configure RDB/AOF deliberately; know the durability tradeoffs |

## Quick Reference

| Need | Command(s) |
|------|-----------|
| Set with expiry | `SET k v EX 3600` / `SET k v PX 60000` |
| Atomic get-set token | `SET k v NX PX 30000` |
| Iterate keyspace | `SCAN 0 MATCH "user:*" COUNT 100` |
| Async big delete | `UNLINK k` |
| Hash field TTL (9.0+) | `HEXPIRE k 60 FIELDS 1 f` / `HSETEX` / `HGETEX` |
| Atomic multi-step | Lua `EVALSHA` / `FCALL` / `MULTI`+`EXEC` |
| Stream consume | `XADD`, `XREADGROUP`, `XACK` |
| Inspect slow ops | `SLOWLOG GET 25` |
| Key size/memory | `MEMORY USAGE k` (sample), `DEBUG OBJECT` (costly) |

## Local Development

```bash
docker run --rm -p 6379:6379 valkey/valkey:8.1
valkey-cli ping   # PONG   (redis-cli also works)
```

The CLI, config directives, and `INFO` fields mirror Redis names (`redis-cli`, `redis://` URLs) for compatibility — Valkey accepts both `valkey-*` and `redis-*` forms.
