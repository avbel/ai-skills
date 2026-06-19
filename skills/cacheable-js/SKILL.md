---
name: cacheable-js
description: Cacheable (jaredwray/cacheable) conventions — L1/L2 caching with Keyv, TTL, wrap/memoize, hooks, events, stats, distributed sync, CacheableMemory, cache-manager, and storage adapters. Use when writing or modifying code that imports 'cacheable' or 'cache-manager' for caching.
---

Apply these conventions when working with the Cacheable ecosystem in Node.js/TypeScript projects.

## Package Selection

| Use Case | Package |
|---|---|
| Full L1/L2 caching with hooks, events, stats, sync | `cacheable` |
| NestJS / existing cache-manager users | `cache-manager` |
| Simple in-memory LRU cache | `@cacheable/memory` |
| HTTP response caching | `cacheable-request` |
| Drop-in `node-cache` replacement | `@cacheable/node-cache` |

## Current Stable Baseline

Use npm `latest` as the stable baseline for installable APIs. As of this update: `cacheable@2.3.5`, `@cacheable/memory@2.0.9`, `cache-manager@7.2.8`.

GitHub `main` and the latest GitHub release mention `cacheable@2.4.0` / `@cacheable/memory@2.1.0` features such as `maxTtl`, `CacheableMemoryHooks`, and tag invalidation, but those versions were not present on npm. Do not prescribe those APIs unless the project explicitly depends on a published version that contains them.

## Setup

```typescript
import { Cacheable, CacheableMemory } from 'cacheable'
import { Keyv } from 'keyv'
import { createKeyv as createRedisKeyv } from '@keyv/redis'

// Memory-only
const memoryOnly = new Cacheable()

// L1 memory + L2 Redis
const cache = new Cacheable({
  primary: new Keyv({ store: new CacheableMemory({ ttl: '5m', lruSize: 5000 }) }),
  secondary: createRedisKeyv(process.env.REDIS_URL!),
  ttl: '1h',           // default TTL: ms number or shorthand
  nonBlocking: false,  // true favors latency over L2 freshness
  stats: false,        // true enables instance hit/miss/set/delete stats
  namespace: 'myapp',  // isolate shared stores and sync channels
})
```

Prefer `createKeyv` helpers from Keyv adapters where available; otherwise wrap the adapter with `new Keyv({ store })`.

## TTL Shorthand

`1ms`, `1s`, `1m`, `1h` / `1hr`, `1d` — works anywhere TTL is accepted. `0` or `undefined` disables expiry.

TTL precedence:

```
function-level TTL → storage adapter TTL → cacheable default TTL
```

When promoting from L2 to L1, the remaining TTL from L2 is used, capped by the primary store TTL when configured.

## CRUD

```typescript
await cache.set('key', 'value')
await cache.set('key', 'value', 5000)
await cache.set('key', 'value', '15m')
await cache.setMany([{ key: 'a', value: 1 }, { key: 'b', value: 2, ttl: '5m' }])

const val = await cache.get<string>('key')       // T | undefined
const vals = await cache.getMany<number>(['a', 'b'])
const raw = await cache.getRaw<string>('key')    // raw metadata
const rawMany = await cache.getManyRaw(['a', 'b'])

const exists = await cache.has('key')
const manyExist = await cache.hasMany(['a', 'b'])
const taken = await cache.take('key')
const takenMany = await cache.takeMany(['a', 'b'])

await cache.delete('key')
await cache.deleteMany(['a', 'b'])
await cache.clear()
await cache.disconnect()
```

In v2, use `getRaw()` / `getManyRaw()` rather than `get(key, { raw: true })` when targeting `cacheable`; older docs and `cache-manager` examples may still show raw options.

## L1/L2 Behavior

| Operation | Behavior |
|---|---|
| `set` / `setMany` | Writes primary, then secondary |
| `get` / `getMany` | Reads primary; on miss reads secondary and promotes to primary |
| `delete` / `deleteMany` / `clear` | Applies to both stores |

With `nonBlocking: true`, get-related operations return primary results immediately and repair secondary misses in the background. Override per call with `{ nonBlocking: false }` when read-through freshness matters more than latency.

## Wrap / Memoize

```typescript
const cachedGetUser = cache.wrap(
  async (id: number) => db.findUser(id),
  { ttl: '1h', keyPrefix: 'users' },
)

const user = await cachedGetUser(42)

cache.wrap(fn, {
  ttl: '1h',
  keyPrefix: 'prefix',
  key: 'explicit-key',
  cacheError: false,
  createKey: (_fn, args) => `custom:${args[0]}`,
})
```

Use stable, low-cardinality keys. Never include raw request bodies, secrets, or unordered objects unless you supply a deterministic key serializer.

## getOrSet (Cache-Aside)

```typescript
const user = await cache.getOrSet(
  `user:${userId}`,
  async () => db.findUser(userId),
  { ttl: '30m' },
)
```

Use `getOrSet` for cache-aside reads; use `wrap` when memoizing a function across many call sites.

## Hooks

