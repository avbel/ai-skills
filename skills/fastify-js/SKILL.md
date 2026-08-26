---
name: fastify-js
description: Fastify 5 web application conventions — plugin encapsulation, route schemas, validation, hooks lifecycle, error handling, TypeScript type providers, and testing patterns. Use when writing or modifying Fastify routes, plugins, decorators, hooks, or server setup code.
---

# Fastify 5

Apply these conventions when working with Fastify code in node.js projects.

## Server Setup
- Fastify 5 targets Node.js 20+. Do not write guidance that assumes Node 18 compatibility for new Fastify 5 apps.
- Current Fastify 5 stable is 5.12.1; keep production apps on at least 5.12.1 for the August 2026 security fixes.
- Create the Fastify instance with explicit options: `logger: true` (or Pino config object), `loggerInstance` for an existing Pino-compatible logger, `trustProxy` when behind a reverse proxy.
- Set `requestTimeout` when exposed without a reverse proxy; use `handlerTimeout` for application-level route lifecycle timeouts and pass `request.signal` into cancellable work.
- For custom request-log behavior or request-id log labels, prefer `logController: new LogController(...)`; top-level `disableRequestLogging` and `requestIdLogLabel` are deprecated for removal in Fastify 6.
- Do not rely on semicolon query delimiters; Fastify 5 defaults `routerOptions.useSemicolonDelimiter` to `false`. Enable it only for legacy clients that send `/path;foo=bar`.
- Treat forwarded `request.ip` / `request.host` / `request.protocol` as untrusted unless `trustProxy` is restricted to the real proxy chain; avoid hop-count-only custom trust functions.
- Separate app construction (`app.ts`) from server startup (`server.ts` / `cluster.ts`) to enable testing via `inject()` without starting the server.

## Plugins & Encapsulation
- Everything is a plugin. Register features with `fastify.register(plugin, options)`.
- Plugins are encapsulated by default — decorators, hooks, and routes registered inside a plugin are invisible to parent scopes.
- Use `fastify-plugin` wrapper only when a plugin must expose decorators or hooks to the parent scope (e.g., database connection, authentication decorator).
- Declare decorator dependencies in the `dependencies` array to fail fast at boot, not at runtime.
- Plugin loading order matters — plugins registered first are available to later plugins in the same scope.

## Routes
- Use shorthand methods: `fastify.get()`, `fastify.post()`, etc.
- Fastify 5.11+ supports `QUERY` by default. Use `addHttpMethod()` only for custom/non-default methods or intentional body-behavior overrides; pass `overrideExisting: true` when overriding an existing method.
- Always use `async` handlers that `return` the response body. Do not mix `return` with `reply.send()` — pick one.
- If an async handler or hook must call `reply.send()` later/outside the promise chain, `return reply` or `await reply` to avoid duplicate execution/race conditions.
- Group related routes in a plugin and apply a `prefix` via `register` options.
- Do not wrap route plugins directly with `fastify-plugin` when relying on `register(..., { prefix })`; `fastify-plugin` makes Fastify-specific register options like `prefix` no-op.
- Use route-level `schema` for request validation (`body`, `querystring`, `params`, `headers`) and response serialization (`response`).
- Prefer route-level `handlerTimeout` for slow endpoints instead of only socket timeouts; timeout errors use code `FST_ERR_HANDLER_TIMEOUT` and async work must observe `request.signal` to stop cooperatively.
- Treat `request.params` as a null-prototype object in Fastify 5; use `Object.hasOwn(request.params, 'id')`, not `request.params.hasOwnProperty(...)`.
- Treat route params and wildcards as percent-decoded untrusted input. Do not join them into filesystem paths, template names, or redirects without validation and containment; use `@fastify/static` for rooted file serving.

