---
name: dev-testing
description: Testing strategy for changed behavior — stable seams, real-engine fidelity, verified API mocks, and relevant edge cases. Use when writing tests, when the user asks "how should I test this", "add tests", or when finishing a feature without tests.
---

# Testing Strategy

Bias toward **integration tests** — they verify what users actually experience and survive refactoring. Unit tests are for pure logic with many branches. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

This skill covers the **everyday suite** that runs on every `test` invocation. For the heavier production-parity tier — real brokers, local blockchains, real sockets, network-fault injection, run on demand rather than per commit — see `dev-e2e-testing`.

## Choose the Smallest Test That Proves the Contract

- Reuse existing coverage if it already detects a regression in the changed behavior. Trivial edits need no new test.
- For new nontrivial behavior or a bug fix, add a durable check at the cheapest stable seam: unit tests for pure logic, integration tests for storage/protocol contracts, E2E for cross-system behavior.
- Test the requested result and relevant failure cases, not a test-count or coverage-percentage quota. For a bug fix, observe the check fail before the fix and pass after it; expected values come from an independent source.
- Respect the requested test scope. Suggest a broader check only when the narrower one misses a concrete risk.

## Databases: Match Fidelity to the Behavior

Use the project's existing local harness when it proves the contract:

- SQLite `:memory:` runs the real engine. `mongodb-memory-server` launches real MongoDB binaries; pin/configure the server and topology needed by the test.
- PostgreSQL requires real PostgreSQL for migrations, SQL/type behavior, transactions, locks, and concurrency. Use managed local binaries or Testcontainers. `pg-mem` is an emulator: useful for fast limited checks, not proof of PostgreSQL semantics. Never alter production SQL to accommodate its gaps.
- Redis/Valkey: prefer a disposable real server; use a mock only when a real engine cannot run and report the fidelity gap.
- Other engines: local binaries or containers matching the relevant production version and features. Containers alone do not guarantee parity.

Run real migrations. Use unique databases/schemas/key prefixes per worker. Destructive reset (`DROP`, `FLUSHALL`, volume deletion) is permitted only for resources created and owned by this test run; never infer ownership from a name like `test` or `localhost`. Do not mock driver calls to claim query correctness.

Sources: [pg-mem limitations](https://github.com/oguimbal/pg-mem#readme), [MongoDB binary harness](https://github.com/typegoose/mongodb-memory-server#readme).

## External APIs: Mock Server + Real-Data Verification

Never stub `fetch`/`reqwest` inline across the codebase. Stand up **one mock server** at the HTTP boundary:

- Node/browser → `msw` (or `nock` for quick cases)
- Rust → `wiremock` / `httpmock`
- Language-agnostic → WireMock (container)

Use the existing client or HTTP boundary. Add a vendor adapter only when it centralizes actual protocol/translation logic or serves a current application boundary; do not add a production interface or forwarding wrapper solely to make a mock convenient. Keep mock handlers limited to the responses each scenario needs.

**The critical step — verify mock fidelity.** A mock that drifts from the real API produces green tests and production failures. Before trusting mock data:

1. **Capture a real response** once through an authorized read-only/sandbox operation, or use an example from the vendor's current docs and use it as the mock body. Redact credentials and personal data before saving. Do not perform live mutations to discover a fixture; if authoritative evidence is unavailable, state the gap rather than inventing the contract.
2. **Diff against the vendor's published schema** (OpenAPI spec if available) — field names, nesting, types, nullability, pagination envelope.
3. **Record where each mock body came from** once alongside the fixture, in metadata or a brief comment: `// captured from GET /v2/users 2026-07-12, api-version 2024-11`. Do not repeat provenance at every use.
4. Mock the **failure shapes** too: the vendor's actual 429/5xx error body and headers (e.g. `Retry-After`), not an invented `{error: "oops"}`.
5. If a sandbox exists, keep **one opt-in live smoke test** (skipped by default, run in CI nightly or on demand) that asserts the real response still matches the mock's shape — this catches drift.

## Test Quality — Three Anti-Patterns

- **Tautological tests:** the expected value must come from an independent source of truth — the spec, a captured real output, a hand computation — never recomputed with the same logic as the code under test. A test that mirrors the implementation passes when both are wrong.
- **Implementation-coupled tests:** test at stable seams (public interfaces, entry points), not private internals — internals-coupled tests break on every refactor without ever catching a bug. If a behavior can only be tested through internals, that's a design finding, not a reason to reach in.
- **Horizontal slicing:** don't write all tests upfront and then all implementation. Work in vertical slices — one test, make it pass, next test — so each failure has one candidate cause.

## Keep Test Code Readable

Apply `dev-code-style` to tests too. Let scenario names, fixture names, and explicit assertions explain the behavior; skip comments narrating setup, calls, or assertions. Keep only non-obvious fixture provenance, timing constraints, or reasons an expected value is correct. Reuse existing setup; add a helper only when shared setup or a meaningful operation becomes clearer. Avoid generic fixture builders, test base classes, and mock factories for a single simple case. A little explicit repetition is fine; retain each scenario's distinguishing input and expectation where the reader can see them. Simplification must not weaken coverage or assertions.

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

- Reuse setup within a suite while isolating state per test/worker. Preserve setup/test exit status through cleanup; cleanup success must not mask a failed test.
- Run focused checks while iterating; after an edit rerun checks whose inputs changed. Run repository-required checks on the final state, then stop unless new evidence warrants more testing.
- Parallel-safe tests: unique DB name/schema per worker, no shared global state.
- If total test time exceeds a few minutes, split a fast default suite from a slower `integration`-tagged suite — but the fast suite must still include the critical integration paths.
