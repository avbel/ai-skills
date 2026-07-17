---
name: rust-cookbook
description: Task-to-crate recipe index for common Rust jobs — random, async runtimes, CLI parsing, compression, crypto, databases, date/time, logging, encoding (CSV/JSON/TOML), filesystem traversal, networking, external commands, math, regex, and HTTP clients. Use when implementing a routine Rust task and you need the idiomatic crate plus a working pattern.
---

# Rust Cookbook

Idiomatic recipes for common Rust tasks, adapted from *Cookin' with Rust*. Each recipe is **task → crate → pattern**. This skill is the broad index; where a dedicated skill exists (`reqwest-rust`, `clap-rust`, `tokio-rust`, `anyhow-rust`, `walkdir-rust`, `tempfile-rust`, `clickhouse`, `rocksdb`, `sui-sdk-js`...), defer to it for depth.

## How to use

1. Find the task category below.
2. Use the crate named — these are the cookbook's current, battle-tested choices. Confirm the latest version on `crates.io`/`docs.rs` before pinning.
3. Adapt the pattern. Prefer returning `anyhow::Result<T>` from fallible recipe code and propagating with `?` (see `anyhow-rust`).

> Crate baseline: `regex 1.12`, `semver 1.0`, `num 0.4`, `chrono 0.4`, rand 0.9 (`rand::rng()`), clap 4 (`Command`/derive). These recipes assume a **recent toolchain** — `std::sync::LazyLock`/`LazyCell` (used below over `lazy_static`) need **Rust 1.80+**, and rand 0.9 dropped `thread_rng()`/`gen_range`. Check your MSRV before pinning; on older toolchains fall back to `lazy_static`/`once_cell` and rand 0.8 APIs.

## Crate selection map

| Task area | Reach for | Notes |
|-----------|-----------|-------|
| Randomness | `rand`, `rand_distr` | `rand::rng()`, `random_range` |
| Async runtime | `tokio` | `#[tokio::main]`; see `tokio-rust` |
| CLI args | `clap` | derive or builder; see `clap-rust` |
| Compression | `flate2`, `tar` | gzip + tarballs |
| Data parallelism | `rayon` | drop-in parallel iterators |
| Thread pools / channels | `crossbeam`, `threadpool`, std | message passing |
| Hashing / crypto | `ring` | SHA-256, HMAC, PBKDF2 |
| SQLite | `rusqlite` | sync, embedded |
| Async SQL | `sqlx` | compile-time checked queries |
| Postgres (sync) | `postgres` | |
| ORM | `sea-orm` | async, dynamic |
| Date / time | `chrono` | `Utc::now()`, parse/format |
| Logging | `log` + `env_logger`/`log4rs`, `syslog` | facade + backend |
| Structured tracing | `tracing` | spans/events |
| Versioning | `semver` | parse/bump/match ranges |
| Encoding | `base64`, `data-encoding`, `percent-encoding` | hex/base64/url |
| CSV | `csv` (+ `serde`) | |
| JSON / TOML | `serde_json`, `toml` | with `serde` derive |
| Endianness | `byteorder` | LE/BE integers |
| Dir traversal | `walkdir`, `glob`, `same-file` | see `walkdir-rust` |
| Temp files | `tempfile` | see `tempfile-rust` |
| Memory map | `memmap2` | random file access |
| CPU count | `num_cpus` | |
| Linear algebra | `ndarray`, `nalgebra` | matrices/vectors |
| Numeric / bignum / complex | `num` | |
| Regex | `regex` | `LazyLock<Regex>` for statics |
| Unicode | `unicode-segmentation` | graphemes |
| HTTP client | `reqwest` | see `reqwest-rust` |
| HTML scraping | `scraper` | the cookbook shows `select` (obsolete) — prefer `scraper` |
| URL / MIME | `url`, `mime` | |
| WebAssembly host | `wasmtime` | embed/run guests |
| Errors | `anyhow` (apps), `thiserror` (libs) | see `anyhow-rust` |

## Algorithms — randomness & sorting

