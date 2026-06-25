---
name: vitest-js
description: Use when writing or reviewing Vitest tests in JavaScript/TypeScript — vitest.config.ts setup, describe/test/expect, vi mocking (vi.fn, vi.mock, vi.spyOn, vi.hoisted, vi.mocked, fake timers), snapshots, concurrent/sequential tests, in-source testing, projects (multi-config), browser mode, coverage with v8/istanbul, and Vitest 4.x migration.
---

# Vitest

Use these conventions for testing JavaScript/TypeScript projects with `vitest-dev/vitest`.

## Source Baseline

- Prefer official docs at `vitest.dev` and the matching GitHub release over older Jest-era snippets.
- Current stable baseline checked for this skill: Vitest `4.1.9` (June 2026). Vitest `5.0.0-beta.5` exists but is not the stable `latest` tag.
- Vitest 4.1.9 supports **Vite `^6.0.0 || ^7.0.0 || ^8.0.0`** and **Node.js `^20.0.0 || ^22.0.0 || >=24.0.0`**.
- Vitest is Vite-native: it reuses the project's Vite config, transforms, and resolvers — do not bolt Babel on top unless a transform is missing.
- Vitest's `vi` API is Jest-compatible enough that most `jest.*` calls map 1:1 to `vi.*`, but the runtime, ESM handling, and mocking semantics differ — do not assume Jest behavior.

## Install

```bash
pnpm add -D vitest
```

For coverage and DOM testing add only what is used:

```bash
pnpm add -D @vitest/coverage-v8 jsdom @testing-library/jest-dom
```

For browser mode:

```bash
pnpm add -D vitest @vitest/browser-playwright
```

Note: in Vitest 4 the runtime API is exported from `vitest/browser`. Install a provider package such as `@vitest/browser-playwright`, `@vitest/browser-webdriverio`, or `@vitest/browser-preview`; the old `@vitest/browser/context` and `@vitest/browser/utils` entry points are transitional and should be migrated to `vitest/browser`.

## package.json Scripts

```json
{
  "scripts": {
    "test": "vitest",
    "test:run": "vitest run",
    "test:coverage": "vitest run --coverage",
    "test:ui": "vitest --ui"
  }
}
```

- `vitest` runs in watch mode by default; use `vitest run` in CI.
- `vitest --changed` runs only tests affected by uncommitted changes; useful as a pre-push hook.

## Config

Prefer a single `vitest.config.ts` that re-uses the project's Vite config:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    globals: false,
    setupFiles: ['./test/setup.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['**/*.d.ts', '**/*.test.{ts,tsx}'],
      reporter: ['text', 'html', 'lcov'],
      thresholds: { lines: 80, functions: 80, branches: 75, statements: 80 },
    },
  },
});
```

- Keep `globals: false` and import `describe`, `test`, `expect`, `vi` explicitly. Globals couple test files to a hidden runtime and slow down editor type inference.
- If you must enable globals, add `"types": ["vitest/globals"]` to `tsconfig.json`.
- Default `environment` is `'node'`. Use `'jsdom'` or `'happy-dom'` only for DOM-touching files — set per-file with `// @vitest-environment jsdom` rather than globally.

## Writing Tests

```ts
import { describe, test, expect } from 'vitest';
import { sum } from './sum';

describe('sum', () => {
  test('adds two numbers', () => {
    expect(sum(1, 2)).toBe(3);
  });

  test.each([
    [1, 2, 3],
    [0, 0, 0],
    [-1, 1, 0],
  ])('sum(%i, %i) === %i', (a, b, expected) => {
    expect(sum(a, b)).toBe(expected);
  });
});
```

- Use `test` (or `it`) — both are aliases.
- Use `test.each` for table-driven cases instead of looping with `for` inside `describe`.
- Use `test.skip`/`test.only`/`test.todo` for triage; do not commit `.only`.
- Use `expect.soft(...)` to collect multiple assertion failures in one test instead of stopping at the first.
- Test file names must include `.test.` or `.spec.` to be picked up by the default `include` pattern.

