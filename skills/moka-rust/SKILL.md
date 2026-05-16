---
name: moka-rust
description: Use when building or reviewing Rust in-memory caches with moka: sync::Cache, future::Cache, CacheBuilder, get_with/try_get_with read-through loading, TTL/TTI expiration, weighted eviction, eviction listeners, invalidation, run_pending_tasks, async cache usage, and cache testing.
---

# Moka Rust

Use these conventions for Rust in-memory caches built with `moka-rs/moka`.

## Source Baseline

- Prefer released docs from `docs.rs/moka`, crates.io, and the matching GitHub release over older snippets.
- Current docs.rs baseline checked for this skill: `moka 0.12.15`.
- Moka provides thread-safe, concurrent in-memory caches inspired by Caffeine.
- Current MSRV checked for `sync` and `future`: Rust `1.71.1`.
- At least one crate feature, `sync` or `future`, must be enabled.
- Moka can bound caches by maximum entry count or total weighted size, supports TTL/TTI and per-entry expiration, and supports eviction listeners.
- Moka returns cloned values from cache reads. Store `Arc<T>` when values are expensive to clone.

## Cargo

Use the synchronous cache for sync code:

```toml
[dependencies]
moka = { version = "0.12", features = ["sync"] }
```

Use the futures-aware cache for async services:

```toml
[dependencies]
moka = { version = "0.12", features = ["future"] }
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
```

Enable both only when a crate genuinely needs both APIs:

```toml
moka = { version = "0.12", features = ["sync", "future"] }
```

## Choose the Cache

- Use `moka::sync::Cache` for normal threaded sync code.
- Use `moka::future::Cache` in async Rust so loading/invalidation can await without blocking the runtime.
- Use `mini-moka` rather than `moka` for single-threaded or lighter non-concurrent use cases.
- Prefer one cache per coherent data domain and key type; avoid one global catch-all cache.
- Wrap large or shared values in `Arc<T>` because `get`, `get_with`, and related APIs return cloned values.

## Sync Cache

```rust
use moka::sync::Cache;
use std::{sync::Arc, time::Duration};

#[derive(Debug)]
struct User {
    id: u64,
    name: String,
}

fn user_cache() -> Cache<u64, Arc<User>> {
    Cache::builder()
        .max_capacity(10_000)
        .time_to_live(Duration::from_secs(300))
        .time_to_idle(Duration::from_secs(60))
        .build()
}

fn load_user(cache: &Cache<u64, Arc<User>>, id: u64) -> Arc<User> {
    cache.get_with(id, || {
        Arc::new(User {
            id,
            name: format!("user-{id}"),
        })
    })
}
```

- `get_with` evaluates the init closure only on a miss and inserts the returned value.
- Concurrent `get_with` calls for the same absent key are coalesced into one init closure evaluation; other callers wait for the same result.
- Use `try_get_with` for fallible loaders. Errors are not cached and are returned wrapped in `Arc<E>`.
- Use `optionally_get_with` when a miss loader can legitimately decide not to cache anything.

## Future Cache

```rust
use moka::future::Cache;
use std::{sync::Arc, time::Duration};

#[derive(Debug)]
struct User {
    id: u64,
    name: String,
}

fn user_cache() -> Cache<u64, Arc<User>> {
    Cache::builder()
        .max_capacity(10_000)
        .time_to_live(Duration::from_secs(300))
        .time_to_idle(Duration::from_secs(60))
        .build()
}

async fn load_user(cache: &Cache<u64, Arc<User>>, id: u64) -> Arc<User> {
    cache
        .get_with(id, async move {
            Arc::new(User {
                id,
                name: format!("user-{id}"),
            })
        })
        .await
}
```

- Await async cache operations such as `insert`, `invalidate`, `get_with`, `try_get_with`, and `optionally_get_with`.
- Do not use `moka::sync::Cache` with blocking loaders inside async request paths unless the loader is known to be cheap and non-blocking.
- For fallible async loading, use `try_get_with` and convert `Arc<E>` into the local error shape.

## Read-Through Loading

Prefer read-through methods over manual check-then-insert code.

```rust
let value = cache.try_get_with(key.clone(), || load_from_disk(&key))?;
```

Avoid this pattern:

```rust
if let Some(value) = cache.get(&key) {
    return Ok(value);
}
let value = load_from_disk(&key)?;
cache.insert(key, value.clone());
Ok(value)
```

The manual pattern can duplicate expensive work under concurrency. `get_with` and `try_get_with` coalesce concurrent loads for the same key.

## Capacity and Weight

Use `max_capacity` for entry-count bounding. Use `weigher` when entries have meaningfully different memory or operational cost.

