---
name: duckdb-js
description: DuckDB conventions — SQL syntax, data types, complex types (LIST/STRUCT/MAP), aggregate functions, window functions, lambda expressions, file I/O (Parquet/CSV/JSON), COPY, ATTACH, Node.js client, and DuckDB-specific SQL extensions. Use when writing queries, schemas, or code that uses DuckDB.
---

Apply these conventions when working with DuckDB.

## Data Types

**Numeric:** `TINYINT` (1B), `SMALLINT` (2B), `INTEGER` (4B), `BIGINT` (8B), `HUGEINT` (16B) + unsigned variants (`UTINYINT`, etc.). `FLOAT` (4B), `DOUBLE` (8B). `DECIMAL(prec, scale)` for exact math. Use smallest type that fits.
**String:** `VARCHAR` (variable-length, aliases: `TEXT`, `STRING`). `BLOB` for binary.
**Date/Time:** `DATE`, `TIME`, `TIMESTAMP` (aliases: `DATETIME`), `TIMESTAMPTZ`, `INTERVAL`. Precision variants: `TIMESTAMP_S`, `TIMESTAMP_MS`, `TIMESTAMP_NS`.
**Other:** `BOOLEAN`, `UUID`, `BIT`, `ENUM`, `JSON` (requires json extension).

**Complex types:**
- `LIST` — variable-length, same-type: `INTEGER[]` or `LIST(INTEGER)`. Literal: `[1, 2, 3]`. Different row lengths OK.
- `ARRAY` — fixed-length, same-type: `INTEGER[3]`. Every row must have same element count.
- `STRUCT` — named fields, different types: `STRUCT(name VARCHAR, age INTEGER)`. Literal: `{'name': 'Alice', 'age': 30}`. All rows must have same keys.
- `MAP` — key-value, variable keys per row: `MAP(VARCHAR, INTEGER)`. Literal: `MAP {'a': 1, 'b': 2}`. Bracket access returns LIST, not scalar.
- `UNION` — tagged union: `UNION(num INTEGER, str VARCHAR)`. Create: `union_value(num := 42)`. Query tag: `union_tag(col)`.
- `ENUM` — ordered set of strings: `CREATE TYPE mood AS ENUM ('happy', 'sad')`. Stored as integers internally. Ordering follows definition order, not lexicographic — always cast literals when comparing: `WHERE p >= 'medium'::priority`.

All complex types nest arbitrarily.

## CREATE TABLE

```sql
CREATE TABLE t (id INTEGER PRIMARY KEY, name VARCHAR NOT NULL, score INTEGER DEFAULT 0);
CREATE OR REPLACE TABLE t (i INTEGER);
CREATE TABLE t AS SELECT * FROM read_csv('data.csv');       -- CTAS
CREATE TABLE t AS FROM 'https://example.com/data.parquet';  -- FROM-first
CREATE TEMPORARY TABLE t (i INTEGER);
```

## DuckDB-Specific SELECT

```sql
-- Star modifiers
SELECT * EXCLUDE (col1, col2) FROM t;
SELECT * REPLACE (price / 100 AS price) FROM t;
SELECT * RENAME (col1 AS height) FROM t;

-- COLUMNS expression (dynamic column selection)
SELECT COLUMNS('sales_.*') FROM t;           -- regex match
SELECT COLUMNS(c -> c != 'id') FROM t;       -- lambda predicate

-- FROM-first (SELECT optional)
FROM t;                                       -- = SELECT * FROM t
FROM t SELECT col1, col2;

-- GROUP BY ALL / ORDER BY ALL
SELECT city, avg(income) FROM t GROUP BY ALL;
SELECT * FROM t ORDER BY ALL;

-- QUALIFY (filter on window functions, no subquery needed)
SELECT *, row_number() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn
FROM employees QUALIFY rn <= 3;

-- UNION BY NAME (match by column name, not position)
SELECT * FROM t1 UNION BY NAME SELECT * FROM t2;

-- DISTINCT ON
SELECT DISTINCT ON (user_id) * FROM events ORDER BY user_id, ts DESC;

-- SAMPLE
SELECT * FROM t USING SAMPLE 10%;

-- SUMMARIZE (quick stats on all columns)
SUMMARIZE t;
```