```typescript
import { CacheableHooks } from 'cacheable'

cache.onHook(CacheableHooks.BEFORE_SET, (data) => {
  console.log(`setting ${data.key}`)
})
cache.removeHook(CacheableHooks.BEFORE_SET)
```

Stable hooks: `BEFORE_SET`, `AFTER_SET`, `BEFORE_SET_MANY`, `AFTER_SET_MANY`, `BEFORE_GET`, `AFTER_GET`, `BEFORE_GET_MANY`, `AFTER_GET_MANY`, `BEFORE_SECONDARY_SETS_PRIMARY`.

## Events

```typescript
import { CacheableEvents } from 'cacheable'

cache.on(CacheableEvents.ERROR, (error) => logger.error({ error }, 'cache error'))
cache.on(CacheableEvents.CACHE_HIT, (data) => metrics.cacheHit(data.store))
cache.on(CacheableEvents.CACHE_MISS, (data) => metrics.cacheMiss(data.store))
```

Always listen for `ERROR` when using network-backed secondary stores.

## Statistics

```typescript
const cache = new Cacheable({ stats: true })

cache.stats.hits
cache.stats.misses
cache.stats.sets
cache.stats.deletes
cache.stats.clears
cache.stats.errors
cache.stats.count
cache.stats.vsize
cache.stats.ksize
cache.stats.reset()
```

Stats are instance-local and do not aggregate distributed L2 stores.

## CacheableMemory (In-Memory Engine)

Use `@cacheable/memory` for standalone use, or the re-export from `cacheable` when already depending on Cacheable.

```typescript
import { CacheableMemory, KeyvCacheableMemory } from 'cacheable'
import { Keyv } from 'keyv'

const mem = new CacheableMemory({
  ttl: '1h',
  lruSize: 5000,         // 0 = no LRU eviction
  useClones: true,       // false shares object references
  checkInterval: 60000,  // 0 = lazy expiry only
  storeHashSize: 16,     // multiple Maps to avoid single-Map limits
})

mem.set('k', 'v')
mem.get('k')
mem.has('k')
mem.delete('k')
mem.clear()
mem.size
mem.getRaw('k')
mem.getManyRaw(['k'])

const keyv = new Keyv({ store: new KeyvCacheableMemory({ ttl: 60000, lruSize: 5000 }) })
const cachedFn = mem.wrap((n: number) => n * 2, { ttl: '1h', key: 'double' })
```

For large objects, consider `useClones: false` only if callers will not mutate cached values.

## cache-manager (NestJS-Compatible)

```typescript
import { createCache } from 'cache-manager'
import { createKeyv, KeyvCacheableMemory } from 'cacheable'
import { Keyv } from 'keyv'
import { createKeyv as createRedisKeyv } from '@keyv/redis'

const cache = createCache({
  stores: [
    createKeyv({ ttl: 60000, lruSize: 5000 }),
    createRedisKeyv(process.env.REDIS_URL!),
  ],
  ttl: 10000,
  refreshThreshold: 3000,
  nonBlocking: false,
})

const explicitMemory = createCache({
  stores: [new Keyv({ store: new KeyvCacheableMemory({ ttl: 60000, lruSize: 5000 }) })],
})
```

`cache-manager` v7 returns `undefined` on misses. For non-JSON in-memory values such as `symbol` or `Uint8Array`, disable Keyv JSON serialization:

```typescript
const keyv = new Keyv()
keyv.serialize = undefined
keyv.deserialize = undefined
```

## Distributed Sync

```typescript
import { Cacheable } from 'cacheable'
import { RedisMessageProvider } from '@qified/redis'

const provider = new RedisMessageProvider({
  connection: { host: 'localhost', port: 6379 },
})

const cache = new Cacheable({
  namespace: 'service-a',
  sync: { qified: provider },
})
```

Sync updates only the primary storage layer of peer instances. Secondary storage is still written by the instance performing the operation. Give each service a `namespace` to isolate Pub/Sub channels; sync is eventually consistent.

## Storage Adapters (via Keyv)

| Store | Package |
|---|---|
| Memory | `@cacheable/memory` / `KeyvCacheableMemory` |
| Redis | `@keyv/redis` |
| Valkey | `@keyv/valkey` |
| Memcache | `@keyv/memcache` |
| MongoDB | `@keyv/mongo` |
| SQLite | `@keyv/sqlite` |
| PostgreSQL | `@keyv/postgres` |
| MySQL | `@keyv/mysql` |
| Etcd | `@keyv/etcd` |

## Production Pitfalls

- Cache misses are `undefined` in `cacheable` and `cache-manager` v7; avoid `null` sentinels.
- `clear()` affects all configured stores; avoid it on shared Redis/Valkey namespaces.
- `nonBlocking: true` favors latency over immediate L2 consistency.
- Use explicit namespaces for shared stores and distributed sync.
- Do not use unreleased `maxTtl`, tag invalidation, or `CacheableMemoryHooks` just because GitHub `main` documents them; confirm the installed npm version first.