## Concurrency

- `test.concurrent` runs sibling tests in the same file in parallel. Group with `describe.concurrent` to apply to all children.
- Concurrent tests must use the local `expect` from the test callback context to keep snapshots and assertions correctly attributed:

```ts
test.concurrent('isolated', async ({ expect }) => {
  expect(await fetchValue()).toBe(42);
});
```

- Top-level `test(name, { concurrent: false }, fn)` overrides a global `sequence.concurrent: true` for that test.
- The `sequential` test API and `sequence.sequential` option are deprecated in Vitest 4 — invert with `concurrent: false` instead.

## Hooks

```ts
import { beforeAll, beforeEach, afterEach, afterAll } from 'vitest';

beforeEach(async (ctx) => {
  ctx.db = await openTestDb();
  return async () => ctx.db.close(); // teardown returned from beforeEach
});
```

- Returning a function from `beforeEach`/`beforeAll` registers teardown — prefer this over a paired `afterEach` for symmetry.
- Hooks are scoped to the enclosing `describe`. Avoid global `beforeEach` that resets state every test file silently.

## Mocking with `vi`

### vi.fn / vi.spyOn

```ts
import { vi, expect, test } from 'vitest';

test('spy on method', () => {
  const obj = { greet: (name: string) => `hi ${name}` };
  const spy = vi.spyOn(obj, 'greet');
  obj.greet('world');
  expect(spy).toHaveBeenCalledWith('world');
  spy.mockRestore();
});

test('mock fn returning value', () => {
  const fn = vi.fn().mockReturnValue(42);
  expect(fn()).toBe(42);
  expect(fn).toHaveBeenCalledOnce();
});
```

- `vi.fn()` and `vi.spyOn()` support `new` (constructor calls) in Vitest 4.
- Prefer `vi.spyOn` when the original implementation should still run — it returns a spy that wraps the real method.
- Call `spy.mockRestore()` (or rely on `restoreMocks: true` in config) to put the original back. `mockReset()` keeps the spy but drops history and implementation. `mockClear()` drops only history.

### vi.mock (hoisted)

```ts
import { vi, expect, test } from 'vitest';
import { fetchUser } from './api';

vi.mock('./api', () => ({
  fetchUser: vi.fn(async (id: number) => ({ id, name: `mock-${id}` })),
}));

test('uses mocked api', async () => {
  expect(await fetchUser(1)).toEqual({ id: 1, name: 'mock-1' });
});
```

- `vi.mock(path, factory)` is **hoisted** to the top of the file. The factory cannot reference module-scoped variables that have not been initialized via `vi.hoisted`.
- Use `vi.doMock` for non-hoisted mocking that needs runtime-scoped values — but it only affects subsequent dynamic `import()`s, not static imports.
- For partial mocks, call `vi.importActual` inside the factory:

```ts
vi.mock('./api', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./api')>();
  return { ...actual, fetchUser: vi.fn() };
});
```

### vi.hoisted

```ts
const mocks = vi.hoisted(() => ({ now: vi.fn(() => 0) }));

vi.mock('./clock', () => ({ now: mocks.now }));
```

- Use `vi.hoisted` to safely build values referenced by `vi.mock` factories.

### vi.mocked

```ts
import { vi } from 'vitest';
import { fetchUser } from './api';

vi.mock('./api');

const mockedFetch = vi.mocked(fetchUser);
mockedFetch.mockResolvedValue({ id: 1, name: 'x' });
```

- `vi.mocked(value, { partial: true, deep: true })` is a typing helper. It does not change runtime behavior.

### Fake Timers

```ts
import { vi, beforeEach, afterEach, expect, test } from 'vitest';

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

test('debounced call fires after 200ms', () => {
  const fn = vi.fn();
  setTimeout(fn, 200);
  vi.advanceTimersByTime(199);
  expect(fn).not.toHaveBeenCalled();
  vi.advanceTimersByTime(1);
  expect(fn).toHaveBeenCalledOnce();
});
```

