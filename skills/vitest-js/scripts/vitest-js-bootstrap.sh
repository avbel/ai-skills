#!/bin/bash
set -e

scenario="${1:-config}"

case "$scenario" in
  config)
    install='pnpm add -D vitest @vitest/coverage-v8'
    snippet='import { defineConfig } from '"'"'vitest/config'"'"';

export default defineConfig({
  test: {
    environment: '"'"'node'"'"',
    include: ['"'"'src/**/*.{test,spec}.{ts,tsx}'"'"'],
    globals: false,
    setupFiles: ['"'"'./test/setup.ts'"'"'],
    clearMocks: true,
    restoreMocks: true,
    coverage: {
      provider: '"'"'v8'"'"',
      include: ['"'"'src/**/*.{ts,tsx}'"'"'],
      exclude: ['"'"'**/*.d.ts'"'"', '"'"'**/*.test.{ts,tsx}'"'"'],
      reporter: ['"'"'text'"'"', '"'"'html'"'"', '"'"'lcov'"'"'],
      thresholds: { lines: 80, functions: 80, branches: 75, statements: 80 },
    },
  },
});'
    ;;
  test)
    install='pnpm add -D vitest'
    snippet='import { describe, test, expect } from '"'"'vitest'"'"';
import { sum } from '"'"'./sum'"'"';

describe('"'"'sum'"'"', () => {
  test('"'"'adds two numbers'"'"', () => {
    expect(sum(1, 2)).toBe(3);
  });

  test.each([
    [1, 2, 3],
    [0, 0, 0],
    [-1, 1, 0],
  ])('"'"'sum(%i, %i) === %i'"'"', (a, b, expected) => {
    expect(sum(a, b)).toBe(expected);
  });

  test.concurrent('"'"'async value'"'"', async ({ expect }) => {
    await expect(Promise.resolve(3)).resolves.toBe(3);
  });
});'
    ;;
  mock)
    install='pnpm add -D vitest'
    snippet='import { vi, describe, test, expect } from '"'"'vitest'"'"';
import { fetchUser } from '"'"'./api'"'"';
import { getUserName } from '"'"'./user'"'"';

vi.mock('"'"'./api'"'"', async (importOriginal) => {
  const actual = await importOriginal<typeof import('"'"'./api'"'"')>();
  return { ...actual, fetchUser: vi.fn() };
});

describe('"'"'getUserName'"'"', () => {
  test('"'"'returns name from api'"'"', async () => {
    vi.mocked(fetchUser).mockResolvedValue({ id: 1, name: '"'"'ada'"'"' });
    await expect(getUserName(1)).resolves.toBe('"'"'ada'"'"');
    expect(fetchUser).toHaveBeenCalledWith(1);
  });
});'
    ;;
  timers)
    install='pnpm add -D vitest'
    snippet='import { vi, beforeEach, afterEach, test, expect } from '"'"'vitest'"'"';
import { debounce } from '"'"'./debounce'"'"';

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

test('"'"'debounced call fires once after the window'"'"', () => {
  const fn = vi.fn();
  const debounced = debounce(fn, 200);

  debounced('"'"'a'"'"');
  debounced('"'"'b'"'"');
  vi.advanceTimersByTime(199);
  expect(fn).not.toHaveBeenCalled();
  vi.advanceTimersByTime(1);
  expect(fn).toHaveBeenCalledExactlyOnceWith('"'"'b'"'"');
});'
    ;;
  projects)
    install='pnpm add -D vitest jsdom'
    snippet='import { defineConfig } from '"'"'vitest/config'"'"';

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: '"'"'unit'"'"',
          environment: '"'"'node'"'"',
          include: ['"'"'src/**/*.test.ts'"'"'],
        },
      },
      {
        test: {
          name: '"'"'dom'"'"',
          environment: '"'"'jsdom'"'"',
          include: ['"'"'src/**/*.dom.test.tsx'"'"'],
          setupFiles: ['"'"'./test/dom-setup.ts'"'"'],
        },
      },
    ],
  },
});'
    ;;
  browser)
    install='pnpm add -D vitest @vitest/browser playwright'
    snippet='import { defineConfig } from '"'"'vitest/config'"'"';

export default defineConfig({
  test: {
    browser: {
      enabled: true,
      provider: { name: '"'"'playwright'"'"' },
      instances: [{ browser: '"'"'chromium'"'"' }],
      headless: true,
    },
  },
});'
    ;;
  *)
    echo "Usage: $0 [config|test|mock|timers|projects|browser]" >&2
    exit 2
    ;;
esac

SCENARIO="$scenario" INSTALL="$install" SNIPPET="$snippet" python3 <<'PY'
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "install": os.environ["INSTALL"],
    "snippet": os.environ["SNIPPET"],
}, indent=2))
PY
