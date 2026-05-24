---
name: clickhouse
description: ClickHouse columnar OLAP database conventions for Rust and Node.js developers — what it is good/bad at, current features (JSON/Variant/Dynamic types, async inserts, refreshable materialized views, lightweight deletes/updates, vector search), client libraries (clickhouse + clickhouse-rs crates; @clickhouse/client), insert/query patterns, and antipatterns. Use when building analytics, event/log ingestion, or time-series workloads on ClickHouse from application code. For deep ClickHouse schema/MergeTree conventions see the clickhouse-js skill.
---

# ClickHouse

ClickHouse is a column-oriented OLAP database for real-time analytics over large datasets — vectorized execution, heavy compression, and massively parallel queries. It is **append-mostly and analytical**, not a transactional (OLTP) store. This skill covers using it from Rust and Node.js plus patterns/antipatterns; for detailed schema, engine, and `ORDER BY` design see the **clickhouse-js** skill.

## What It Is Good and Bad At

- **Great at:** large aggregations/scans, time-series and event/log analytics, append-heavy ingestion, columnar compression, `GROUP BY`/window/approximate functions over billions of rows.
- **Bad at:** point lookups by primary key, single-row updates/deletes, high-frequency tiny inserts, transactions across rows, foreign-key integrity, frequent mutations. Do not use it as an application's primary OLTP database.
- **Mental model:** data lands in immutable **parts** and is merged in the background (MergeTree family). Dedup, updates, and deletes are *eventually* applied via merges — design queries to tolerate that (e.g. `FINAL` or aggregation).

## Current Features (worth using, 2024–2026)

- **`JSON` data type (GA):** native semi-structured column with per-path subcolumn storage and typed reads — replaces the old `Object('json')`/string-blob approach. Pairs with **`Dynamic`** (one column, many types) and **`Variant(T1, T2, …)`** (tagged union) for flexible schemas.
- **Async inserts** (`async_insert=1`): the server batches many small inserts server-side into larger parts — the standard fix for "many small producers." Tune `wait_for_async_insert`, `async_insert_max_data_size`/`busy_timeout_ms`.
- **Lightweight `DELETE`** and **on-the-fly / lightweight `UPDATE`:** far cheaper than legacy `ALTER TABLE … UPDATE/DELETE` mutations, but still not OLTP — use sparingly.
- **Refreshable materialized views:** scheduled full-refresh MVs (in addition to classic insert-triggered incremental MVs) for periodic rollups/denormalization.
- **Vector search:** approximate-nearest-neighbor indexes for embedding similarity, complementing the analytical core.
- **Query cache, parallel replicas, and projections** for read scaling and alternate sort orders within one table.

## Client Libraries

### Rust
- **`clickhouse`** (the `clickhouse-rs`/ClickHouse-Rust crate, `clickhouse` on crates.io) — the recommended async client. Uses the efficient **RowBinary** format with `#[derive(Row, Serialize, Deserialize)]` structs, HTTP transport, optional `lz4` compression, and a buffered `insert`/`inserter` API for batching. Integrates with `tokio`.
- **`clickhouse-rs`** (the older `suharev7` TCP-native-protocol crate) — still around; prefer the HTTP `clickhouse` crate for new code and broad compatibility (incl. ClickHouse Cloud).

```rust
use clickhouse::{Client, Row};
use serde::Serialize;

#[derive(Row, Serialize)]
struct Event { id: u64, ts: u32, kind: String }

let client = Client::default().with_url("http://localhost:8123").with_database("app");
let mut insert = client.insert("events")?;       // batch many rows into one part
for e in batch { insert.write(&e).await?; }
insert.end().await?;                              // one large insert, not row-by-row
```

### Node.js
- **`@clickhouse/client`** — the official Node client (HTTP/HTTPS). Streaming inserts/selects, multiple formats (`JSONEachRow`, `CSV`, RowBinary via streams), compression, abort signals, connection settings. Use `insert({ table, values, format })` with arrays/streams.
- **`@clickhouse/client-web`** — official browser/edge build (fetch-based) for Cloudflare Workers, Deno, browsers.

```js
import {createClient} from '@clickhouse/client';

const client = createClient({url: 'http://localhost:8123', database: 'app'});
await client.insert({
  table: 'events',
  values: rows,            // array of objects — send large batches, not one row
  format: 'JSONEachRow',
});
const rs = await client.query({query: 'SELECT count() FROM events', format: 'JSONEachRow'});
```