## INSERT / UPDATE / DELETE

```sql
-- INSERT BY NAME (match columns by name)
INSERT INTO t BY NAME SELECT j, i FROM other;

-- Upsert
INSERT OR REPLACE INTO t VALUES (1, 'updated');
INSERT INTO t VALUES (1, 84) ON CONFLICT (id) DO UPDATE SET val = EXCLUDED.val;
INSERT INTO t VALUES (1, 84) ON CONFLICT DO NOTHING;

-- UPDATE from another table
UPDATE t SET value = n.value FROM new_table n WHERE t.key = n.key;

-- DELETE with USING
DELETE FROM t USING other WHERE t.id = other.id;

-- RETURNING clause (works on INSERT, UPDATE, DELETE)
INSERT INTO t VALUES (1, 'a') RETURNING *;
```

## WITH / CTE

```sql
WITH cte AS (SELECT 42 AS x) SELECT * FROM cte;

-- Recursive
WITH RECURSIVE fib(n, a, b) AS (
    SELECT 0, 0, 1
    UNION ALL
    SELECT n+1, b, a+b FROM fib WHERE n < 10
) SELECT * FROM fib;
```

CTEs are materialized by default. Force: `AS MATERIALIZED (...)` or `AS NOT MATERIALIZED (...)`.

## Aggregate Functions

**Standard:** `count()`, `sum()`, `avg()`, `min()`, `max()`, `string_agg(col, ',')`.

**DuckDB-specific:**
- `arg_min(val, cmp)` / `arg_max(val, cmp)` — value at row with min/max of another column.
- `arg_min(val, cmp, n)` / `arg_max(val, cmp, n)` — top-n as list.
- `any_value(x)` / `first(x)` — arbitrary / first value.
- `approx_count_distinct(x)` — HyperLogLog approximate distinct count.
- `approx_quantile(x, q)` — approximate quantile (t-digest).
- `quantile_cont(x, q)` / `quantile_disc(x, q)` — exact quantiles.
- `median(x)` — shorthand for `quantile_cont(x, 0.5)`.
- `mode(x)` — most frequent value.
- `histogram(x)` — returns MAP of value → count.
- `list(x)` / `array_agg(x)` — collect into LIST.
- `entropy(x)`, `kurtosis(x)`, `skewness(x)` — statistical.
- `mad(x)` — median absolute deviation.
- `product(x)` — multiply all values.

**Modifier:** `FILTER (WHERE cond)` — per-aggregate filtering: `count(*) FILTER (WHERE x > 5)`.

## Window Functions

`row_number()`, `rank()`, `dense_rank()`, `ntile(n)`, `percent_rank()`, `cume_dist()`, `lag()`, `lead()`, `first_value()`, `last_value()`, `nth_value()`.

Any aggregate works as a window function: `sum(x) OVER (...)`.

Use `QUALIFY` to filter without subqueries. Named windows: `WINDOW w AS (PARTITION BY ... ORDER BY ...)`.

## Lambda Functions (LIST operations)

```sql
list_transform([1,2,3], x -> x * 2)         -- [2, 4, 6]
list_filter([1,2,3,4], x -> x > 2)          -- [3, 4]
list_reduce([1,2,3], (x, y) -> x + y)       -- 6
```

## List / Struct / Map Functions

**List:** `list[1]` (1-based), `list[-1]` (last), `list[2:4]` (slice), `list_contains()`, `list_sort()`, `list_distinct()`, `list_concat()` / `||`, `list_aggregate(list, 'sum')`, `len()`, `unnest()`, `flatten()`, `generate_series()`.

**Struct:** `s.field` (dot notation), `struct_extract(s, 'field')`, `struct_pack(k := v)`, `struct_insert(s, k := v)`.

**Map:** `m['key']` (returns LIST), `map_keys(m)`, `map_values(m)`, `map_entries(m)`, `map_from_entries(list)`, `element_at(m, key)`, `cardinality(m)`.

## UNNEST

```sql
SELECT unnest([1, 2, 3]) AS x;                              -- 3 rows
SELECT unnest([1,2,3]) AS a, unnest(['x','y']) AS b;         -- parallel (zip), NULLs for shorter
SELECT unnest({'a': 42, 'b': 84});                           -- struct → columns
SELECT unnest([{'a': 1}, {'a': 2}], recursive := true);      -- fully flatten nested
```