```rust
// rand 0.9: each thread has a generator via rand::rng()
use rand::Rng;
let mut rng = rand::rng();
let n: u32 = rng.random();              // any u32
let d = rng.random_range(1..=6);        // inclusive range
let pw: String = (0..16).map(|_| rng.sample(rand::distr::Alphanumeric) as char).collect();
```

Sorting: `v.sort()` for `Ord`; `v.sort_by(|a, b| a.partial_cmp(b).unwrap())` for floats; `v.sort_by_key(|s| s.field)` for structs (`sort_by_cached_key` if the key is expensive).

## Asynchronous

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> { /* ... */ Ok(()) }
```

Need control over worker threads? Use the builder instead of the macro:
```rust
let rt = tokio::runtime::Builder::new_multi_thread().enable_all().build()?;
rt.block_on(async { /* ... */ });
```
Channels: `tokio::sync::mpsc::channel(n)` (bounded) / `unbounded_channel()`. Race with `tokio::select!`; shutdown on `tokio::signal::ctrl_c()`; fan out + await with `JoinSet`. See `tokio-rust`, `rust-async-conventions`.

## Command line — clap

```rust
use clap::Parser;
#[derive(Parser)]
struct Cli { #[arg(short, long)] name: String, #[arg(short, long, default_value_t = 1)] count: u8 }
let cli = Cli::parse();
```
Colored terminal output: the cookbook uses `ansi_term`, but it's **archived/unmaintained** — prefer `anstyle` (the ecosystem standard, used by clap/cargo), `owo-colors`, or `nu-ansi-term`. See `clap-rust`.

## Compression — flate2 + tar

```rust
use flate2::read::GzDecoder;
use tar::Archive;
let mut a = Archive::new(GzDecoder::new(std::fs::File::open("archive.tar.gz")?));
a.unpack(".")?;                          // extract all
// compress: tar::Builder::new(GzEncoder::new(file, Compression::default()))
//   .append_dir_all("backup", "/src/dir")?;
```

## Concurrency & parallelism

- **Scoped threads** (borrow stack data safely): `std::thread::scope(|s| { s.spawn(|| ...); })`.
- **Global mutable state**: `static X: LazyLock<Mutex<T>> = LazyLock::new(|| Mutex::new(..))`.
- **Data parallelism — rayon** (drop-in): `v.par_iter_mut().for_each(|x| ...)`, `v.par_iter().any(pred)`, `v.par_sort()`, `data.par_iter().map(..).reduce(id, op)`.
- **Pipelines / passing data**: `crossbeam::channel` or `std::sync::mpsc`; `threadpool` for a fixed worker pool.
- **Actor pattern**: a `tokio::spawn`ed task owning state, driven by an mpsc `Receiver<Message>`; clients hold a `Handle` wrapping the `Sender`.

## Cryptography — ring

```rust
use ring::digest::{Context, SHA256};
let mut ctx = Context::new(&SHA256);
ctx.update(chunk);                        // loop over file reads
let digest = ctx.finish();                // digest.as_ref() -> &[u8]
```
HMAC: `ring::hmac` (sign + `verify`). Password hashing: `ring::pbkdf2` with a random salt from `ring::rand::SystemRandom`. Never roll your own crypto. `ring` is fast but has a C/asm build and stricter platform/MSRV needs — the pure-Rust **RustCrypto** crates (`sha2`, `hmac`, `pbkdf2`, `argon2`) are often easier to compose and build; for passwords prefer `argon2` over PBKDF2 in new code.

## Data structures

Bitfields: `bitflags!`. Collections recipes are plain std — `HashMap` entry API for word frequency/grouping (`*map.entry(k).or_insert(0) += 1`), `BTreeMap` range queries, `HashSet` set ops (`union`/`intersection`/`difference`), `BinaryHeap` for priority order, `VecDeque` for sliding windows.

## Database

```rust
// rusqlite (sync, embedded)
let conn = rusqlite::Connection::open("app.db")?;
conn.execute("CREATE TABLE IF NOT EXISTS person (id INTEGER PRIMARY KEY, name TEXT)", [])?;
let mut stmt = conn.prepare("SELECT id, name FROM person")?;
let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
```
Wrap multi-statement writes in `conn.transaction()?` then `tx.commit()?`.

```rust
// sqlx (async, compile-time checked with the query! macros)
let pool = sqlx::sqlite::SqlitePool::connect("sqlite:app.db").await?;
let row = sqlx::query!("SELECT name FROM person WHERE id = ?", id).fetch_one(&pool).await?;
```
Sync Postgres → `postgres::Client`. Dynamic/async ORM → `sea-orm`. For OLAP/columnar see `clickhouse`; for embedded KV see `rocksdb`.

## Date & time — chrono

```rust
use chrono::{Utc, Local, DateTime, Duration};
let now = Utc::now();
let later = now + Duration::hours(2);
let ts = now.timestamp();                              // -> Unix seconds
let back: DateTime<Utc> = DateTime::from_timestamp(ts, 0).unwrap();
let s = now.format("%Y-%m-%d %H:%M:%S").to_string();
let parsed = DateTime::parse_from_rfc3339("2024-01-01T00:00:00Z")?;
```
Use `checked_add_signed`/`checked_sub_signed` for overflow-safe arithmetic. Timezone conversion via `.with_timezone(&Local)`.

## Development tools — logging, versioning, build

```rust
// log facade + env_logger backend; control with RUST_LOG=debug
log::error!("failed: {e}");  log::debug!("state = {state:?}");
fn main() { env_logger::init(); }
```
Per-module levels and custom output via `env_logger::Builder` or a `log4rs.yaml` config; Unix syslog via `syslog`. Structured spans → `tracing` + `tracing_subscriber::fmt::init()` (see `tracing-rust`).

```rust
// semver
use semver::{Version, VersionReq};
let mut v = Version::parse("1.2.3")?;  v.patch += 1;
let req = VersionReq::parse(">=1.2, <2.0")?;
assert!(req.matches(&v));  let pre = !v.pre.is_empty();
```
Build-time linking of bundled C/C++: the `cc` crate in `build.rs` (`cc::Build::new().file("src/foo.c").compile("foo")`).

## Encoding

```rust
use base64::{Engine, engine::general_purpose::STANDARD};
let b64 = STANDARD.encode(bytes);  let raw = STANDARD.decode(&b64)?;
let hex = data_encoding::HEXUPPER.encode(bytes);
let enc = percent_encoding::utf8_percent_encode(s, percent_encoding::NON_ALPHANUMERIC).to_string();
```
CSV — `csv::Reader::from_reader(..)`; `.deserialize::<Row>()` into `#[derive(Deserialize)]` structs; write with `csv::Writer` + `.serialize(row)`. JSON — `serde_json::json!`/`from_str`/`to_string`, `serde_json::Value` for unstructured. TOML config — `toml::from_str::<Config>(..)`. Endianness — `byteorder` `ReadBytesExt`/`WriteBytesExt` with `LittleEndian`/`BigEndian`.

## Error handling

Apps: return `anyhow::Result<()>` from `main`, add context with `.with_context(|| ..)`, construct with `anyhow!`/`bail!`/`ensure!`. Libraries: define error enums with `thiserror` `#[derive(Error)]` + `#[from]`. See `anyhow-rust`, `eyre-rust`.

## File system

```rust
let s = std::fs::read_to_string("f.txt")?;            // whole file
std::fs::write("f.txt", "data")?;                     // whole file
for line in std::io::BufReader::new(std::fs::File::open("f.txt")?).lines() { /* line? */ }
```
Atomic replace: write to a `tempfile::NamedTempFile`, then `.persist(target)?` (same filesystem). Random access: `memmap2::Mmap`. Traversal: `walkdir::WalkDir::new(dir)` (filter dotfiles with `.filter_entry`, control depth with `.max_depth`), `glob::glob("**/*.png")?` for patterns, `same-file` to detect path loops. See `walkdir-rust`, `tempfile-rust`.

## Hardware & memory

CPU cores: `num_cpus::get()`. Lazy statics — prefer std over `lazy_static`:
```rust
use std::sync::LazyLock;                  // thread-safe, global
static TABLE: LazyLock<Vec<u32>> = LazyLock::new(|| (0..100).collect());
// std::cell::LazyCell for single-threaded / !Sync init
```

## Networking

Std is enough for most TCP/UDP work:
```rust
let listener = std::net::TcpListener::bind("127.0.0.1:0")?;   // :0 = OS-assigned port
for stream in listener.incoming() { /* echo: io::copy(&mut s, &mut s.try_clone()?) */ }
let stream = std::net::TcpStream::connect_timeout(&addr, Duration::from_secs(5))?;
stream.set_read_timeout(Some(Duration::from_secs(2)))?;
stream.set_nodelay(true)?;                                    // disable Nagle
```
UDP via `UdpSocket::bind`/`send_to`/`recv_from`, multicast with `join_multicast_v4`. Resolve names with `addr.to_socket_addrs()`. Classify with `IpAddr::is_loopback`/`is_multicast`. Async/large-scale → tokio (`tokio-rust`).

## Operating system — external commands

```rust
let out = std::process::Command::new("git").args(["log", "--oneline"]).output()?;
if !out.status.success() { anyhow::bail!("git failed: {}", String::from_utf8_lossy(&out.stderr)); }
let stdout = String::from_utf8(out.stdout)?;
```
Stream output: `.stdout(Stdio::piped()).spawn()?` then read `child.stdout` with a `BufReader`. Pipe commands by feeding one child's stdout into the next's `Stdio::from`. Env vars: `std::env::var("KEY")`.

## Science — math

- Matrices/vectors: `ndarray` (`array![[1.,2.],[3.,4.]]`, `a.dot(&b)`, broadcasting) or `nalgebra` (`Matrix3`, `.try_inverse()`, `.norm()`).
- Complex numbers & big integers: `num` (`Complex::new(re, im)`, `BigInt`, `BigUint`).
- Stats/trig: std `f64` methods (`.sin()`, `.sqrt()`); mean/median/stddev computed directly over slices.

## Text processing — regex

```rust
use std::sync::LazyLock;
use regex::Regex;
static EMAIL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[\w.+-]+@[\w-]+\.[\w.-]+$").unwrap());
if let Some(c) = EMAIL.captures(input) { /* &c[1] */ }
let cleaned = RE.replace_all(text, "$1");
```
Compile regexes **once** in a `LazyLock` static, never inside a loop. Unicode graphemes: `unicode_segmentation::UnicodeSegmentation::graphemes(s, true)`. Custom parsing: `impl FromStr for MyType`.

## Web programming

```rust
// reqwest GET (see reqwest-rust for client reuse, TLS, JSON, streaming)
let body = reqwest::get(url).await?.text().await?;
```
Scrape links from HTML with `scraper` (`Html::parse_document(&html).select(&Selector::parse("a").unwrap())`) — the cookbook's `select` crate is obsolete. Parse/manipulate URLs with `url::Url` (`join`, `origin`, `set_fragment(None)`). MIME types via `mime`/`mime_guess`. GitHub-style REST: `reqwest::Client` with `serde` structs; check existence with a `HEAD` request and inspect `status()`.

## WebAssembly host — wasmtime

```rust
let engine = wasmtime::Engine::default();
let module = wasmtime::Module::from_file(&engine, "guest.wasm")?;
let mut store = wasmtime::Store::new(&engine, ());
let instance = wasmtime::Instance::new(&mut store, &module, &[])?;
let f = instance.get_typed_func::<i32, i32>(&mut store, "run")?;
let r = f.call(&mut store, 41)?;
```
Share linear memory via `instance.get_memory`; expose host functions to guests with a `Linker` + `func_wrap`; WASI via `wasmtime_wasi`.

## Cross-references

- HTTP clients → `reqwest-rust` · Async → `tokio-rust`, `rust-async-conventions`, `futures-util-rust`
- CLI → `clap-rust` · Errors → `anyhow-rust`, `eyre-rust` · Logging → `tracing-rust`
- FS → `walkdir-rust`, `tempfile-rust` · General style → `rust-conventions`, `design-patterns-rust`
- Design patterns → `design-patterns-rust` · Databases → `clickhouse`, `rocksdb`
