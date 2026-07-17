---
name: parquet-js
description: Apache Parquet format conventions — file structure, data types, encodings, compression, schema design, predicate pushdown, and Node.js/TypeScript libraries (hyparquet, parquet-wasm, DuckDB). Use when reading, writing, or designing Parquet-based data pipelines.
---

# Apache Parquet (JavaScript)

Apply these conventions when working with Apache Parquet files.

## File Structure

```
"PAR1" magic bytes
[Row Group 1: Column Chunk 1, Column Chunk 2, ..., Column Chunk N]
[Row Group 2: Column Chunk 1, Column Chunk 2, ..., Column Chunk N]
...
File Metadata (Thrift-encoded)
4-byte metadata length (LE)
"PAR1" magic bytes
```

- **Row Group** — horizontal partition; each contains one column chunk per column. Processed independently (parallelism unit).
- **Column Chunk** — all data for one column within one row group. Contiguous in file.
- **Page** — smallest unit of compression/encoding. Types: Data Page, Dictionary Page, Index Page.
- Metadata is at the **end** (footer) — enables single-pass writing; readers grab schema/stats from the last few bytes.

## Primitive Types

| Type | Size | Notes |
|------|------|-------|
| `BOOLEAN` | 1 bit | Bit-packed |
| `INT32` | 4 bytes | LE |
| `INT64` | 8 bytes | LE |
| `FLOAT` | 4 bytes | IEEE 754 |
| `DOUBLE` | 8 bytes | IEEE 754 |
| `BYTE_ARRAY` | variable | 4-byte length prefix + bytes |
| `FIXED_LEN_BYTE_ARRAY` | fixed | Length in schema |

Avoid `INT96` — deprecated (was for nanosecond timestamps). Use `INT64 TIMESTAMP` instead.

## Logical Types (on top of primitives)

| Logical Type | Primitive | Description |
|---|---|---|
| `STRING` | BYTE_ARRAY | UTF-8 text |
| `DATE` | INT32 | Days since epoch |
| `TIMESTAMP(unit, isAdjustedToUTC)` | INT64 | Millis/micros/nanos since epoch |
| `TIME(unit, isAdjustedToUTC)` | INT32/INT64 | Time of day |
| `DECIMAL(precision, scale)` | INT32/INT64/BYTE_ARRAY | Exact decimal |
| `UUID` | FIXED_LEN_BYTE_ARRAY(16) | RFC 4122 |
| `JSON` | BYTE_ARRAY | JSON document |
| `INT(8,16,32,64)` signed/unsigned | INT32/INT64 | Narrower integer widths |
| `LIST` | Group (3-level nesting) | Ordered collection |
| `MAP` | Group (3-level nesting) | Key-value pairs |

Always annotate primitives with logical types (`STRING` not raw `BYTE_ARRAY`, `DATE` not raw `INT32`).

Nested types use **definition levels** (how many optional fields are defined) and **repetition levels** (at what level a value repeats) — the Dremel encoding model.

## Encodings

| Encoding | Best For |
|---|---|
| `PLAIN` | Baseline, all types |
| `RLE_DICTIONARY` | Low-to-medium cardinality columns (default, falls back to PLAIN if dictionary too large) |
| `DELTA_BINARY_PACKED` | Sorted/sequential INT32/INT64 |
| `DELTA_LENGTH_BYTE_ARRAY` | Variable-length byte arrays |
| `DELTA_BYTE_ARRAY` | Sorted strings (front compression) |
| `BYTE_STREAM_SPLIT` | Noisy FLOAT/DOUBLE data |
| `RLE / Bit-Packing` | Booleans, def/rep levels |

Dictionary encoding: dictionary page written first per column chunk, data pages store RLE/bit-packed indices. Disable for very high cardinality (UUIDs, timestamps).

## Compression

| Codec | Trade-off |
|---|---|
| `SNAPPY` | Fast, moderate compression — **default choice**, maximum compatibility |
| `ZSTD` | Best modern choice — tunable speed/ratio |
| `GZIP` | Slower, better compression — storage-sensitive workloads |
| `LZ4_RAW` | Very fast — low-latency reads |
| `BROTLI` | Best compression — archival/cold storage |

Compression is applied **per page** (after encoding).

## Configuration

| Parameter | Default | Guidance |
|---|---|---|
| Row group size | ~128 MB | 128 MB – 1 GB. Larger = fewer groups, better sequential reads |
| Page size | ~8 KB | Smaller = finer predicate pushdown; larger = better compression |
| Dictionary page size | ~1 MB | Increase for high-cardinality columns you still want dictionary-encoded |
| Enable dictionary | true | Disable for very high cardinality (UUIDs, full timestamps) |
| Enable statistics | true | Never disable — essential for predicate pushdown |
| Enable bloom filter | false | Enable for equality/IN filters on high-cardinality columns |

## Predicate Pushdown & Column Pruning

**Column pruning:** Read only needed columns — skipping a column costs zero I/O in columnar format.

**Predicate pushdown (3 levels):**
1. **Row group pruning** — min/max statistics per column per row group; skip groups that can't match.
2. **Bloom filter pruning** — membership check for equality predicates; skip groups without the value.
3. **Page pruning** — per-page min/max (page index); skip pages within a column chunk.

**Key practice:** Sort data by columns used in filter predicates — makes min/max ranges non-overlapping, dramatically improving skip rates.

## Node.js Libraries

### hyparquet — Pure JS, Zero Dependencies

Best for: lightweight reads, browser apps, HTTP range fetches, plain JS objects.

