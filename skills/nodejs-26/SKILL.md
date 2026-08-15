---
name: nodejs-26
description: Node.js 26 (May 2026) runtime conventions — Temporal API enabled by default, V8 14.6 language features (Map.getOrInsert, Iterator.concat), Undici 8 fetch, experimental node:ffi, raw Ed25519 keys, and removals (legacy _stream_ modules, writeHeader, --experimental-transform-types). Use when targeting or upgrading to Node.js 26+.
---

# Node.js 26

Apply these conventions when targeting Node.js 26.x (Current line, LTS in October 2026). V8 14.6 / Chromium 146 baseline, `NODE_MODULE_VERSION = 147`.

For TypeScript projects, use [TypeScript 7](../typescript-7/SKILL.md). It is the default compiler for new Node.js 26 projects and documents compatibility constraints for API-dependent tooling.

## Runtime Baseline
- V8 14.6.202.33 (from Chromium 146). All V8 14.x ECMAScript additions are available without flags.
- Undici 8.0.2 powers `fetch`, `Request`, `Response`, `Headers`, `WebSocket`.
- ICU 78.3, libuv 1.52.1, bundled SQLite 3.53.x (with Percentile extension), npm 11.x.

## Temporal API (enabled by default — no flag)
- Available as the global `Temporal`. Prefer it over `Date` for any new code that handles time zones, calendars, scheduling, durations, or financial date math.
- Core types: `Temporal.Instant`, `Temporal.ZonedDateTime`, `Temporal.PlainDate`, `Temporal.PlainTime`, `Temporal.PlainDateTime`, `Temporal.PlainYearMonth`, `Temporal.PlainMonthDay`, `Temporal.Duration`.
- Objects are **immutable** — `.add()`, `.subtract()`, `.with()` return new instances.
- Time zones are explicit and first-class — no silent host-tz coercion.
  ```js
  const meeting = Temporal.ZonedDateTime.from('2026-06-15T14:00:00[America/New_York]')
  const tomorrow = Temporal.Now.plainDateISO().add({ days: 1 })
  const lateBy = Temporal.Duration.from({ minutes: 30 })
  ```
- Do not rewrite working `Date` code purely to migrate — use Temporal for new code and migrate strategically.
- For DB I/O: `instant.toString()` produces an ISO 8601 string (RFC 3339 compatible) safe to store in `timestamptz`. Parse back with `Temporal.Instant.from()`.

## V8 14.6 New Language Features

### Map / WeakMap upsert (TC39 Stage 4)
- `map.getOrInsert(key, defaultValue)` — return existing or set+return `defaultValue`.
- `map.getOrInsertComputed(key, factoryFn)` — same, but lazy. `factoryFn(key)` runs only on miss.
- Same methods on `WeakMap`.
  ```js
  // Replaces the verbose has/get/set dance
  const slug = cache.getOrInsertComputed(articleId, buildSlug)

  // Grouping / counting
  for (const item of items) groups.getOrInsert(item.kind, []).push(item)
  ```
- Prefer `getOrInsertComputed` when the default is non-trivial — the factory only fires on a miss, unlike `getOrInsert` which always evaluates its argument.

### Iterator helpers — `Iterator.concat()`
- Stage 4 iterator-sequencing proposal. Concatenates any number of iterables into a single iterator without building intermediate arrays.
  ```js
  for (const row of Iterator.concat(activeUsers(), pendingUsers(), archivedUsers())) {
    process(row)
  }
  ```
- Combine with the existing `Iterator.prototype` helpers (`map`, `filter`, `take`, `drop`, `flatMap`, `toArray`, `reduce`, `some`, `every`, `find`) from V8 12.x for fully lazy pipelines.

### RegExp.escape (Stage 4)
- `RegExp.escape(str)` safely escapes a string for use inside a regex literal — replaces hand-rolled `replace(/[.*+?^${}()|[\]\\]/g, '\\$&')` helpers.

### Other V8 14.x carry-overs (assume available)
- `Promise.try(fn)`, `Set` set-theory methods (`union`, `intersection`, `difference`, `symmetricDifference`, `isSubsetOf`, `isSupersetOf`, `isDisjointFrom`), `Error.isError`, `Float16Array`, `Math.f16round`, resizable `ArrayBuffer`/`SharedArrayBuffer`, `Uint8Array.fromBase64`/`toBase64`/`fromHex`/`toHex`.

## Standard Library Changes

### Undici 8 (powers `fetch`)
- Closer alignment with WHATWG Fetch — fewer cross-runtime quirks for streaming, redirect, and abort.
- `fetch()`, `WebSocket`, `EventSource`, and `Request`/`Response` are all globals — do not import from `undici` unless you need Dispatcher/Agent/Pool/MockAgent.
- For per-call connection pools / proxies, use `Agent` / `ProxyAgent` from `undici` and pass via `dispatcher` option (Node-specific; not portable to browsers).

### Experimental `node:ffi` (added in 26.1.0)
- Load native libraries and call symbols directly from JS.
- Behind `--experimental-ffi` flag; under Permission Model also requires `--allow-ffi`.
- **Inherently unsafe** — invalid pointers, wrong signatures, or use-after-free crash or corrupt the process. Treat like `unsafe` Rust: isolate behind a typed wrapper, fuzz the boundary.

### Crypto
- `KeyObject` import/export now supports `'raw'` format for Ed25519 (and other asymmetric primitives where applicable).
- Signature operations accept a `context` option for Ed25519ctx-style domain separation.
- `module.register()` is **runtime-deprecated** (DEP0218) — migrate ESM loader hooks; will be removed.
- `DEP0203` and `DEP0204` (legacy crypto APIs) are now runtime-deprecated.

### Streams / HTTP / misc
- `localStorage` returns `undefined` when no backing file is configured (previously kept in-memory state silently). Tests relying on the old behavior break.
- The bundled SQLite (`node:sqlite`) enables the Percentile extension.

## Removed in 26 (no longer available)
- Legacy stream private modules: `_stream_readable`, `_stream_writable`, `_stream_duplex`, `_stream_transform`, `_stream_passthrough`, `_stream_wrap`. Use `node:stream` exports instead.
- `http.ServerResponse.prototype.writeHeader()` — use `writeHead()` (note: this removes the typo'd alias only).
- `--experimental-transform-types` flag — use a build step or `--experimental-strip-types` (which only strips, no transform) for TS execution.
- Several older DEP-numbered APIs that had been emitting warnings for multiple majors.

## Upgrade Checklist
- [ ] Rebuild any native add-ons — `NODE_MODULE_VERSION` bumped to 147.
- [ ] Search the codebase for imports of `_stream_*` — replace with `node:stream`.
- [ ] Replace `response.writeHeader(` calls with `response.writeHead(`.
- [ ] Remove `--experimental-transform-types` from start scripts / Dockerfiles.
- [ ] Audit `module.register()` callers — migrate to the stable loader-hooks pathway before it is removed.
- [ ] Replace hand-rolled has/get/set patterns on `Map` with `getOrInsert` / `getOrInsertComputed`.
- [ ] For new date/time code, prefer `Temporal` over `Date`.
- [ ] Replace polyfilled `regexpEscape` helpers with `RegExp.escape`.
- [ ] If using ESM loaders or worker threads with `module.register`, plan migration before 27.

## Release Cadence Note
- Node.js 26 is the Current release; LTS begins October 2026.
- Node.js 26 is the **last release under the existing odd/even release strategy** — from Node.js 27 onward the project adopts a new cadence. Avoid hard-coding assumptions about the old "odd = transient, even = LTS" rule in tooling.
