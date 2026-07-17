---
name: dev-testing
description: Testing strategy for any project — integration tests first, in-memory databases, mock servers for external APIs with real-data verification, edge-case coverage. Use when writing tests, when the user asks "how should I test this", "add tests", or when finishing a feature without tests.
---

# Testing Strategy

Bias toward **integration tests** — they verify what users actually experience and survive refactoring. Unit tests are for pure logic with many branches. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

This skill covers the **everyday suite** that runs on every `test` invocation. For the heavier production-parity tier — real brokers, local blockchains, real sockets, network-fault injection, run on demand rather than per commit — see `dev-e2e-testing`.

## Default Test Plan for a Feature

1. **1–3 integration tests** through the real entry point (HTTP handler, CLI command, job runner) hitting a real-but-local database.
2. **Edge-case tests** — see the checklist below.
3. **Unit tests only** for isolated pure logic (parsers, calculators, matchers) where enumerating cases is cheap.

Always *suggest* integration tests even when the user only asked for unit tests — one sentence, not a lecture. If they decline, respect it.

## Databases: Run Real Engines Locally, Not Fakes

Prefer, in order:

1. **In-memory / embedded mode of the real engine** — zero infra, exact SQL dialect:
   - PostgreSQL → `pg-mem` (Node, no server) or embedded binaries (`embedded-postgres` for Rust/Go/Java)
   - SQLite → `:memory:`
   - MongoDB → `mongodb-memory-server`
   - Redis/Valkey → `ioredis-mock`, or a real `valkey` container
   - ClickHouse / anything without an embedded mode → containers (next option)
2. **Testcontainers** (`testcontainers` for Node/Rust/Go/Java/Python) — real engine in Docker, throwaway per suite. Heavier but 100% faithful; use when the in-memory shim diverges from the real dialect (e.g. `pg-mem` lacks some PG features — on the first unsupported-feature error, switch to testcontainers rather than dumbing down the SQL).
3. **Never** mock the database driver call-by-call — those tests assert your own implementation, not behavior.

Run migrations in test setup so the schema is the production schema.

## External APIs: Mock Server + Real-Data Verification

Never stub `fetch`/`reqwest` inline across the codebase. Stand up **one mock server** at the HTTP boundary:

- Node/browser → `msw` (or `nock` for quick cases)
- Rust → `wiremock` / `httpmock`
- Language-agnostic → WireMock (container)

Structure the code so mocks stay simple: wrap the vendor behind an **SDK-style interface** (one method per operation, each returning one shape) instead of mocking a generic `fetch` — a fetch mock has to reimplement routing and grows a second API client inside the test suite.

**The critical step — verify mock fidelity.** A mock that drifts from the real API produces green tests and production failures. Before trusting mock data:

1. **Capture a real response** once (curl the sandbox/real API, or copy a verbatim example from the vendor's current docs) and use it as the mock body. Do not hand-write response JSON from memory.
2. **Diff against the vendor's published schema** (OpenAPI spec if available) — field names, nesting, types, nullability, pagination envelope.
3. **Record where each mock body came from** in a one-line comment: `// captured from GET /v2/users 2026-07-12, api-version 2024-11`.
4. Mock the **failure shapes** too: the vendor's actual 429/5xx error body and headers (e.g. `Retry-After`), not an invented `{error: "oops"}`.
5. If a sandbox exists, keep **one opt-in live smoke test** (skipped by default, run in CI nightly or on demand) that asserts the real response still matches the mock's shape — this catches drift.

## Test Quality — Three Anti-Patterns

- **Tautological tests:** the expected value must come from an independent source of truth — the spec, a captured real output, a hand computation — never recomputed with the same logic as the code under test. A test that mirrors the implementation passes when both are wrong.
- **Implementation-coupled tests:** test at stable seams (public interfaces, entry points), not private internals — internals-coupled tests break on every refactor without ever catching a bug. If a behavior can only be tested through internals, that's a design finding, not a reason to reach in.
- **Horizontal slicing:** don't write all tests upfront and then all implementation. Work in vertical slices — one test, make it pass, next test — so each failure has one candidate cause.

## Edge-Case Checklist

For each new code path, pick the cases that apply — aim to test the boundaries, not every combination:

- Empty / zero / `null` / missing input; empty collection vs absent collection
- Boundary sizes: 0, 1, exactly-at-limit, limit+1
- Duplicate submission / retry (idempotency)
- Concurrent access to the same resource (two writers, read-during-write)
- Unicode, very long strings, injection-shaped input in anything user-supplied
- Timezone/DST boundaries and clock skew for anything date-based
- The external dependency failing: timeout, 429, 5xx, malformed body, connection reset mid-stream
- Partial failure in multi-step operations — what state is left behind?

When reviewing (see `dev-review`), explicitly check the diff's tests against this list.

## Keep the Suite Fast

- In-memory engines + one shared container per suite (not per test).
- Parallel-safe tests: unique DB name/schema per worker, no shared global state.
- If total test time exceeds a few minutes, split a fast default suite from a slower `integration`-tagged suite — but the fast suite must still include the critical integration paths.