- `vi.setSystemTime(date)` controls `Date` independently — useful when only `Date.now()` matters.
- `vi.useFakeTimers({ toFake: ['setTimeout', 'setInterval'] })` narrows the mocked surface so unrelated timers (e.g. `queueMicrotask`) keep running.

### Reset Helpers

Prefer config over per-test resets:

```ts
// vitest.config.ts
test: {
  clearMocks: true,    // mock.calls/results cleared between tests
  restoreMocks: true,  // spies returned to original, mocks reset
}
```

- `clearMocks: true` ≈ `vi.clearAllMocks()` before each test.
- `restoreMocks: true` ≈ `vi.restoreAllMocks()` before each test. This also implies reset.
- `mockReset: true` ≈ `vi.resetAllMocks()`.

## Snapshots

```ts
expect(value).toMatchSnapshot();
expect(value).toMatchInlineSnapshot();
expect(html).toMatchFileSnapshot('./__snapshots__/page.html');
```

- Prefer `toMatchInlineSnapshot()` for small, readable snapshots — they live next to the assertion and review well in diffs.
- Use `expect(fn).toThrowErrorMatchingInlineSnapshot()` to lock error messages.
- Update with `vitest -u` or per-test with `vitest run path -u`.

## Async Assertions

```ts
await expect(fetchUser(1)).resolves.toEqual({ id: 1 });
await expect(fetchUser(-1)).rejects.toThrow('invalid id');
```

- Always `await` `.resolves`/`.rejects` — otherwise the promise is dangling and the test passes silently.
- For polling, prefer `expect.poll(() => readState(), { timeout: 2000, interval: 50 }).toBe('ready')` over hand-written retry loops.

## Projects (multi-config)

Vitest 4 renamed `workspace` to `projects`. Define multiple test configurations in one `vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: 'unit',
          environment: 'node',
          include: ['src/**/*.test.ts'],
        },
      },
      {
        test: {
          name: 'dom',
          environment: 'jsdom',
          include: ['src/**/*.dom.test.tsx'],
          setupFiles: ['./test/dom-setup.ts'],
        },
      },
    ],
  },
});
```

- A separate `vitest.workspace.{ts,js,json}` file is no longer needed — move its contents into `projects`.
- Filter projects on the CLI: `vitest --project unit`.

## Browser Mode

```ts
import { defineConfig } from 'vitest/config';
import { playwright } from '@vitest/browser-playwright';

export default defineConfig({
  test: {
    browser: {
      enabled: true,
      provider: playwright(),
      instances: [{ browser: 'chromium' }],
      headless: true,
    },
  },
});
```

- In Vitest 4.1 use the provider helper (`playwright()`, `webdriverio()`, or `preview()`) from the matching provider package; do not use the old string form (`provider: 'playwright'`).
- Import test APIs from `vitest/browser` for browser-specific helpers like `userEvent`.
- Use `browser.testerHtmlPath` to customize the tester HTML — `browser.testerScripts` was removed in v4.

## In-Source Testing

Co-locate tiny tests with the implementation by exporting through `import.meta.vitest`:

```ts
export function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

if (import.meta.vitest) {
  const { test, expect } = import.meta.vitest;
  test('slug', () => expect(slug('Hello World!')).toBe('hello-world'));
}
```

Enable in config:

```ts
test: {
  includeSource: ['src/**/*.ts'],
},
// also set this in vite config so production builds drop the test block
define: { 'import.meta.vitest': 'undefined' },
```

- Use sparingly — only for pure utilities. Anything touching modules, fixtures, or DOM belongs in a `.test.ts` file.

## Coverage