```rust
use moka::sync::Cache;

let cache: Cache<String, String> = Cache::builder()
    .weigher(|_key, value: &String| value.len().try_into().unwrap_or(u32::MAX))
    .max_capacity(32 * 1024 * 1024)
    .build();
```

- The weigher returns a `u32` relative size.
- With a weigher, `max_capacity` is the total weighted size, not entry count.
- Weighted sizes constrain capacity; they are not used when choosing which entries to evict.
- Capacity eviction is best effort under concurrency; do not treat it as an exact memory limit.

## Expiration

Use TTL for absolute lifetime after write and TTI for idle lifetime after last read.

```rust
use moka::sync::Cache;
use std::time::Duration;

let cache = Cache::builder()
    .max_capacity(10_000)
    .time_to_live(Duration::from_secs(30 * 60))
    .time_to_idle(Duration::from_secs(5 * 60))
    .build();
```

- TTL starts from insert/update and is not extended by reads.
- TTI is extended by reads such as `get`.
- If both TTL and TTI are configured, the earliest expiration wins.
- Durations longer than 1000 years can panic during cache build.
- Use custom `Expiry` only when expiration depends on key/value state; keep it deterministic and cheap.

## Eviction and Invalidation

- Use `invalidate(&key)` for one key and `invalidate_all()` only for deliberate broad cache resets.
- Use `invalidate_entries_if` only after enabling builder support with `support_invalidation_closures()`.
- Eviction listeners receive `Arc<K>`, `V`, and `RemovalCause`.
- `RemovalCause` includes `Expired`, `Explicit`, `Replaced`, and `Size`; use `was_evicted()` when only eviction-vs-explicit matters.
- Eviction listeners must not panic. After a panic, the cache intentionally stops calling that listener.
- In async caches, use `async_eviction_listener` when the listener needs to await.

## Maintenance and Metrics

Moka buffers read/write recordings and performs maintenance lazily.

- Maintenance can be triggered by writes, some reads, invalidation calls, or explicit `run_pending_tasks()`.
- Counts such as `entry_count()` are estimates under concurrency and pending expiration/removal.
- Call `run_pending_tasks()` before exact-ish assertions in tests or before reading cache policy stats for diagnostics.
- Instrument hit/miss/load/error behavior around the cache; Moka is not a replacement for operational metrics.

## Testing

- Test the loader, cache policy, and caller behavior separately.
- Use small capacities and short TTL/TTI durations in focused tests.
- Call `run_pending_tasks()` before asserting entry count after expiration or invalidation.
- Use `get_with`/`try_get_with` tests to prove concurrent loads are coalesced when duplicated work matters.
- Avoid sleeping long wall-clock durations; inject a clock or keep TTL tests tiny when the project does not have time-control helpers.

## Helper Script

Generate starter snippets without loading extra context:

```bash
bash /mnt/skills/user/moka-rust/scripts/moka-rust-bootstrap.sh sync
bash /mnt/skills/user/moka-rust/scripts/moka-rust-bootstrap.sh future
bash /mnt/skills/user/moka-rust/scripts/moka-rust-bootstrap.sh try-get
bash /mnt/skills/user/moka-rust/scripts/moka-rust-bootstrap.sh weighted
bash /mnt/skills/user/moka-rust/scripts/moka-rust-bootstrap.sh eviction
```

The script prints JSON with a `scenario`, `cargo`, and `snippet` field.

## Review Checklist

- Is the correct API selected: `sync::Cache` for sync code, `future::Cache` for async loaders?
- Are expensive values wrapped in `Arc<T>` instead of cloned deeply on every hit?
- Is read-through loading done with `get_with` or `try_get_with`, not manual check-then-insert?
- Is capacity bounded by entry count or weighted size intentionally?
- Are TTL and TTI semantics correct for the data freshness contract?
- Are eviction listeners non-panicking and cheap, or async when they need to await?
- Are invalidation and `invalidate_all` scoped narrowly?
- Do tests call `run_pending_tasks()` before assertions affected by lazy maintenance?

## Sources

- `https://github.com/moka-rs/moka`
- `https://docs.rs/moka/latest/moka/`
- `https://docs.rs/moka/latest/moka/sync/struct.Cache.html`
- `https://docs.rs/moka/latest/moka/sync/struct.CacheBuilder.html`
- `https://docs.rs/moka/latest/moka/future/struct.Cache.html`
- `https://docs.rs/moka/latest/moka/future/struct.CacheBuilder.html`
- `https://docs.rs/moka/latest/moka/notification/enum.RemovalCause.html`
- `https://docs.rs/moka/latest/moka/policy/trait.Expiry.html`