Use one long-lived client; send large batches (see Patterns). Follow [js-conventions] (ESM, async/await).

## Insert & Query Patterns

- **Batch inserts large.** Aim for tens of thousands to millions of rows (or MBs) per insert; one insert = one part. Buffer in the app and flush periodically, or enable **`async_insert`** so the server batches for you when you have many small producers.
- **Insert in `ORDER BY` order when you can** — reduces merge work and improves compression.
- **Use `RowBinary`/typed rows** (Rust `clickhouse` crate, or RowBinary streams in Node) for the fastest, most compact transfer; reserve `JSONEachRow` for convenience/low volume.
- **Pre-aggregate with materialized views** at insert time (incremental MV → `SummingMergeTree`/`AggregatingMergeTree`) so dashboards read small rollups, not raw rows.
- **Deduplicate with `ReplacingMergeTree`** + read-time `FINAL` *or* `GROUP BY`/`argMax(ver)` — never assume duplicates are gone immediately after insert.
- **Filter on `ORDER BY` prefix columns** (low cardinality first) so the sparse primary index can skip granules; add **skip indexes** (`minmax`, `bloom_filter`) for other hot filters.
- **Set TTLs** for retention/tiering (`TTL ts + INTERVAL 90 DAY DELETE` / `TO VOLUME`), and keep partitions coarse (e.g. monthly) — far fewer than 1000.
- **Make retries idempotent:** insert deduplication keys off block content; reuse the same block on retry so ClickHouse dedups it.

## Antipatterns to Avoid

| Antipattern | Why it hurts | Do instead |
|-------------|-------------|------------|
| Many small/frequent inserts (per-row, per-request) | Creates thousands of tiny parts → merge storms, "too many parts" errors | Batch large; or enable `async_insert` |
| Frequent `ALTER TABLE … UPDATE/DELETE` mutations | Rewrites whole parts; very expensive, async, easy to pile up | Use lightweight delete/update sparingly, or model with `ReplacingMergeTree`/`CollapsingMergeTree` |
| `OPTIMIZE TABLE … FINAL` to force merges in prod | Rewrites entire partitions; huge I/O, not for routine use | Trust background merges; use `FINAL` at query time if needed |
| `FINAL` on every query as a habit | Forces merge-on-read, slow on big data | Pre-aggregate; only `FINAL` where correctness needs it |
| High-cardinality column first in `ORDER BY` | Wrecks index granule skipping and compression | Low-cardinality columns first; high-cardinality later |
| Using ClickHouse for point lookups / OLTP | Designed for scans, not single-row get/update | Use a KV/OLTP store; ClickHouse for analytics |
| `SELECT *` on wide tables | Reads every column from disk (columnar) | Select only needed columns |
| Overusing `Nullable(T)` | Extra null bitmap → storage + slower reads | Use sensible defaults (0, `''`) unless null is meaningful |
| Too many partitions (e.g. by day or by id) | Thousands of parts/partitions, slow startup and merges | Coarse `PARTITION BY` (month); keep < ~1000 |
| Huge `IN (subquery)` / unbounded joins | Memory blowups; right table of join is loaded into memory | Use dictionaries for lookups; put the smaller table on the right |
| Reusing OLTP-style schema (normalized, many joins) | Joins are not ClickHouse's strength | Denormalize; use `Dictionary`/`MATERIALIZED` columns |
| Treating async insert as durable-on-ack by default | With `wait_for_async_insert=0` the ack precedes the flush | Keep `wait_for_async_insert=1` unless you accept the risk |

## Quick Reference

| Need | How |
|------|-----|
| Many small producers | `SETTINGS async_insert=1, wait_for_async_insert=1` |
| Fast typed transfer | RowBinary (Rust `clickhouse` crate; RowBinary streams in Node) |
| Dedup by key | `ReplacingMergeTree(ver)` + `FINAL`/`argMax(ver)` at read |
| Rollups at insert | incremental materialized view → `*MergeTree` |
| Periodic rebuild | `REFRESHABLE` materialized view |
| Retention | `TTL ts + INTERVAL n DAY DELETE` |
| Cheap delete | lightweight `DELETE FROM t WHERE …` (sparingly) |
| Semi-structured | `JSON` column (+ `Dynamic`/`Variant`) |

For MergeTree engine selection, codecs, data-type sizing, aggregate-function combinators, and detailed `ORDER BY`/skip-index design, use the **clickhouse-js** skill.
