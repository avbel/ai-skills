# Embedded-language checks

Code inside strings gets zero help from the host language's compiler — a typo in embedded SQL/HTML/GraphQL passes typecheck and fails at runtime. For every string in the diff containing another language (SQL, HTML, GraphQL, regex, shell, CSS, JSON, XPath):

**Validate the syntax, don't eyeball it.** In order of preference:
1. **Execute against the real engine** — prepare the SQL on the local/test database (`PREPARE q AS <query>` in Postgres parses *and* type-checks without running), parse GraphQL with the project's graphql lib, compile the regex in a REPL, render the template.
2. **Run a linter/parser** if available: `sqlfluff`/`pgsql-parser` (SQL), `graphql validate` against the schema, HTML validator.
3. Only as a last resort, manual parse: matched quotes/parens, correct placeholder count and order (`$1..$n` vs args passed), keywords in valid positions.

**Cross-boundary consistency:** placeholder count matches the argument list; column names/types match the current schema (check migrations in the same diff); GraphQL fields exist in the schema; HTML ids/classes referenced from JS/CSS actually exist.

**Postgres-specific traps (check every SQL string):**
- **Parameter type inference.** PostgreSQL can infer parameter types from context. Add explicit casts when inference is ambiguous or the driver binds an incompatible type; verify using the actual query and binding path. Do not flag every uncast parameter or enum literal. See [PREPARE](https://www.postgresql.org/docs/current/sql-prepare.html).
- **Unqualified custom types.** Enums, domains, and composite types must be schema-qualified everywhere they appear — casts, `CREATE TABLE` columns, function signatures, migrations: `my_schema.my_enumeration`, not `my_enumeration`. A bare name only works while `search_path` happens to include the schema — it differs between the app, migration runner, `psql`, and pg_dump/restore, so this breaks exactly where it wasn't tested. Same rule for functions and tables outside `public` when `search_path` isn't guaranteed.
- `NULL` handling in comparisons (`= NULL` instead of `IS NULL`), and `IN ($1)` with an array argument instead of `= ANY($1)`.

**Tie-in with `dev-testing`:** every embedded SQL/GraphQL string changed in the diff must be executed by at least one integration test against the real engine (a real local server or container for databases) — that's the only durable guard for embedded-language errors. An untested new query is a missing edge-case-test finding.