## Validation & Serialization
- Define full JSON Schema (Draft 7) on every route for `body`, `querystring`, `params`, and `response`, including root `type` and `properties`; v5 removed JSON schema shorthand.
- Share reusable schemas with `fastify.addSchema({ $id, ... })` and reference via `$ref`.
- Always define `response` schemas — they enable `fast-json-stringify` for serialization performance and prevent accidental leaking of internal fields.
- Default Ajv settings: `removeAdditional: true`, `useDefaults: true`, `coerceTypes: 'array'`. Be aware that coercion can interact unexpectedly with `anyOf`/nullable types.
- Never pass user-provided schemas to the validator — the compiler uses dynamic code evaluation internally.
- Validation only runs automatically for `application/json` bodies unless `schema.body.content` maps content types explicitly. When adding custom content-type parsers, enumerate every accepted content type in `content` or use a catch-all body schema.
- Custom validators must return `{ value }` or `{ error }`; do not throw from validator functions, especially when async `preValidation` hooks are present.

## TypeScript
- Use a Type Provider (`@fastify/type-provider-typebox` or `@fastify/type-provider-json-schema-to-ts`) to derive request/reply types from route schemas automatically.
- Mark inline schemas `as const`; custom Fastify 5 type providers must expose separate `validator` and `serializer` schema types, not the old single `output` type.
- Type decorators via module augmentation (`declare module 'fastify' { interface FastifyInstance { ... } }`).
- Use `FastifyPluginAsync` for async plugin types. Pass plugin options as a generic parameter.

## Decorators
- Use `decorate` for the Fastify instance, `decorateRequest` for request, `decorateReply` for reply.
- Never use reference types (objects, arrays) as default values in `decorateRequest`/`decorateReply` — they are shared across all requests. Use `null` as default and set the actual value in an `onRequest` hook.
- Check existence with `hasDecorator()` / `hasRequestDecorator()` / `hasReplyDecorator()` before adding.

## Hooks
- Request lifecycle order: `onRequest` → `preParsing` → `preValidation` → `preHandler` → handler → `preSerialization` → `onSend` → `onResponse`.
- `onError` runs when an error occurs (before the error handler). `onTimeout` fires on request timeout. `onRequestAbort` fires on client disconnect.
- Application hooks: `onReady`, `onListen`, `onRoute`, `onRegister`, `preClose`, `onClose`.
- Hooks are encapsulated — register them in the appropriate plugin scope.
- In async hooks, do not use the `done` callback — just `return` or `throw`.
- Call `reply.send()` in a hook to short-circuit the lifecycle and skip subsequent hooks/handler.

## Error Handling
- Set a custom error handler with `fastify.setErrorHandler(async (error, request, reply) => { ... })`.
- Error handlers are encapsulated — each plugin can define its own. Errors bubble to the nearest ancestor handler.
- Avoid calling `setErrorHandler` multiple times in the same scope; Fastify 5 warns that `allowErrorHandlerOverride` defaults to `true` now but will default to `false` in the next major release.
- The default error handler sends `error.message` and `error.code` to clients, including 500s. Register a root error handler that logs unexpected errors and returns sanitized 5xx payloads.
- Always throw `Error` instances, never primitives. Fastify's built-in errors use `FST_` prefixed codes (e.g., `FST_ERR_VALIDATION`).
- Validation errors have `error.validation` (raw errors) and `error.validationContext` (`body`, `params`, `query`, `headers`).
- If a custom error handler throws, the parent error handler catches it (triggered only once to prevent loops).

## Testing
- Use `fastify.inject({ method, url, payload, headers })` for testing without network overhead — no need to call `listen()`.
- Always call `fastify.close()` after tests to clean up connections.
- Structure: import the app factory, create an instance, `inject`, assert, `close`.

## Performance
- Define `response` schemas on all routes for serialization speed.
- Set appropriate `bodyLimit` per route for large/small payloads instead of raising the global limit.
- Use `LogController` with `disableRequestLogging` / `isLogDisabled` for high-throughput or noisy routes where request logs are not needed.
- Use route/plugin `logLevel` for noisy or high-value endpoints; it applies to route logging, not the global `fastify.log` instance.
- Avoid multi-parameter and RegExp-heavy hot-path routes; static routes are fastest, then single-param routes.