## Pattern Matching

- `LIKE` / `ILIKE` (case-insensitive, DuckDB extension) — `%` any chars, `_` single char.
- `GLOB` — Unix-style: `*`, `?`, `[...]`.
- `regexp_matches(s, pattern)` or `s ~ pattern` — partial match, RE2 syntax.
- `regexp_extract(s, pattern, ['name1','name2'])` — returns STRUCT of named captures.
- `regexp_replace(s, pattern, repl [, 'g'])` — replace first/all.
- `regexp_extract_all(s, pattern)` — LIST of all matches.
- `regexp_split_to_array(s, pattern)` — split to LIST.

## File I/O

**Read directly (no import needed):**
```sql
SELECT * FROM 'data.parquet';
SELECT * FROM read_parquet('data/*.parquet');
SELECT * FROM read_csv('data.csv');
SELECT * FROM read_json('data.ndjson', format = 'newline_delimited');
```

**Glob & multi-file:**
```sql
SELECT * FROM read_parquet('data/**/*.parquet');                            -- recursive
SELECT * FROM read_parquet('data/*.parquet', union_by_name = true);        -- different schemas
SELECT *, filename FROM read_parquet('data/*.parquet');                     -- source file column
```

**Hive partitioning:**
```sql
SELECT * FROM read_parquet('orders/*/*/*.parquet', hive_partitioning = true)
WHERE year = 2024 AND month = 3;    -- file-level pruning on partition columns
```

**Write:**
```sql
COPY tbl TO 'out.parquet' (FORMAT parquet, COMPRESSION zstd);
COPY tbl TO 'out.csv' (FORMAT csv, HEADER true);
COPY tbl TO 'out.ndjson' (FORMAT json);
COPY tbl TO 'dir/' (FORMAT parquet, PARTITION_BY (year, month));           -- Hive-partitioned output
COPY (SELECT * FROM tbl WHERE x > 10) TO 'filtered.parquet' (FORMAT parquet);
```

**Parquet metadata inspection:**
```sql
SELECT * FROM parquet_metadata('data.parquet');
SELECT * FROM parquet_schema('data.parquet');
```

**Export entire database:**
```sql
EXPORT DATABASE 'backup/' (FORMAT parquet);
```

## Remote Files (httpfs)

```sql
SELECT * FROM read_parquet('https://example.com/data.parquet');
SELECT * FROM read_csv('s3://bucket/data.csv');

SET s3_region = 'us-east-1';
SET s3_access_key_id = 'key';
SET s3_secret_access_key = 'secret';
COPY tbl TO 's3://bucket/out.parquet' (FORMAT parquet);
```

## ATTACH (Cross-Database)

```sql
ATTACH 'dbname=mydb host=localhost' AS pg (TYPE postgres);
ATTACH 'mydb.sqlite' AS lite (TYPE sqlite);
ATTACH 'host=localhost database=mydb' AS my (TYPE mysql);

-- Cross-engine joins
SELECT u.name, o.total FROM pg.public.users u
JOIN 'orders.parquet' o ON u.id = o.user_id;
```

## PIVOT / UNPIVOT

```sql
-- PIVOT (rows → columns, dynamic value discovery when IN omitted)
PIVOT sales ON year USING sum(revenue) GROUP BY product;

-- UNPIVOT (columns → rows)
UNPIVOT monthly ON jan, feb, mar INTO NAME month VALUE amount;

-- Dynamic UNPIVOT
FROM monthly UNPIVOT (amount FOR month IN (COLUMNS(* EXCLUDE (id))));
```

## Node.js Client (`@duckdb/node-api`)

Current stable package: `@duckdb/node-api` `1.5.4-r.1` (DuckDB 1.5.4 line; wraps released DuckDB binaries via `@duckdb/node-bindings`). Official docs list Linux glibc/musl (x64/arm64), macOS (x64/arm64), and Windows x64 as supported; do not rely on Windows ARM64 despite the optional npm binary package existing.

