---
name: clickhouse-js
description: ClickHouse database conventions — MergeTree engines, schema design, ORDER BY optimization, data types, aggregate functions with combinators, materialized views, Node.js client patterns, and query best practices. Use when writing or modifying code that queries ClickHouse or designs ClickHouse schemas.
---

# ClickHouse Schema & Query Conventions

Apply these conventions when working with ClickHouse databases.

## Engine Selection

| Use Case | Engine | Notes |
|---|---|---|
| General analytics | `MergeTree` | Default choice |
| Deduplicate by key | `ReplacingMergeTree(ver)` | Use `FINAL` or `GROUP BY` in queries for correctness |
| Pre-aggregate sums | `SummingMergeTree` | Auto-sums numeric cols on merge |
| Custom aggregations | `AggregatingMergeTree` | With `AggregateFunction` columns + `-State`/`-Merge` |
| Mutable data (ordered inserts) | `CollapsingMergeTree(sign)` | sign=+1 insert, sign=-1 cancel |
| Mutable data (any order) | `VersionedCollapsingMergeTree(sign, ver)` | Safe with concurrent inserts |

## CREATE TABLE

```sql
CREATE TABLE [IF NOT EXISTS] [db.]table (
    col1 Type [DEFAULT|MATERIALIZED|ALIAS expr] [CODEC(codec)] [TTL expr],
    col2 Type,
    INDEX idx_name expr TYPE bloom_filter GRANULARITY 4
) ENGINE = MergeTree
ORDER BY (col1, col2)         -- defines sort order + sparse primary index
PARTITION BY toYYYYMM(date)   -- optional, keep < 1000 partitions
PRIMARY KEY (col1)            -- optional, defaults to ORDER BY; must be its prefix
SAMPLE BY intHash32(user_id)  -- optional, enables SAMPLE queries
TTL timestamp + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192
```

**Column modifiers:** `DEFAULT expr` (stored, computed if omitted), `MATERIALIZED expr` (stored, hidden from `SELECT *`), `ALIAS expr` (computed on-the-fly, not stored), `EPHEMERAL` (not stored, input-only for other defaults).

**Codecs:** `ZSTD(1)` general-purpose. `Delta + ZSTD` for monotonic values (timestamps, counters). Per-column: `col UInt32 CODEC(Delta(4), ZSTD(1))`.

## Data Types

**Integers:** `UInt8/16/32/64/128/256`, `Int8/16/32/64/128/256` — use the smallest that fits.
**Floats:** `Float32/64` — approximate; use `Decimal(P,S)` for exact math (money).
**Strings:** `String` (default), `FixedString(N)` (fixed-width codes/hashes), `LowCardinality(String)` (dictionary-encoded, use when < ~10K distinct values — major compression win).
**Date/Time:** `Date` (day precision, 2 bytes), `DateTime('UTC')` (second precision, 4 bytes), `DateTime64(3)` (milliseconds). Prefer `DateTime` unless sub-second needed.
**Enum:** `Enum8('a'=1, 'b'=2)` — fixed categorical values.
**Special:** `UUID`, `IPv4`, `IPv6`, `JSON`, `Dynamic`, `Variant(...)`, `Time`, `Time64`, `Array(T)`, `Tuple(T1,T2)`, `Map(K,V)`, `Nested(...)`, geo (`Point`, `Ring`, `Polygon`, `MultiPolygon`).
**Nullable(T):** Adds overhead (separate bitmap) — avoid unless truly needed. Use defaults (0, `''`) instead.

## ORDER BY / Primary Key Design

- ClickHouse uses a **sparse index**: one entry per granule (8192 rows by default).
- **Put columns used in WHERE first**, ordered by **ascending cardinality** (low-cardinality first).
- First column uses binary search; subsequent columns use generic exclusion.
- Filtering on columns NOT in ORDER BY causes full granule scans.
- For `ReplacingMergeTree`: ORDER BY is the dedup key — must uniquely identify a row.

**Skip indexes** for columns not in ORDER BY: `INDEX idx col TYPE minmax|bloom_filter|set(N)|ngrambf_v1(3,256,2,0) GRANULARITY N`.

## SELECT (ClickHouse-Specific)

```sql
SELECT [DISTINCT] ... FROM table [FINAL] [SAMPLE 0.1]
[ARRAY JOIN arr_col AS alias]
[PREWHERE highly_selective_filter]  -- reads fewer columns from disk
[WHERE ...]
[GROUP BY ... [WITH ROLLUP|CUBE|TOTALS]]
[ORDER BY ... LIMIT 3 BY user_id]   -- top-N per group
[SETTINGS max_threads=4]
[FORMAT JSONEachRow]
```

- **FINAL** — forces on-read dedup for Replacing/CollapsingMergeTree. Expensive but necessary for correctness before background merges complete.
- **PREWHERE** — filters before reading non-referenced columns. Often auto-applied; use explicitly for highly selective filters.
- **ARRAY JOIN** — unnests arrays into rows. `LEFT ARRAY JOIN` preserves rows with empty arrays.
- **LIMIT BY** — returns up to N rows per distinct value (different from LIMIT).
- **SAMPLE** — approximate but deterministic sampling (requires `SAMPLE BY` in table definition).

