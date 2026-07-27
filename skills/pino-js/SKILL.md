---
name: pino-js
description: Pino logger conventions — log levels, child loggers, serializers, redaction, transports, destinations, formatters, and web framework integration. Use when writing or modifying logging code that imports 'pino' in JavaScript/Node.js projects.
---

# Pino Logging

Apply these conventions when working with pino logging code.

## Compatibility
- Current stable checked: Pino `10.3.1`.
- Pino 10 dropped Node.js 18 support. For Node.js 18 applications, stay on the Pino 9 line unless the runtime can be upgraded.
- Official runtimes are Node.js, Bare, and Pear; browser usage has a separate API surface. Bundlers must emit Pino worker/transport support files separately.

## Logger Creation
- Create with `pino(options, destination)`. Both arguments are optional.
- Key options: `level` (default `'info'`), `name`, `base` (default `{pid, hostname}` — set to `undefined` to omit), `timestamp` (default `true`), `messageKey` (default `'msg'`), `errorKey` (default `'err'`).
- Use `enabled: false` to disable logging entirely (e.g., in tests).
- Use `nestedKey` to namespace logged objects and avoid key collisions with the log envelope.
- `depthLimit` (default `5`) and `edgeLimit` (default `100`) only affect Pino's fallback serializer after `JSON.stringify` throws; do not rely on them as general output-size or traversal limits.

## Log Levels
- Built-in levels: `trace` (10), `debug` (20), `info` (30), `warn` (40), `error` (50), `fatal` (60), `silent` (Infinity).
- Method signature: `logger.info([mergingObject], [message], [...interpolationValues])`.
- Pass the object first, message second: `logger.info({ userId: 123 }, 'user logged in')` — not the other way around.
- Check level before expensive work: `if (logger.isLevelEnabled('debug')) { ... }`.
- Custom levels: `customLevels: { audit: 35 }`. Use `useOnlyCustomLevels: true` to disable built-in levels.
- Use `levelComparison: 'ASC' | 'DESC' | (current, expected) => boolean` only when custom level ordering is required; ensure downstream transports understand the custom levels.

## Child Loggers
- Create with `logger.child({ module: 'auth' })` — bindings are included in every log from the child.
- Child loggers inherit parent serializers and level unless overridden.
- Pass options as the second argument: `logger.child({ module: 'auth' }, { level: 'debug', msgPrefix: '[auth] ' })`.
- Do not put serializers in child bindings; `bindings.serializers` is deprecated. Use the second argument: `logger.child(bindings, { serializers })`.
- Creating children is cheap (~259ms for 10,000). Prefer creating a child per module/request over passing context manually.
- Use `logger.setBindings({ key })` only for process-wide/static context changes after creation; prefer `child()` for scoped context.

## Serializers
- Define in `serializers` option: `{ req: (req) => ({ method: req.method, url: req.url }) }`.
- Applied automatically when a logged object has a matching key.
- Standard serializers: `pino.stdSerializers.err` (included by default), `pino.stdSerializers.req`, `pino.stdSerializers.res`.
- Error serialization uses the `err` key by default. Log errors as: `logger.error({ err }, 'operation failed')` — not `logger.error(err)`.

## Redaction
- Array shorthand: `redact: ['password', 'user.ssn', 'cards[*].number']`.
- Object form for custom censor: `redact: { paths: ['password'], censor: '***', remove: false }`.
- Use `remove: true` to omit redacted fields entirely from output.
- Path syntax: dot notation (`a.b.c`), bracket notation for hyphens (`a["x-key"]`), wildcards (`a[*].b`).
- Wildcard redaction has ~50% overhead — prefer explicit paths when possible.
- Never derive redaction paths from user input — paths are compiled using dynamic code evaluation internally, which is a code injection risk.
- Do not pass untrusted objects directly as `logger.info(untrusted)` or `logger.child(untrusted)`: top-level keys can collide with `level`, `time`, `msg`, bindings, or security fields. Wrap under an application-controlled key: `logger.info({ untrusted }, '...')`.

## Transports (Worker Thread)
- Transports run in a separate worker thread to avoid blocking the main thread.
- Single transport: `pino({ transport: { target: 'pino-pretty' } })`.
- If `transport` is supplied in options, do not also pass a second `destination` argument to `pino()`; Pino throws.
- Multiple targets with level filtering:
  ```js
  pino({
    transport: {
      targets: [
        { target: 'pino-pretty', level: 'info' },
        { target: 'pino/file', level: 'error', options: { destination: './error.log', mkdir: true } }
      ]
    }
  })
  ```
- Use `dedupe: true` to route each log only to the highest-level matching target instead of all matching targets.
- Built-in file transport: `target: 'pino/file'` with `options: { destination, mkdir, append }`.
- Transport options are serialized via Structured Clone — only JSON-compatible values.
- Transports start asynchronously. Use `transport.on('ready', ...)` if you need to ensure logs flush before exit.
- Transport worker threads are named for easier identification in diagnostics and profilers.
- Single `target` or single `pipeline`: only `logger.level` filters logs; a `transport.level` is not applied.
- Multiple `targets`: `logger.level` is the first gate, then each `targets[i].level` filters again; missing target levels default to `info`.
- With multiple `targets`, keep the numeric `level` field intact. Do not use `formatters.level` to rename `level` or convert it to a string before routing; transform level labels in a pipeline/custom transport after routing.
- For synchronous transport writes, pass `sync: true` to the transport options; this trades throughput for lower loss risk.
- Pino sanitizes invalid `NODE_OPTIONS` preloads for transport workers, but avoid initializing transports in recursive preload paths unless tested.

