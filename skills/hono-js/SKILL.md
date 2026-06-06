---
name: hono-js
description: Hono web framework conventions for JavaScript and TypeScript - routing, middleware, validation, RPC, Hono CLI docs/search, testing with app.request(), adapters, and multi-runtime deployment.
---

Apply these conventions when writing, modifying, reviewing, or debugging Hono applications.

## Documentation Workflow

- Prefer the project-installed or globally available `hono` command from `@hono/cli` for Hono-specific docs lookup.
- Before substantial Hono work, check the best-practices page:
  ```bash
  hono docs /docs/guides/best-practices
  ```
- When choosing middleware, search the Hono docs first:
  ```bash
  hono search middleware
  hono search "jwt middleware" --limit 10
  hono search "third-party middleware" --pretty
  ```
- Use `hono docs <path>` on the best matching search result path before coding. Search output is JSON by default, which is useful for agents and scripts.
- If `hono` is unavailable, install `@hono/cli` using the repo's package-manager policy or ask before adding a global tool.

## App Shape

- Export an app object from application modules. Keep runtime startup/adapters separate when possible so tests can call `app.request()` without listening on a port.
- Use Web Standard `Request`, `Response`, `Headers`, `URL`, and Fetch APIs. Avoid Node-only request/response assumptions unless the target runtime is explicitly Node.
- Model runtime bindings through Hono's `Env` generic:
  ```ts
  type Env = {
    Bindings: {
      DATABASE_URL: string
    }
    Variables: {
      requestId: string
    }
  }

  const app = new Hono<Env>()
  ```
- Keep platform adapters at the edge of the app: Cloudflare Workers/Pages, Node, Bun, Deno, Vercel, Lambda, and similar runtime glue should not leak into route logic unless needed.

## Routing

- Prefer route-local handlers for type inference:
  ```ts
  app.get('/books/:id', (c) => {
    const id = c.req.param('id')
    return c.json({ id })
  })
  ```
- Do not extract Rails-style controller functions by default; path params and validated inputs lose easy inference.
- For larger apps, split route groups into Hono sub-apps and mount them with `app.route()`:
  ```ts
  const books = new Hono<Env>()
    .get('/', (c) => c.json([]))
    .post('/', (c) => c.json({ ok: true }, 201))

  app.route('/books', books)
  ```
- When extracted handlers are necessary, use `createFactory().createHandlers()` from `hono/factory` to preserve types.
- Return `Response` objects through helpers like `c.json()`, `c.text()`, `c.html()`, `c.redirect()`, or `c.body()`. Do not mix Express-style `res` mutation patterns into Hono code.

## Middleware

- Register middleware with `app.use(path?, middleware)` or per-route before the final handler.
- Middleware should either `await next()` and return nothing, or return a `Response` to short-circuit.
- Use built-in middleware from `hono/<middleware-name>` before adding external dependencies: `logger`, `cors`, `secure-headers`, `etag`, `compress`, `jwt`, `bearer-auth`, `basic-auth`, `request-id`, `timeout`, `body-limit`, `csrf`, and related documented middleware.
- Search docs before introducing middleware:
  ```bash
  hono search "cors middleware"
  hono search "secure headers"
  hono search "third-party middleware auth"
  ```
- Use `createMiddleware()` from `hono/factory` when extracting reusable middleware so `c`, `next`, bindings, and variables stay typed:
  ```ts
  import { createMiddleware } from 'hono/factory'

  const requireUser = createMiddleware<Env>(async (c, next) => {
    const userId = c.req.header('x-user-id')
    if (!userId) {
      return c.json({ error: 'Unauthorized' }, 401)
    }

    c.set('requestId', crypto.randomUUID())
    await next()
  })
  ```
- After `await next()`, mutate response headers with `c.header()` or replace `c.res` only when intentionally post-processing the downstream response.
- In Deno/JSR imports, keep middleware and Hono versions aligned; mixed versions can break runtime behavior.

## Validation

- Validate external input before business logic. Prefer official validator middleware such as `@hono/zod-validator` or `@hono/standard-validator` when the project already uses compatible schemas.
- Access validated data with `c.req.valid(target)`, not by re-reading and re-parsing the body.
- For `json` and `form` validation, ensure requests and tests set the matching `Content-Type`; otherwise Hono will not parse the body as expected.
- Use explicit status codes in `c.json(body, status)` for typed clients and predictable API behavior.

## RPC and Typed Clients

- For Hono RPC, build routes through chained calls and export the inferred route or app type:
  ```ts
  const route = app
    .get('/health', (c) => c.json({ ok: true }, 200))
    .post('/books', validator, (c) => c.json({ ok: true }, 201))

  export type AppType = typeof route
  ```
- Use `hc<AppType>()` from `hono/client` on the client side.
- Use `InferRequestType` and `InferResponseType` for request/response helpers.
- Keep `"strict": true` in TypeScript projects that rely on RPC inference, especially across monorepos.
- Remember that global error handlers and global middleware responses are not automatically inferred by `hc`; use Hono's global response helper types when the client must know those shapes.

## Errors and HTTP Semantics

- Use `app.onError((error, c) => ...)` for centralized error mapping.
- Throw `HTTPException` for intentional HTTP failures where it improves clarity.
- Do not add dedicated `HEAD` handlers for paths that also have `GET`; Hono converts `HEAD` to `GET` before route matching and strips the body. Put HEAD-specific behavior in middleware when needed.
- Put auth, CORS, security headers, request IDs, and logging middleware before routes that need them.

## Testing

- Test apps with `app.request()` and Web Standard request objects:
  ```ts
  const res = await app.request('/books', {
    method: 'POST',
    body: JSON.stringify({ title: 'Hono' }),
    headers: new Headers({ 'Content-Type': 'application/json' }),
  })

  expect(res.status).toBe(201)
  expect(await res.json()).toEqual({ ok: true })
  ```
- Pass mocked runtime bindings as the third argument to `app.request(path, init, env)`.
- Test both `GET` and `HEAD` when routes expose important headers or expensive GET responses.
- Prefer typed Hono test clients or direct `app.request()` over starting a network listener for route-level tests.
