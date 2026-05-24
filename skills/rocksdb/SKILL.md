---
name: rocksdb
description: RocksDB embedded LSM-tree key-value store conventions for Rust and Node.js developers — architecture, column families, compaction, transactions, merge operators, BlobDB, bulk ingest, current features (10.x/11.x), library bindings (rocksdb/rust-rocksdb crates; classic-level, @harperfast/rocksdb-js), and usage patterns and antipatterns. Use when embedding RocksDB for local persistence, state stores, queues, or storage engines.
---

# RocksDB

RocksDB is an **embedded** (in-process, no server) persistent key-value store from Meta, based on a log-structured merge-tree (LSM-tree). It is a C++ library forked from LevelDB, optimized for fast storage (SSD/NVMe) and high write throughput. It is the storage engine behind TiKV, CockroachDB, Kafka Streams, Ceph, and many others. Apply these conventions when embedding RocksDB via Rust or Node.js bindings.

## Architecture (why behavior is what it is)

- **Write path:** writes go to the **WAL** (durability) and an in-memory **memtable**. When the memtable fills, it is flushed to an immutable **SST file** at level 0. Background **compaction** merges SSTs down the level hierarchy (L0→L1→…).
- **LSM tradeoffs:** excellent write throughput and sequential I/O, but reads may touch multiple levels (read amplification) and compaction consumes CPU/IO (write amplification). Tuning is about balancing space/read/write amplification for your workload.
- **Ordered keys:** keys are stored sorted by byte order; range scans and prefix iteration are cheap. There is no secondary indexing — model your keys for the access pattern.
- **Single-process ownership:** one process opens the DB read-write (a lock file enforces this). Use a **secondary instance** or **checkpoints** for read-only sharing.

## Core Features

- **Column families** — independent keyspaces in one DB sharing a WAL; per-CF options (comparator, compaction, compression). Use for logical separation (like tables). Atomic writes can span CFs.
- **Compaction styles** — **Leveled** (default; low space/read amp, higher write amp — good for read-heavy), **Universal** (lower write amp, higher space amp — write-heavy), **FIFO** (TTL/cache-like, drops oldest). Pick per workload.
- **Atomic batches** — `WriteBatch` groups writes applied atomically; can disable WAL per-write for speed (at durability cost).
- **Transactions** — `TransactionDB` (pessimistic, locking) and `OptimisticTransactionDB` (conflict-checked at commit). Support snapshots and `GetForUpdate`.
- **Snapshots** — consistent point-in-time read view; iterators can pin a snapshot.
- **Merge operators** — server-side read-modify-write (counters, append-only lists) avoiding read-then-put round trips.
- **Prefix iterators / bloom filters** — `prefix_extractor` + prefix bloom for fast prefix range scans and point lookups.
- **BlobDB (key-value separation)** — store large values in separate blob files (`enable_blob_files`, `min_blob_size`) to cut write amplification on big values.
- **Bulk ingest** — build SST files offline with `SstFileWriter` and `IngestExternalFile` for fast loads (skips the write path).
- **Other** — TTL DB, `DeleteRange` (range tombstones), `MultiGet` (batched point reads), backups/`Checkpoint`, rate limiter, block cache, statistics/`perf_context`.
- **Recent (10.x → 11.x, 2025–2026):** parallel compression CPU overhead cut up to ~65% (10.7); `FlushWAL(FlushWALOptions)` with sync + IO priority (10.8); `max_manifest_space_amp_pct` + larger manifest control (10.8/10.9); FIFO `max_data_files_size` / `use_kv_ratio_compaction` and `index_block_search_type=binary_search` (11.0); `allow_ingest_behind` for backfilling older data (10.6).

## Library Bindings

