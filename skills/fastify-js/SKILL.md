---
name: fastify-js
description: Fastify 5 web application conventions — plugin encapsulation, route schemas, validation, hooks lifecycle, error handling, TypeScript type providers, and testing patterns. Use when writing or modifying Fastify routes, plugins, decorators, hooks, or server setup code.
---

Apply these conventions when working with Fastify code in node.js projects.

## Server Setup
- Create the Fastify instance with explicit options: `logger: true` (or Pino config object), `trustProxy` when behind a reverse proxy.
- Separate app construction (`app.ts`) from server startup (`server.ts` / `cluster.ts`) to enable testing via `inject()` without starting the server.

## Plugins & Encapsulation
- Everything is a plugin. Register features with `fastify.register(plugin, options)`.
- Plugins are encapsulated by default — decorators, hooks, and routes registered inside a plugin are invisible to parent scopes.
- Use `fastify-plugin` wrapper only when a plugin must expose decorators or hooks to the parent scope (e.g., database connection, authentication decorator).
- Declare decorator dependencies in the `dependencies` array to fail fast at boot, not at runtime.
- Plugin loading order matters — plugins registered first are available to later plugins in the same scope.

## Routes
- Use shorthand methods: `fastify.get()`, `fastify.post()`, etc.
- Always use `async` handlers that `return` the response body. Do not mix `return` with `reply.send()` — pick one.
- Group related routes in a plugin and apply a `prefix` via `register` options.
- Use route-level `schema` for request validation (`body`, `querystring`, `params`, `headers`) and response serialization (`response`).

## Validation & Serialization
- Define JSON Schema (Draft 7) on every route for `body`, `querystring`, `params`, and `response`.
- Share reusable schemas with `fastify.addSchema({ $id, ... })` and reference via `$ref`.
- Always define `response` schemas — they enable `fast-json-stringify` for serialization performance and prevent accidental leaking of internal fields.
- Default Ajv settings: `removeAdditional: true`, `useDefaults: true`, `coerceTypes: 'array'`. Be aware that coercion can interact unexpectedly with `anyOf`/nullable types.
- Never pass user-provided schemas to the validator — the compiler uses dynamic code evaluation internally.

## TypeScript
- Use a Type Provider (`@fastify/type-provider-typebox` or `@fastify/type-provider-json-schema-to-ts`) to derive request/reply types from route schemas automatically.
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
- Use `disableRequestLogging: true` on high-throughput routes where request logs are not needed.
