---
name: postgres-js
description: Postgres.js (porsager/postgres) conventions — tagged template queries, transactions, dynamic SQL, cursors, subscriptions, type handling, connection pooling, and TypeScript patterns. Use when writing or modifying code that imports 'postgres' for database access.
---

Apply these conventions when working with postgres.js (`postgres` package from `porsager/postgres`, current stable 3.4.x) in Node.js, Bun, Deno, or Cloudflare Workers projects.

## Connection Setup
- Create the connection with `postgres(url, options)` or `postgres(options)`.
- Falls back to psql-style environment variables when not specified: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSERNAME`/`PGUSER`, `PGPASSWORD`, `PGAPPNAME`, `PGIDLE_TIMEOUT`, `PGCONNECT_TIMEOUT`.
- Key options: `max` (pool size, default 10; lower in Cloudflare Workers), `idle_timeout`, `max_lifetime` (randomized by default to recycle prepared statements), `connect_timeout` (default 30s), `prepare` (default true), `fetch_types` (default true), `sslnegotiation: 'direct'` when the server/provider requires direct SSL negotiation.
- PGBouncer transaction mode: use `prepare: false` unless the deployment is PGBouncer 1.21+ configured with `max_prepared_statements` for protocol-level named prepared statements.
- Multi-host HA: `postgres('postgres://host1:5432,host2:5433', { target_session_attrs: 'primary' })`.
- Dynamic auth: `password` option accepts an async function returning a token.

## Query Syntax
- All queries use tagged template literals: `` sql`select * from users where age > ${age}` ``.
- Parameters are sent separately from the query string — this prevents SQL injection automatically.
- **Never** wrap interpolated values in quotes: `` sql`select * from users where name = '${name}'` `` is **wrong**. The correct form is `` sql`select * from users where name = ${name}` ``.
- Results are arrays of objects with column names as keys.

## Result Properties
- `result.count` — affected rows.
- `result.command` — query command (`SELECT`, `INSERT`, etc.).
- `result.columns` — array of column metadata objects.

## TypeScript
- Use generic type parameters for results: `` sql<User[]>`select * from users` ``.
- Destructure with optionals for single-row queries: `` const [user]: [User?] = await sql`select * from users where id = ${id}` ``.

## Dynamic Queries
- **Column selection:** `` sql`select ${sql(columns)} from users` ``.
- **Dynamic insert:** `` sql`insert into users ${sql(user, 'name', 'age')}` `` — pass the object and allowed column names.
- **Multiple rows:** `` sql`insert into users ${sql(users, 'name', 'age')}` `` — pass an array of objects.
- **Dynamic update:** `` sql`update users set ${sql(user, 'name', 'age')} where id = ${id}` ``.
- **WHERE IN:** `` sql`select * from users where age in ${sql([68, 75, 23])}` ``.
- **Identifiers:** `` sql`select * from ${sql(tableName)}` `` for dynamic table/column names.
- **Conditional fragments:** `` ${condition ? sql`and active = true` : sql``} ``.
- Always explicitly list allowed columns in `sql(object, ...columns)` to prevent mass assignment.

## Unsafe Queries
- Use `sql.unsafe(query, params)` only when dynamic SQL is unavoidable (DDL, dynamic schema names, trigger definitions).
- Unsafe can be nested inside safe queries: `` sql`select ${sql.unsafe(dynamicExpression)}` ``.

## Transactions
- Basic: `` sql.begin(async (sql) => { /* use scoped sql */ }) ``.
- Pipelined (array return): `` sql.begin((sql) => [sql`...`, sql`...`]) ``.
- Auto-rollback on thrown error.
- Isolation levels: `` sql.begin('read committed', async (sql) => { ... }) ``.
- Savepoints: `` await sql.savepoint(async (sql) => { ... }) `` inside a transaction.
- Always use the `sql` parameter passed to the callback, not the outer connection — the scoped `sql` is bound to the transaction's reserved connection.

## Cursors & Streaming
- **Callback cursor:** `` sql`select * from users`.cursor(async ([row]) => { ... }) ``.
- **Batch cursor:** `` sql`select * from users`.cursor(10, async (rows) => { ... }) ``.
- **Async iteration:** `` for await (const [row] of sql`select * from users`.cursor()) { ... } ``.
- **Early termination:** return `sql.CLOSE` from the cursor callback.
- **forEach:** `` sql`select * from users`.forEach((row) => { ... }) ``.

## COPY Operations
- **Copy from (write):** `` const writable = await sql`copy users from stdin`.writable() `` — pipe data with `pipeline()`.
- **Copy to (read):** `` const readable = await sql`copy users to stdout`.readable() `` — consume with `for await...of` or `pipeline()`.

## Listen / Notify
- Listen: `` await sql.listen('channel', (payload) => { ... }) ``.
- With reconnect init: `` await sql.listen('channel', handler, onConnect) ``.
- Notify: `` await sql.notify('channel', JSON.stringify(data)) ``.

## Real-time Subscriptions (Logical Replication)
- Requires `wal_level = logical` and a publication.
- Pass `publications: 'publication_name'` when not using the default `alltables` publication.
- Subscribe: `` await sql.subscribe('*', (row, { command, relation }) => { ... }, onSubscribe, onError) ``.
- Patterns: `'*'`, `'insert:users'`, `'update:public.events'`, `'delete:users=1'`.

## Arrays with `sql.array()`
- Use `sql.array(values, oid)` to pass JavaScript arrays as PostgreSQL typed array parameters.
- The second argument is the PostgreSQL type OID. Common OIDs: `25` = text, `23` = int4, `20` = int8/bigint, `701` = float8.
- Use with `ANY()` for bulk lookups and updates:
  ```js
  await sql`UPDATE nft_meta SET invalid = true WHERE token_id = ANY(${sql.array(ids, 23)})`
  ```
- Prefer `sql.array()` with `ANY()` over `sql([...])` with `IN` for typed array parameters — it avoids parameter count limits on large arrays and ensures correct type casting.
- For simple cases where type inference works, `WHERE id = ANY(${ids})` with a plain array also works — use `sql.array()` when you need explicit type control.

## Type Casting & Custom Types
- **Cast parameters whose type Postgres can't infer.** Parameters arrive as `unknown`; when the context doesn't pin the type, add an explicit cast **in the SQL**: `${id}::uuid`, `${ts}::timestamptz`, `${ids}::text[]` inside `ANY()`. If a query fails with `could not determine data type of parameter` or `operator does not exist: <type> = unknown`, the fix is a cast — not stringifying the value.
- **Enum parameters always get a cast, schema-qualified:**
  ```js
  // CORRECT
  await sql`update orders set status = ${status}::my_schema.order_status where id = ${id}::uuid`

  // WRONG — bare parameter compared to an enum column
  await sql`update orders set status = ${status} where id = ${id}`
  ```
  Same for enum literals: `'active'::my_schema.order_status`, never a bare quoted string where the comparison is ambiguous.
- **Always schema-qualify custom types** — enums, domains, composite types — in every cast, DDL column definition, and function signature: `my_schema.my_enumeration`, **never** bare `my_enumeration`. A bare name resolves only while `search_path` happens to include that schema, and `search_path` differs between the app connection, the migration runner, `psql`, and dump/restore — unqualified names break exactly in the environment where they weren't tested.
- The same qualification rule applies to tables and functions outside `public` when the connection's `search_path` isn't explicitly set.
- Exception: `::jsonb` casts on parameters are unnecessary — use `sql.json()` (see JSONB section below).

## JSONB
- **Inserting JSON (MANDATORY pattern):** Always use `sql.json(value)` to send a JavaScript object to a `jsonb` column. postgres.js handles the wire-format serialization; no manual stringify, no cast required.
  ```js
  // CORRECT
  await sql`insert into events (type, payload) values (${type}, ${sql.json(payload)})`

  // CORRECT — dynamic insert/update with jsonb fields
  await sql`insert into events ${sql({ type, payload: sql.json(payload) }, 'type', 'payload')}`
  ```
- **Anti-pattern — NEVER do this:** `JSON.stringify(obj)` combined with an explicit `::jsonb` cast. It bypasses postgres.js's typed parameter handling, breaks when the object contains values postgres.js would normally serialize (Dates, Buffers, custom types), and produces double-encoded strings in some edge cases.
  ```js
  // WRONG — do not use
  await sql`insert into events (payload) values (${JSON.stringify(payload)}::jsonb)`
  ```
  If a legacy query uses this form, migrate it to `${sql.json(payload)}` (no cast needed).
- **Dynamic JSONB columns in inserts/updates:** When a column is `jsonb`, wrap the value with `sql.json()` so postgres.js sends it as JSON rather than `[object Object]`.
- **Merging JSONB fields:** Use PostgreSQL's `||` operator with `COALESCE` to safely merge into a possibly-null column:
  ```js
  await sql`
    UPDATE nft_meta
    SET chain_state = COALESCE(chain_state, '{}'::jsonb) || jsonb_build_object(
      'ipfs_url', ${ipfsUrl}::text,
      'walrus_url', ${walrusUrl}::text
    )
    WHERE token_id = ANY(${sql.array(ids, 25)})
  `
  ```
- **Reading JSONB:** JSONB columns are automatically parsed to JavaScript objects — no manual `JSON.parse()` needed.
- **JSONB operators in queries:** Use PostgreSQL operators directly in templates: `->` (get key as JSON), `->>` (get key as text), `@>` (contains), `?` (key exists). Escape `?` as `??` in tagged templates since `?` is reserved for parameters.
- **Building JSONB in SQL:** Prefer `jsonb_build_object('key1', ${val1}, 'key2', ${val2})` over constructing JSON in JavaScript — it keeps types consistent and avoids extra serialization.

## Other Type Handling
- **BigInt:** Returned as `BigInt` when using `postgres.BigInt` type.
- **Numeric/Decimal:** Returned as strings — convert explicitly if needed.
- **Custom types:** Define in connection options: `types: { rect: { to: 1337, from: [1337], serialize: fn, parse: fn } }`. Use as `` sql.typed.rect(value) ``.
- **Undefined values:** Rejected by default (throws `UNDEFINED_VALUE`). To convert to `null`: `transform: { undefined: null }`.

## Case Transformations
- Built-in transforms: `postgres.toCamel`, `postgres.toPascal`, `postgres.toKebab` (results only).
- Input transforms: `postgres.fromCamel`, `postgres.fromPascal`, `postgres.fromKebab`.
- Both directions: `postgres.camel`, `postgres.pascal`, `postgres.kebab`.
- Custom: `transform: { column: { to: fn, from: fn } }`.

## Query Methods
- `.values()` — return rows as arrays instead of objects.
- `.raw()` — return raw buffers (performance optimization).
- `.describe()` — get query metadata without executing.
- `.simple()` — execute multiple statements without parameters.
- `.execute()` — run in the current tick instead of deferring.
- `.file('query.sql', [params])` — execute SQL from a file.

## Connection Lifecycle
- Connections are created lazily on first query.
- `await sql.end()` — reject new queries, wait for in-flight queries to complete.
- `await sql.end({ timeout: 5 })` — force close after 5 seconds.
- `const reserved = await sql.reserve()` — reserve a dedicated connection. Call `reserved.release()` when done.
- Cloudflare Workers/Pages: postgres.js exposes a `workerd` export and supports Workers TCP sockets; prefer Cloudflare Hyperdrive for connection pooling/query caching.

## SSL/TLS
- Basic: `ssl: true`.
- Development: `ssl: { rejectUnauthorized: false }`.
- Production: `ssl: { ca, cert, key }` with proper certificates.

## Error Handling
- Errors throw on the specific query that caused them — never globally.
- Error properties `error.query` and `error.parameters` are non-enumerable to prevent leaking in logs.
- Known error codes: `UNSAFE_TRANSACTION`, `UNDEFINED_VALUE`, `MAX_PARAMETERS_EXCEEDED`, `CONNECTION_CLOSED`, `CONNECTION_ENDED`, `CONNECTION_DESTROYED`, `CONNECT_TIMEOUT`.

## Query Cancellation
- Execute and capture: `const query = sql`...`.execute()`.
- Cancel: `await query.cancel()`.