### Rust
- **`rocksdb`** (crate from the `rust-rocksdb` org) — the widely used wrapper over `librocksdb-sys`. Exposes `DB`, `Options`, `ColumnFamily`, `WriteBatch`, `DBIterator`, `TransactionDB`, merge operators (`MergeFn`), `MultiGet`. Statically linked to a pinned RocksDB; building from source needs **clang/LLVM**.
- **`rust-rocksdb`** (Zaidoon's actively maintained fork, v0.49+) — tracks newer upstream RocksDB releases faster than the base crate. Choose it when you need recent RocksDB features.
- Both have a multi-threaded mode (`DBWithThreadMode`) — share the DB via `Arc<DB>`; the handle is `Send + Sync`.

```rust
use rocksdb::{DB, Options, WriteBatch};

let mut opts = Options::default();
opts.create_if_missing(true);
let db = DB::open(&opts, "/data/state")?;
let mut batch = WriteBatch::default();      // atomic multi-write
batch.put(b"user:1", b"alice");
batch.put(b"user:2", b"bob");
db.write(batch)?;
let v = db.get(b"user:1")?;                 // Option<Vec<u8>>
```

### Node.js
- **`classic-level`** — the maintained Level-ecosystem store (LevelDB under the hood). For RocksDB specifically, the abstract-level RocksDB backends (`rocksdb` / older `level-rocksdb`) expose the same `abstract-level` API (`get`/`put`/`batch`/iterators/sublevels).
- **`@harperfast/rocksdb-js`** — newer native C++ binding with a TypeScript API, full transaction support, lazy range iterators, and prebuilt binaries for major platforms. Prefer it when you need transactions and modern TS ergonomics.
- Bindings are native add-ons — confirm prebuilt binaries exist for your platform/Node version, or expect a source build (node-gyp + a C++ toolchain).

```js
import {RocksDB} from '@harperfast/rocksdb-js';

const db = new RocksDB('/data/state');
await db.open();
await db.put('user:1', 'alice');
const value = await db.get('user:1');
await db.close();
```

## Usage Patterns

- **Model keys for the access pattern:** use sorted, prefixed keys (`user:{id}:posts:{ts}`) so related data is contiguous and range/prefix scans are cheap. There are no joins or secondary indexes — denormalize or maintain index keys yourself (in the same `WriteBatch`).
- **Atomicity via `WriteBatch`/transactions:** group related mutations (and index updates) into one batch so they apply atomically and crash-consistently.
- **Counters/aggregates via merge operators** instead of get→modify→put (avoids races and round trips).
- **Large values → BlobDB** (`enable_blob_files`, tune `min_blob_size`) to keep the LSM tree small and compaction cheap.
- **Bulk load → `SstFileWriter` + `IngestExternalFile`** rather than millions of individual puts.
- **Tune compaction to the workload:** leveled for read-heavy, universal for write-heavy, FIFO for TTL/cache. Set `level_compaction_dynamic_level_bytes = true` for stable leveled space amp.
- **Point-lookup-heavy:** enable a **bloom filter** and a shared **block cache**; consider `optimize_for_point_lookup`.
- **Consistent reads / backups:** take a **snapshot** for a stable iterator view; use **`Checkpoint`** (hard-link based, near-instant) for backups instead of copying files live.
- **Tune for ingest:** raise `write_buffer_size` and `max_write_buffer_number`, increase background jobs (`max_background_jobs`), and use a **rate limiter** to keep compaction from starving foreground I/O.

## Antipatterns to Avoid

| Antipattern | Why it hurts | Do instead |
|-------------|-------------|------------|
| Running with default `Options` in production | Defaults are conservative; wrong for most workloads | Tune memtable, compaction, cache, bloom filters per workload |
| One sync write per operation | `fsync` per write throttles throughput | Batch with `WriteBatch`; use `WriteOptions::disableWAL` only for replayable/ephemeral data |
| Storing large blobs inline | Bloats SSTs, multiplies write amplification in compaction | BlobDB / key-value separation |
| `Get` in a loop for many keys | N round trips through all levels | `MultiGet` (batched, parallel) |
| Full unbounded iteration to find a range | Scans the whole keyspace | Set iterator lower/upper bounds or a `prefix_extractor` |
| Too many column families | Each adds memtables + flush/compaction overhead and complicates WAL recycling | Few CFs; partition within a CF via key prefixes |
| One giant CF for unrelated data with different access patterns | Compaction/compression can't be tuned per dataset | Split by CF when options should differ |
| Leaking iterators / snapshots / CF handles | Pins SST files → unbounded disk growth, blocked compaction | Drop/close them promptly (RAII in Rust; `close` in JS) |
| Frequent manual `CompactRange` in the hot path | Blocks and amplifies I/O | Let background compaction run; tune triggers instead |
| Treating it as a multi-process shared DB | Only one RW process allowed (lock file) | Secondary instance / checkpoint for readers; a service in front for sharing |
| No bloom filter on point-lookup workload | Every miss reads multiple SSTs from disk | Configure prefix/whole-key bloom + block cache |
| No backups, assuming durability = safety | Corruption/bugs lose the only copy | Periodic `Checkpoint` / `BackupEngine` to separate storage |

## Quick Reference

| Need | API (Rust crate) |
|------|------------------|
| Open with options | `DB::open(&opts, path)` / `DB::open_cf(...)` |
| Atomic multi-write | `WriteBatch` + `db.write(batch)` |
| Batched reads | `db.multi_get([...])` / `multi_get_cf` |
| Range tombstone | `db.delete_range_cf(cf, from, to)` |
| Read-modify-write | merge operator (`set_merge_operator`) + `db.merge(k, v)` |
| Prefix scan | set `prefix_extractor`, then `db.prefix_iterator(prefix)` |
| Consistent view | `db.snapshot()` + `ReadOptions::set_snapshot` |
| Backup | `Checkpoint::new(&db)?.create_checkpoint(path)` |
| Bulk load | `SstFileWriter` → `db.ingest_external_file([sst])` |

## Build Notes

- The native library is **statically linked** to a pinned RocksDB version; first build is slow and needs **clang/LLVM** (Rust) or a **C++ toolchain + node-gyp** (Node), unless prebuilt binaries are available.
- Match compression features you enable (zstd/lz4/snappy) with the corresponding system or bundled libraries.
