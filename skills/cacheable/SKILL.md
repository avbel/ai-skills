---
name: cacheable
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

## Setup

```typescript
import { Cacheable } from 'cacheable'

// Memory-only
const cache = new Cacheable()

// L1 memory + L2 Redis
import KeyvRedis from '@keyv/redis'
const cache = new Cacheable({
  secondary: new KeyvRedis('redis://localhost:6379'),
  ttl: '1h',          // default TTL (ms number or shorthand)
  nonBlocking: false,  // true = L2 ops in background
  stats: false,        // true = enable hit/miss/set/delete stats
  namespace: 'myapp',  // key namespace
})
```

## TTL Shorthand

`1ms`, `1s`, `1m`, `1h` / `1hr`, `1d` — works everywhere TTL is accepted. `0` or `undefined` = no expiry.

## CRUD

```typescript
// Set
await cache.set('key', 'value')
await cache.set('key', 'value', 5000)       // 5s TTL
await cache.set('key', 'value', '15m')      // shorthand
await cache.setMany([{ key: 'a', value: 1 }, { key: 'b', value: 2, ttl: '5m' }])

// Get
const val = await cache.get<string>('key')  // T | undefined
const vals = await cache.getMany<number>(['a', 'b'])

// Get raw (includes metadata)
const raw = await cache.getRaw('key')       // { value, expires }

// Has
const exists = await cache.has('key')       // boolean
const many = await cache.hasMany(['a', 'b']) // boolean[]

// Take (get + delete)
const taken = await cache.take('key')

// Delete
await cache.delete('key')
await cache.deleteMany(['a', 'b'])

// Clear (both L1 and L2)
await cache.clear()

// Disconnect
await cache.disconnect()
```

## L1/L2 Behavior

| Operation | Behavior |
|---|---|
| **set** | Writes to primary, then secondary |
| **get** | Reads primary; on miss reads secondary and promotes to primary (with remaining TTL) |
| **delete/clear** | Both stores simultaneously |

**Non-blocking mode** (`nonBlocking: true`): L2 writes/reads happen in background; primary returns immediately.

## Wrap / Memoize

```typescript
// Async wrap with stampede protection
const cachedGetUser = cache.wrap(
  async (id: number) => db.findUser(id),
  { ttl: '1h', keyPrefix: 'users' }
)
const user = await cachedGetUser(42)  // fetches from DB
const cached = await cachedGetUser(42) // returns from cache

// Options
cache.wrap(fn, {
  ttl: '1h',
  keyPrefix: 'prefix',
  key: 'explicit-key',
  cacheError: false,                    // don't cache errors (default)
  createKey: (fn, args, opts) => `custom:${args[0]}`,
})
```

## getOrSet (Cache-Aside)

```typescript
const user = await cache.getOrSet(
  `user:${userId}`,
  async () => db.findUser(userId),     // only called on cache miss
  { ttl: '30m' }
)
```

## Hooks

```typescript
import { CacheableHooks } from 'cacheable'

cache.onHook(CacheableHooks.BEFORE_SET, (data) => {
  console.log(`setting ${data.key}`)
})
cache.removeHook(CacheableHooks.BEFORE_SET)
```

Hooks: `BEFORE_SET`, `AFTER_SET`, `BEFORE_SET_MANY`, `AFTER_SET_MANY`, `BEFORE_GET`, `AFTER_GET`, `BEFORE_GET_MANY`, `AFTER_GET_MANY`, `BEFORE_SECONDARY_SETS_PRIMARY`.

## Events

```typescript
import { CacheableEvents } from 'cacheable'

cache.on(CacheableEvents.ERROR, (error) => console.error(error))
cache.on(CacheableEvents.CACHE_HIT, (data) => { /* data.key, data.value, data.store */ })
cache.on(CacheableEvents.CACHE_MISS, (data) => { /* data.key, data.store */ })
```

## Statistics

```typescript
const cache = new Cacheable({ stats: true })

cache.stats.hits
cache.stats.misses
cache.stats.sets
cache.stats.deletes
cache.stats.errors
cache.stats.count     // key count
cache.stats.vsize     // estimated value bytes
cache.stats.ksize     // estimated key bytes
cache.stats.reset()
```

## CacheableMemory (In-Memory Engine)

Synchronous API. Re-exported from `cacheable`.

```typescript
import { CacheableMemory } from 'cacheable'

const mem = new CacheableMemory({
  ttl: '1h',
  lruSize: 5000,         // 0 = unlimited
  useClones: true,       // false for reference sharing
  checkInterval: 60000,  // expiry check interval (0 = lazy only)
})

mem.set('k', 'v')
mem.get('k')             // 'v'
mem.has('k')             // true
mem.delete('k')
mem.clear()
mem.size                 // key count

// As Keyv store
import { Keyv } from 'keyv'
import { KeyvCacheableMemory } from 'cacheable'
const keyv = new Keyv({ store: new KeyvCacheableMemory({ ttl: 60000, lruSize: 5000 }) })

// Sync wrap/memoize
const cachedFn = mem.wrap((n: number) => n * 2, { ttl: '1h', key: 'double' })
```

## cache-manager (NestJS-Compatible)

```typescript
import { createCache } from 'cache-manager'
import { createKeyv } from 'cacheable'
import KeyvRedis from '@keyv/redis'

const cache = createCache({
  stores: [
    createKeyv({ ttl: 60000, lruSize: 5000 }),        // L1: memory
    new Keyv({ store: new KeyvRedis('redis://...') }), // L2: Redis
  ],
  ttl: 10000,
  refreshThreshold: 3000,  // background refresh when TTL < this
})

await cache.set('key', 'value')
await cache.set('key', 'value', 5000)
const val = await cache.get('key')
await cache.del('key')
await cache.clear()
await cache.mset([{ key: 'a', value: 1 }])
await cache.mget(['a', 'b'])
await cache.mdel(['a', 'b'])

// Wrap with memoization + background refresh
const val = await cache.wrap('key', () => fetchData(), 5000, 3000)

await cache.disconnect()
```

**Events:** `cache.on('set' | 'del' | 'clear' | 'refresh', handler)`.

**refreshThreshold:** When a wrapped value's remaining TTL drops below this, returns stale value immediately and refreshes in background.

## Distributed Sync

```typescript
import { Cacheable } from 'cacheable'
import { RedisMessageProvider } from '@qified/redis'

const provider = new RedisMessageProvider({
  connection: { host: 'localhost', port: 6379 },
})

const cache = new Cacheable({ sync: { qified: provider } })
// Primary caches across instances sync via Pub/Sub
```

## Storage Adapters (via Keyv)

| Store | Package |
|---|---|
| Memory | `@cacheable/memory` (re-exported from `cacheable`) |
| Redis | `@keyv/redis` |
| Valkey | `@keyv/valkey` |
| Memcache | `@keyv/memcache` |
| MongoDB | `@keyv/mongo` |
| SQLite | `@keyv/sqlite` |
| PostgreSQL | `@keyv/postgres` |
| MySQL | `@keyv/mysql` |
| Etcd | `@keyv/etcd` |

## TTL Precedence

```
function-level TTL → storage adapter TTL → cacheable default TTL
```

When promoting from L2 to L1, remaining TTL from L2 is used (capped by L1's configured TTL).