```typescript
import {
  asyncBufferFromFile,
  asyncBufferFromUrl,
  parquetMetadataAsync,
  parquetQuery,
  parquetReadObjects,
  parquetSchema,
} from 'hyparquet'

const file = await asyncBufferFromFile('data.parquet')
const rows = await parquetReadObjects({ file })

// Column selection + row range
const subset = await parquetReadObjects({
  file,
  columns: ['name', 'score'],
  rowStart: 0,
  rowEnd: 100,
})

// Query/filter with row-group pruning from statistics
const filtered = await parquetQuery({
  file,
  columns: ['name', 'score'],
  filter: { score: { $gte: 90 }, country: { $eq: 'US' } },
  useBloomFilters: true, // opt-in; helps $eq/$in when files contain bloom filters
})

// Metadata only
const metadata = await parquetMetadataAsync(file)
const schema = parquetSchema(metadata)

// From URL (browser, uses HTTP range requests)
const remoteFile = await asyncBufferFromUrl({
  url: 'https://example.com/data.parquet',
  requestInit: { headers: { Authorization: 'Bearer token' } },
})
```

Returns plain JS objects. `parquetRead` streams via `onChunk` and `onPage`; `onPage` emits `pathInSchema: string[]`, not `columnName`. Writing via `hyparquet-writer` (`parquetWriteBuffer`, `parquetWriteFile`): specify types/schemas for empty or ambiguous columns; use per-column `bloomFilter` for equality filters. Extra codecs via `hyparquet-compressors` (gzip, brotli, LZ4, ZSTD, LZ4_RAW; LZO is not currently implemented).

### parquet-wasm — Rust/WASM, Arrow-native

Best for: Arrow pipelines, full read/write, large files (~1.2 MB bundle).

```typescript
import { readParquet, writeParquet, WriterPropertiesBuilder, Compression, Table } from 'parquet-wasm/node'
import { tableFromIPC, tableToIPC, tableFromArrays } from 'apache-arrow'
import fs from 'node:fs'

// Read
const wasmTable = readParquet(new Uint8Array(fs.readFileSync('data.parquet')))
const table = tableFromIPC(wasmTable.intoIPCStream()) // consumes wasmTable

// Write
const data = tableFromArrays({ id: [1, 2, 3], name: ['a', 'b', 'c'] })
const dataWasm = Table.fromIPCStream(tableToIPC(data, 'stream'))
const props = new WriterPropertiesBuilder().setCompression(Compression.ZSTD).build()
const parquetBytes = writeParquet(dataWasm, props)
dataWasm.free()
fs.writeFileSync('out.parquet', parquetBytes)
```

Use the ESM/browser entry (`parquet-wasm` or `parquet-wasm/esm`) only after `await initWasm()`; the Node entry initializes synchronously but still keeps Arrow tables in WASM memory until `free()`/`into*()` consumes them.

### @duckdb/node-api — SQL on Parquet

Best for: complex queries, joins, aggregations, automatic predicate pushdown (~30 MB). Client setup, version pin, and general usage live in the `duckdb-js` skill — below is only the Parquet-specific surface.

```typescript
import { DuckDBInstance } from '@duckdb/node-api'

const db = await DuckDBInstance.create()
const conn = await db.connect()

// Query Parquet directly with SQL — no import step
const reader = await conn.runAndReadAll(
  `SELECT name, count(*) AS cnt FROM 'events.parquet'
   WHERE event_date >= '2025-01-01' GROUP BY name ORDER BY cnt DESC LIMIT 10`
)
console.table(reader.getRows())

// Write Parquet
await conn.run(`COPY (SELECT * FROM 'input.csv') TO 'output.parquet'
  (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000)`)

// Glob patterns
await conn.runAndReadAll(`SELECT * FROM 'data/**/*.parquet' LIMIT 100`)
```

### Library Comparison

| | hyparquet | parquet-wasm | @duckdb/node-api |
|---|---|---|---|
| Bundle | ~10 KB | ~1.2 MB | ~30 MB |
| Read/Write | Read (writer separate) | Both | Both (via SQL) |
| Output | Plain JS objects | Arrow Tables | Arrow / rows |
| Browser | Yes | Yes | No (use duckdb-wasm) |
| SQL | No | No | Yes |
| Predicate pushdown | Row-group stats; opt-in bloom filters | Partial | Full (automatic) |
| Dependencies | Zero | WASM binary | Native binary |

## Best Practices

1. **Sort by filter columns** — improves statistics effectiveness for predicate pushdown.
2. **Use ZSTD** for modern workloads; SNAPPY for maximum compatibility.
3. **Target 128–512 MB row groups** — balances parallelism vs. metadata overhead.
4. **Enable bloom filters** on high-cardinality equality-filtered columns.
5. **Always specify only needed columns** — unneeded columns are skipped on disk/network.
6. **Use logical types** — always annotate primitives with their semantic type.
7. **Partition large datasets** into multiple files by a key column (date, region) for file-level pruning.
8. **For streaming large files**, use `onChunk`/`onPage` (hyparquet), `readParquetStream` (parquet-wasm), or `connection.stream()` (DuckDB) — avoid full materialization.

## Type Mapping (JS)

| Parquet | JavaScript |
|---|---|
| INT32, INT64 (small) | `number` |
| INT64 (large) | `bigint` |
| FLOAT, DOUBLE | `number` |
| BYTE_ARRAY (UTF8) | `string` |
| BOOLEAN | `boolean` |
| TIMESTAMP | `Date` |
| LIST | `Array` |
| MAP | `Object` / `Map` |