```ts
test: {
  coverage: {
    provider: 'v8',           // or 'istanbul'
    include: ['src/**/*.{ts,tsx}'],
    exclude: ['**/*.d.ts', '**/index.ts'],
    reporter: ['text', 'html', 'lcov'],
    thresholds: { lines: 80, functions: 80, branches: 75, statements: 80 },
  },
},
```

- Vitest 4 requires you to set `coverage.include` explicitly — there is no `coverage.all` and no implicit `coverage.extensions`.
- `provider: 'v8'` is fast and uses native V8 coverage. Switch to `'istanbul'` only if you need its instrumentation features (e.g. branch coverage on transpiled code).
- Use `// v8 ignore next` / `// v8 ignore start ... // v8 ignore stop` for targeted ignores. Vitest 4 no longer counts empty lines as ignored automatically.

## Pool & Isolation (v4)

- `pool: 'threads' | 'forks' | 'vmThreads' | 'vmForks'` — pick `forks` when test code uses native modules or globals that do not play well with worker threads.
- Use `maxWorkers` / `minWorkers` directly under `test`. The v3 `maxThreads`/`maxForks` and `poolOptions.*` fields were removed.
- For a single shared context (e.g. integration tests against one DB), set `maxWorkers: 1, isolate: false` instead of the old `singleThread`/`singleFork` flags.

## Testing Tips

- Co-locate tests next to source: `foo.ts` + `foo.test.ts`. Avoid a top-level `__tests__` mirror tree — it drifts.
- Test behavior, not implementation. Assert on observable outputs and side effects, not on internal call counts unless the call itself is the contract (e.g. a logger).
- For HTTP, prefer `msw` over hand-rolled `vi.mock('node:http')` — it survives refactors and reuses the same handlers in dev.
- For DB integration, prefer Testcontainers or a per-test schema over mocking the driver.
- `expect.assertions(n)` and `expect.hasAssertions()` guard async tests that might silently early-return without asserting.

## Helper Script

Generate starter snippets without loading extra context:

```bash
bash /mnt/skills/user/vitest-js/scripts/vitest-js-bootstrap.sh config
bash /mnt/skills/user/vitest-js/scripts/vitest-js-bootstrap.sh test
bash /mnt/skills/user/vitest-js/scripts/vitest-js-bootstrap.sh mock
bash /mnt/skills/user/vitest-js/scripts/vitest-js-bootstrap.sh timers
bash /mnt/skills/user/vitest-js/scripts/vitest-js-bootstrap.sh projects
bash /mnt/skills/user/vitest-js/scripts/vitest-js-bootstrap.sh browser
```

The script prints JSON with `scenario`, `install`, and `snippet` fields.

## Review Checklist

- Is `globals: false` set and `describe`/`test`/`expect`/`vi` imported explicitly?
- Is `environment` chosen per-file (via `@vitest-environment` comment) or per-project, not globally `jsdom` when most tests are node?
- Are `vi.mock` factories side-effect free, or are runtime values pulled in via `vi.hoisted`?
- Are spies created with `vi.spyOn` restored (config `restoreMocks: true` or explicit `mockRestore()`)?
- Are async assertions `await`ed (`await expect(...).resolves/rejects`)?
- Do concurrent tests use the local `expect` from the callback context?
- Is `coverage.include` set, and are thresholds enforced in CI?
- For v4 migration: workspace renamed to `projects`, `maxThreads`/`maxForks` replaced by `maxWorkers`, browser `provider` is an object, no `coverage.all`?

## Sources

- `https://github.com/vitest-dev/vitest`
- `https://vitest.dev/guide/`
- `https://vitest.dev/guide/migration.html`
- `https://vitest.dev/config/`
- `https://vitest.dev/api/vi.html`
- `https://vitest.dev/api/expect.html`
- `https://vitest.dev/guide/mocking.html`
- `https://vitest.dev/guide/projects.html`
- `https://vitest.dev/guide/browser/`
- `https://vitest.dev/guide/coverage.html`
- `https://vitest.dev/guide/in-source.html`