```typescript
import { DuckDBInstance } from '@duckdb/node-api'

const db = await DuckDBInstance.create()          // in-memory
// const db = await DuckDBInstance.create('my.duckdb')  // persistent
// const db = await DuckDBInstance.fromCache('my.duckdb') // reuse per-process instance
const conn = await db.connect()

// Query
const reader = await conn.runAndReadAll(
  `SELECT name, count(*) AS cnt FROM 'events.parquet'
   WHERE date >= '2025-01-01' GROUP BY name ORDER BY cnt DESC LIMIT 10`
)
console.table(reader.getRows())

// DDL / COPY
await conn.run(`COPY (SELECT * FROM 'input.csv') TO 'output.parquet'
  (FORMAT parquet, COMPRESSION zstd)`)

// Streaming large results
const reader = await conn.streamAndReadAll(sql)

// Parameterized SQL; values/types can be arrays or named objects
const filtered = await conn.runAndReadAll(
  'SELECT * FROM events WHERE user_id = $user_id AND ts >= $since',
  { user_id: 'u_123', since: '2026-01-01' }
)

// Cross-database
await conn.run(`INSTALL postgres; LOAD postgres;`)
await conn.run(`ATTACH 'dbname=mydb' AS pg (TYPE postgres);`)
```

Use `@duckdb/node-api` for new projects (native Promises, DuckDB-specific API, lossless support for DuckDB types). Legacy `duckdb` is callback-based and SQLite-shaped.

Operational patterns:
- Use `DuckDBInstance.fromCache(path)` when multiple modules in the same Node process may open the same database file; multiple independent instances must not attach the same database.
- Prefer `runAndReadAll()` for bounded results; use `streamAndReadUntil()` / `streamAndRead()` or async chunk iteration for large results.
- For cooperative libuv behavior on long queries, prefer `startStreamThenRead*()` helpers; they combine pending results with streaming so work is split into short tasks without fully materializing the result.
- MAP and UNION support is still incomplete for binding/appending; construct those values in SQL or verify the current API before using appender/prepared-statement paths.
- User-defined types/functions, profiling info, table description, and Arrow APIs are still on the Node Neo roadmap; do not design wrappers assuming those APIs exist.
- Use `getRowsJson()` / `getRowObjectsJson()` when serializing results: BIGINT, DECIMAL, timestamps, INTERVAL, and nested types are converted losslessly for JSON.
- Explicitly close long-lived resources (`connection.closeSync()` / `disconnectSync()`, `instance.closeSync()`) in daemons and tests instead of relying only on GC.

## Key Settings

```sql
SET threads = 8;                     -- worker threads (default: CPU cores)
SET memory_limit = '4GB';           -- max memory
SET temp_directory = '/tmp/duckdb'; -- spill-to-disk location
PRAGMA enable_progress_bar;          -- progress for long queries
EXPLAIN ANALYZE SELECT ...;          -- plan with execution metrics
PRAGMA storage_info('table_name');   -- per-column storage details
```

## Indexing

DuckDB uses **zone maps** (automatic min/max per column chunk) as the primary filtering mechanism. Manual ART indexes exist but are rarely useful — only for point lookups on < 0.1% of rows. Don't create indexes "just in case" like in PostgreSQL.

## Schema Design

- Use smallest types (`TINYINT` over `BIGINT`, `DATE` over `TIMESTAMP`).
- Use `ENUM` for low-cardinality categorical columns — stored as integers, compresses well.
- Sort data before loading — clusters similar values, improves compression and zone map effectiveness.
- Prefer denormalized/flat tables for analytical workloads.
- DuckDB auto-applies compression (RLE, dictionary, bit-packing, FSST, ALP).

## Extensions

Key extensions (most autoload on first use):
- **json** — `read_json()`, `json_extract()`.
- **parquet** — `read_parquet()`, Parquet I/O.
- **httpfs** — HTTP(S) and S3 remote file access.
- **postgres_scanner** / **sqlite_scanner** / **mysql_scanner** — ATTACH external databases.
- **spatial** — geometry types, ST_ functions.
- **fts** — full-text search with BM25 scoring.
- **icu** — collation, timezone, Unicode.
- **vss** — vector similarity search (HNSW).
- **delta** / **iceberg** — data lake table formats.

```sql
INSTALL spatial; LOAD spatial;
SELECT * FROM duckdb_extensions();    -- list installed
```