## INSERT Best Practices

```sql
INSERT INTO table FORMAT JSONEachRow {"col1": 1} {"col1": 2}
INSERT INTO table SELECT ... FROM other_table
```

- **Batch inserts:** 10K–100K+ rows per insert. Each INSERT creates a data part; many small inserts cause merge pressure.
- Ideal: ~1 insert/second with many rows.
- For high-frequency small inserts: `SET async_insert = 1, wait_for_async_insert = 1` — ClickHouse buffers and batches automatically.
- Block-level deduplication is for idempotent retries, not business-level dedup.

## Mutations (UPDATE/DELETE)

**Lightweight DELETE (preferred):**
```sql
DELETE FROM table WHERE condition  -- rows hidden immediately, removed at merge
```

**Mutation DELETE/UPDATE (heavyweight, async):**
```sql
ALTER TABLE t DELETE WHERE condition    -- rewrites entire parts
ALTER TABLE t UPDATE col = expr WHERE condition
```
Track: `SELECT * FROM system.mutations WHERE is_done = 0`. Not for frequent row-level updates.

**ALTER TABLE columns:**
```sql
ALTER TABLE t ADD COLUMN col Type [AFTER existing], DROP COLUMN col,
  MODIFY COLUMN col NewType, RENAME COLUMN old TO new
ALTER TABLE t MODIFY ORDER BY (col1, col2, new_col)  -- can only APPEND columns
```

## Aggregate Functions

**Standard:** `count()`, `sum()`, `avg()`, `min()`, `max()`, `any()`, `anyLast()`.

**ClickHouse-specific (key ones):**
- `uniq(x)` — approximate unique count (~2% error, fast). `uniqExact(x)` for exact.
- `quantile(0.95)(x)` — approximate percentile. `quantileExact`, `quantileTDigest` variants.
- `argMin(val, cmp)` / `argMax(val, cmp)` — value at row with min/max of another column. Common: `argMax(status, updated_at)`.
- `groupArray(x)` — collect into array. `groupUniqArray(x)` for unique.
- `topK(N)(x)` — approximate top-N frequent values.
- `windowFunnel(window)(ts, cond1, cond2, ...)` — funnel analysis.
- `retention(cond1, cond2, ...)` — cohort retention.
- `sequenceMatch('(?1)(?2)')(ts, cond1, cond2)` — event sequence matching.
- `sumMap(keys, values)` — sum values by key across rows.

**Combinators (append to any aggregate name):**
- `-If`: `sumIf(x, cond)` — conditional aggregation.
- `-Array`: `uniqArray(arr)` — aggregate across array elements.
- `-State` / `-Merge`: store/combine intermediate states (for AggregatingMergeTree + MVs).
- `-Distinct`: `sumDistinct(x)` — dedup before aggregating.
- `-ForEach`: `sumForEach(arr)` — per-element on arrays.
- Combinators stack: `uniqArrayIf(arr, cond)`.

**Window functions:** `row_number()`, `rank()`, `dense_rank()`, `lag()`, `lead()`, `first_value()`, `last_value()` + any aggregate as window function: `sum(x) OVER (...)`.

## Materialized Views

**Incremental (insert trigger):**
```sql
CREATE MATERIALIZED VIEW mv_name TO target_table AS
SELECT dim, sum(metric) AS metric FROM source GROUP BY dim
```
Runs on each inserted block; shifts compute to insert time.

**Refreshable (scheduled):**
```sql
CREATE MATERIALIZED VIEW mv_name REFRESH EVERY 1 HOUR TO target_table AS
SELECT * FROM source FINAL  -- useful for dedup
```

**Pitfalls:**
- `POPULATE` can miss concurrent inserts — backfill separately.
- JOINs in incremental MVs only trigger on inserts to the source (left) table.
- Too many MVs on one source table degrades insert performance.

## Node.js Client (`@clickhouse/client`)

**Compatibility:** `@clickhouse/client` 1.23.x requires Node.js `>=20` and supports maintained Node 20/22/24/26. Client 1.12.0+ targets ClickHouse 24.8+; older servers are best-effort.

```typescript
import { createClient } from '@clickhouse/client'

const client = createClient({
  url: process.env.CLICKHOUSE_URL ?? 'http://localhost:8123',
  username: process.env.CLICKHOUSE_USER ?? 'default',
  password: process.env.CLICKHOUSE_PASSWORD ?? '',
  database: 'default',
  max_open_connections: 10,
  request_timeout: 30_000,
  compression: { request: { codec: 'gzip' }, response: true },
  use_multipart_params_auto: true,
  clickhouse_settings: { async_insert: 1 },
})
```

**Query (SELECT):**
```typescript
const rs = await client.query({
  query: 'SELECT * FROM users WHERE age > {age:UInt32}',
  query_params: { age: 30 },     // parameterized — prevents SQL injection
  format: 'JSONEachRow',          // do NOT put FORMAT in SQL string
})
const rows = await rs.json()     // or rs.stream() for large results
```