## Custom Transports
- Use `pino-abstract-transport` as the base:
  ```js
  import build from 'pino-abstract-transport'

  export default async function (options) {
    return build(async function (source) {
      for await (const obj of source) {
        // obj is the parsed log object
      }
    }, {
      async close() { /* cleanup */ }
    })
  }
  ```
- Always implement `close()` to prevent log loss on shutdown.
- Transport files must be ESM (`.mjs`) or CommonJS — referenced by path or package name.
- TypeScript transports are supported on Node.js 22.6+ type stripping. Prefer `.mts`; Node.js 22.6–22.17 needs `--experimental-strip-types`, while Node.js 22.18+ and 24+ enable type stripping by default.

## Destinations
- `pino.destination(path)` — creates a high-throughput SonicBoom destination for file output.
- `pino.destination({ dest: './app.log', sync: false, minLength: 4096 })` — async buffered writes.
- Default destination is stdout (fd 1).
- Use `sync: true` when data loss is unacceptable (blocks on each write).
- Flush async buffers: `logger.flush()` or `destination.flushSync()`.
- `logger.flush()` does **not** work with `pino-pretty` or other worker thread transports — only for SonicBoom destinations on the main thread.

## Formatters
- Customize log shape without full custom serialization:
  ```js
  formatters: {
    level(label, number) { return { level: label } },        // default emits numeric level
    bindings(bindings) { return { ...bindings } },            // shape of pid/hostname
    log(object) { return object }                             // shape of the log payload
  }
  ```
- Use `formatters.level` to emit `"level": "info"` instead of `"level": 30`.

## Timestamps
- Built-in functions: `pino.stdTimeFunctions.epochTime` (default), `unixTime`, `isoTime`, `isoTimeNano`, `nullTime`.
- ISO timestamps: `timestamp: pino.stdTimeFunctions.isoTime`.
- Disable: `timestamp: false`.

## Mixin
- Inject dynamic properties into every log: `mixin: () => ({ traceId: getTraceId() })`.
- Called on every log operation — keep it fast.
- Return a fresh object from `mixin()`; Pino mutates the returned object during merge for performance.
- Control merge order with `mixinMergeStrategy`.

## Hooks
- `logMethod(args, method, level)` — intercept and transform arguments before logging.
- `streamWrite(jsonString)` — modify the serialized JSON string before writing to the destination.

## Multistream
- Route logs to multiple destinations: `pino(options, pino.multistream(streams))`.
- Per-stream level filtering: `pino.multistream([{ stream: dest1, level: 'info' }, { stream: dest2, level: 'error' }])`.
- Prefer `transport.targets` over `multistream` in new code — transports run off the main thread.

## Diagnostics
- Subscribe to Node diagnostics/tracing channel events `tracing:pino_asJson:start` and `tracing:pino_asJson:end` only for library-level instrumentation; they expose serialization arguments/results and can be high volume.

## Browser API
- Browser Pino writes to `console` by default and has a separate API surface from Node destinations/transports.
- Browser serializers are ignored unless `browser.serialize` is enabled; `serialize: true` or an array also enables the standard error serializer unless `!stdSerializers.err` is included.
- `browser.reportCaller: true` surfaces a best-effort user callsite by parsing `Error` stacks. Treat it as debugging aid only; stack formats vary and DevTools clickable locations still point at Pino internals.

## Web Framework Integration
- **Fastify:** Built-in. Set `logger: true` or pass a pino options object. Access via `request.log` / `reply.log`.
- **Express/Koa/Hapi:** Use `pino-http`, `koa-pino-logger`, or `hapi-pino` middleware. Access via `req.log` / `ctx.log`.
- **Restify / Node `http`:** Use `restify-pino-logger` or `pino-http`.
- **Nest:** Use `nestjs-pino`.
- **H3:** Use `pino-http` through H3 `fromNodeMiddleware`.
- **Hono:** Use `@hono/structured-logger` with a root `pino()` logger and per-request child loggers.
- Framework loggers automatically bind request ID and request metadata to child loggers.

## AWS Lambda
- Async logging is disabled by default in Lambda.
- If enabled, call `destination.flushSync()` at the end of each invocation to prevent log loss.

## Production vs Development
- **Production:** Use default NDJSON output. Pipe to transports externally: `node app.js | pino-pretty`.
- **Development:** Use `transport: { target: 'pino-pretty' }` for human-readable output.
- Never use `pino-pretty` in production — it adds significant overhead.

## Performance
- Do not use string interpolation for log messages — pass objects as the first argument and let pino serialize.
- Avoid `JSON.stringify` before logging — pino handles serialization internally.
- Default config achieves best stdout performance. Async destinations add throughput but risk data loss.
- `pino-debug` provides 10-20x performance improvement over the `debug` module.