**Insert:**
```typescript
await client.insert({
  table: 'users',
  values: [{ id: 1, name: 'Alice' }, { id: 2, name: 'Bob' }],
  format: 'JSONEachRow',
})
// Also accepts streams: values: fs.createReadStream('data.ndjson')
```

**DDL/Command:**
```typescript
await client.command({
  query: 'CREATE TABLE IF NOT EXISTS t (id UInt32) ENGINE MergeTree ORDER BY id',
})
```

**Key rules:**
- Consume or dispose `ResultSet` promptly — it holds the HTTP connection open. With TS 5.2+/supported runtimes, `using resultSet = await client.query(...)` auto-disposes on scope exit.
- Use `query_params` with `{name:Type}` placeholders, never string interpolation.
- For large `query_params` (large `IN` arrays, embeddings), enable `use_multipart_params_auto`; force `use_multipart_params` only when needed.
- Use `format` option, not `FORMAT` clause in SQL.
- `await client.close()` on shutdown.
- Node compression: `true` means gzip; `{ codec: 'br' }` enables Brotli; `{ codec: 'zstd' }` requires Node `>=22.15.0`. `@clickhouse/client-web` rejects zstd and does not support streaming inserts.
- JS client type mapping: `UInt64/128/256` and `Int64/128/256` come back as strings in JSON formats by default; keep large decimals as strings on insert and cast `Decimal*` to `String` when querying exact values.
- Date caveats: insert `Date`/`Date32` as `'YYYY-MM-DD'` strings; `DateTime`/`DateTime64` may use JS `Date` with `date_time_input_format: 'best_effort'`.
- Do not import from deprecated `@clickhouse/client-common`; import public types from `@clickhouse/client` or `@clickhouse/client-web`. Use `ClickHouseSettingsInterface` for settings helpers shared across Node/Web clients.
- `parseColumnType` is deprecated; use `@clickhouse/datatype-parser` (`parseDataType`) for ClickHouse type-string AST parsing.
- For RowBinary hot paths, prefer `@clickhouse/rowbinary` reader/writer (`@clickhouse/rowbinary/writer` for inserts); the client package also ships RowBinary agent skills under `node_modules/@clickhouse/client/skills/`.
- Pass a raw OpenTelemetry tracer via `tracer` when you need spans; the client has no OTel dependency and tracer exceptions are not swallowed.
- For browser/edge: use `@clickhouse/client-web` (same API, no streaming inserts).

## Schema Design

- **Denormalize:** Wide, flat tables over normalized JOINs. Flatten one-to-many into fact table.
- **LowCardinality(String)** for columns with < 10K distinct values.
- **Avoid Nullable** unless truly needed — use type defaults (0, `''`).
- **Partition by coarse time** (month/year), not day.
- **Pre-aggregate** via materialized views into SummingMergeTree or AggregatingMergeTree.
- Use strict types (`UInt32` not `String` for IDs, `DateTime` not `String` for timestamps).

## Common Pitfalls

1. Treating ReplacingMergeTree as guaranteed dedup — merges are eventual; use `FINAL` or `GROUP BY`.
2. Using `Nullable` everywhere — performance penalty; use defaults instead.
3. Wrong ORDER BY column order — put low cardinality first, high cardinality last.
4. Filtering on columns not in ORDER BY — causes full scans.
5. Single-row inserts — batch 1K+ rows; use async inserts for high-frequency.
6. Using `POPULATE` on MV creation — can miss concurrent inserts.
7. Expecting JOINs in incremental MVs to react to both sides — only left table triggers.
8. Over-partitioning — keep under 1000 partitions.

## Key Functions Quick Reference

**Date/Time:** `toStartOfDay/Hour/Month()`, `dateDiff('unit', a, b)`, `formatDateTime()`, `parseDateTimeBestEffort()`, `toUnixTimestamp()`, `toTimezone()`.
**Array:** `arrayMap(x -> expr, arr)`, `arrayFilter()`, `has()`, `arrayJoin()` (unfolds to rows), `arrayDistinct()`, `arrayReduce('sum', arr)`.
**String:** `splitByChar()`, `replaceRegexpAll()`, `match()`, `multiMatchAny(s, [patterns])` (Hyperscan, fast).
**JSON:** `JSONExtractString(json, 'key')`, `JSONExtractInt()`, `JSONExtractRaw()`, `JSONHas()`.
**Type conversion:** `toUInt32()`, `toString()`, `CAST(x AS Type)`. All have `OrNull`/`OrZero` variants.
**Conditional:** `if(cond, then, else)`, `multiIf(c1, v1, c2, v2, default)`.
**Hash:** `cityHash64()`, `sipHash64()`, `xxHash64()`.

## Table Functions

```sql
SELECT * FROM s3('https://bucket/path/*.parquet', 'Parquet')
SELECT * FROM url('https://api.example.com/data', 'JSONEachRow', 'id UInt32, name String')
SELECT * FROM file('data.csv', 'CSV', 'id UInt32, name String')
SELECT * FROM numbers(1000000)  -- generate test data
SELECT * FROM postgresql('host:5432', 'db', 'table', 'user', 'pass')
```
