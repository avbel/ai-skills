---
name: js-conventions
description: JavaScript and TypeScript project conventions for Node.js 24+, pnpm, ESM, ES2024+, async patterns, type safety, error handling, lint configuration (including XO when present), and post-edit validation. Use when writing or modifying .js, .jsx, .mjs, .ts, .tsx, or .mts files.
---

# JavaScript and TypeScript Conventions

Apply these conventions in JavaScript and TypeScript projects. These rules are written for any coding agent, including Claude Code, Codex, Cursor, and Copilot.

## Package Manager

- Use `pnpm`, not `npm` or `yarn`.

## Code Style

- Read and follow code style rules defined in XO config, ESLint config, or the ESLint/XO section in `package.json`.
- Use single quotes for strings.
- Use `const` for variables that are never reassigned. Use `let` only when reassignment is required.
- Use camelCase for constants and variables. Do not use UPPER_SNAKE_CASE for constants.
- Use PascalCase for enum type names.
- Always wrap `if`, `while`, and `for` bodies in braces, even for single-line bodies.
- Prefer `switch`/`case` constructions over multiple `if`/`else if` statements when matching a single expression against multiple potential values.
- Use `as const` for constant arrays and derive union types with `typeof values[number]`.
- Use full descriptive names for variables, functions, and types. Avoid abbreviations and short names.

## Module System

- Write ESM code using ES2024+ features.
- Use the `node:` prefix for Node.js built-in module imports, for example `import fs from 'node:fs'`.
- Use static imports. Do not use dynamic `await import()`.
- Only suggest libraries compatible with Node.js 24+.

## Async Patterns

- Use `async` and `await`. Do not use `.then()` chains or callback-based patterns in new code.
- Use async `readFile` from `node:fs/promises`; do not use `readFileSync` in normal application code.
- Do not prefix promise calls with `void`.
- In async functions, use promise-based timers from `node:timers/promises` instead of global `setTimeout` or `setInterval`:
  ```ts
  import { setTimeout as sleep, setInterval } from 'node:timers/promises';
  
  // Use await sleep() for delays
  await sleep(1000);
  
  // Use for await with setInterval() for periodic tasks
  for await (const _ of setInterval(1000)) {
    // Runs every 1000ms
  }
  ```

## Type Safety

- Do not use `any` in TypeScript. Use proper type mapping or `unknown` and narrow.
- Use `undefined` instead of `null`, except when inserting SQL `NULL` values into a database.
- Use `??` for default values instead of `||`.
- Use `readonly` for arrays and properties that must not mutate.
- Model finite states with discriminated unions.
- Prefer `// @ts-expect-error -- reason` over `// @ts-ignore`. Always include a reason after `--`.

## Error Handling

- Before creating a new error type, search the project and dependencies for an existing error class matching the failure context.
- Throw `Error` objects with descriptive messages. Do not throw strings or other primitive values.
- When wrapping a lower-level error, attach it via the `cause` option: `throw new Error('failed to load config', { cause: err })`.
- Do not leave `catch` blocks empty.
- Before throwing or logging an error, check whether the message includes sensitive information and sanitize it when needed.

## Lint Rules and Suppressions

- If a rule needs to be disabled, prefer changing `eslint.config.js` or `xo.config.{js,ts}` instead of adding inline disable comments.
- Explain the justification to the user and ask for confirmation before disabling a lint rule.
- Do not disable `unicorn/no-process-exit`. Add `import process from 'node:process'` when needed.
- Only use narrow, justified, single-line suppressions with a reason after `--`:
  ```ts
  // eslint-disable-next-line unicorn/prefer-module -- Required by legacy CJS runtime.
  const path = require('node:path')
  ```
- Never use file-wide `/* eslint-disable */`. If a rule must be off project-wide, edit the config and document why (requires user approval).

## XO (when present)

XO is an opinionated ESLint wrapper with TypeScript support, auto file discovery, caching, and `--fix`. Detect and respect existing XO setup rather than introducing changes.

### Detect first, then act

1. Look for existing config in this order: `xo.config.ts`, `xo.config.js`, `package.json` `xo` field, then `xo` as a `devDependency`.
2. Check `package.json` scripts for `lint`, `lint:fix`, `test`.
3. Follow existing project config exactly. Do not change rules to fit your code — change the code to fit the rules.

### Workflow

- Install locally when adding to a project: `pnpm add -D xo`.
- Prefer project scripts:
  ```json
  { "scripts": { "lint": "xo", "lint:fix": "xo --fix" } }
  ```
- Goal: pass XO with minimal project-specific overrides.

### XO defaults

- Tab indentation unless config sets `space: true` or `space: N`.
- Semicolons on.
- Single quotes (matches the general rule above).
- Trailing commas in multiline.
- Strict equality `===` / `!==`.
- No unused vars, imports, params, or types.

If `xo.config.*` overrides any of these, the config wins.

### Config snippets

Minimal:

```js
/** @type {import('xo').FlatXoConfig} */
export default []
```

Typical project config:

```js
/** @type {import('xo').FlatXoConfig} */
export default [
  { ignores: ['coverage/**', 'dist/**', 'build/**'] },
  {
    files: ['**/*.{js,ts,tsx}'],
    space: 2,
    semicolon: true,
    rules: {
      // Keep overrides small and justified.
    },
  },
]
```

React: run `xo --react` or enable React in the flat config block.

Prettier: do not introduce it. If already present, use XO's `prettier: 'compat'` or match the existing setup.

## Replaced Packages

Do not add these legacy packages to new projects. Use the modern replacement instead.

| Legacy package | Replacement | Notes |
|---------------|-------------|-------|
| `lodash` | native `Array`/`Object`/`Map`/`Set` methods, `structuredClone` | Every lodash utility (`_.map`, `_.filter`, `_.cloneDeep`, `_.merge`, `_.debounce`, `_.pick`, `_.omit`) has a built-in equivalent in ES2024+. Stop importing it. |
| `axios` | native `fetch` (Undici) | Node ships `fetch` globally since v18. For retry/timeout patterns use a thin wrapper (e.g., `ky`) or Undici `Agent`/`ProxyAgent` — not a full HTTP library that reimplements fetch. |
| `moment` | `Temporal` (global, Node 26+) / `date-fns` / `dayjs` | `moment` is in maintenance mode, mutable, and bundles all locales. Prefer native `Temporal` on Node 26+; `date-fns` or `dayjs` for broader runtime support. |
| `uuid` | `crypto.randomUUID()` | Built into Node 19+. Zero deps, one call. |
| `node-fetch` | native `fetch` | Built into Node 18+. Remove the dependency. |
| `request` | native `fetch` | Deprecated since 2020. No longer maintained. |
| `rimraf` | `fs.rm(path, { recursive: true })` | Built into Node 14.14+. One line, no dependency. |
| `mkdirp` | `fs.mkdir(path, { recursive: true })` | Built into Node 10.12+. Drop the package. |
| `dotenv` | `node --env-file=.env` | Built into Node 20.6+. No runtime dependency needed. |
| `bluebird` | native `Promise`, `Promise.allSettled/any/try` | All Bluebird features are now in the language (ES2015–2024). |
| `core-js` | native ES2024+ | Unnecessary for Node 24+ targets. V8 14.x ships everything `target: es2025` needs. |
| `qs` | `URLSearchParams` | Built into all modern runtimes. |
| `chalk` | `util.styleText()` | Built into Node 21.7+. Colors, bold, underline — no dependency. |
| `cross-env` | native `NODE_ENV=production node ...` | Node 20+ handles cross-platform env vars natively. Windows catches up. |
| `deep-clone` / `clone` | `structuredClone()` | Built into Node 17+. Deep copies objects, handles circular refs. |
| `cross-fetch` / `isomorphic-fetch` | native `fetch()` | Fetch is native in Node 18+, browsers, Deno, Bun. No polyfill needed. |
| `form-data` | `FormData` global | Built into Node 17+. |
| `abort-controller` | `AbortController` global | Built into Node 15+. |
| `left-pad` | `String.prototype.padStart()` | ES2017. The incident that broke the internet for a reason. |
| `foreach` / `isarray` / `isobject` | `Array.forEach`, `Array.isArray`, `typeof x === 'object'` | ES5. Literally part of the language for over a decade. |
| `readable-stream` | native `node:stream` | Node has had streams from day one. The polyfill is never needed. |
| `underscore` | native methods | Predates ES5+. Replace with built-in `Array`, `Object`, `Map`, `Set` methods. |

## Post-Edit Validation

- After modifying code, run `pnpm lint:fix` when both conditions are true:
  - The project `package.json` has a `lint:fix` script.
  - The working directory contains `pnpm-lock.yaml`.
- For XO projects, also run `pnpm lint` after `pnpm lint:fix` to surface remaining failures.

## Pre-finalize checklist

- Lint (`xo` or `eslint`) passes, or remaining failures are reported to the user.
- No `any`, no unused code, no unexplained suppressions.
- Errors thrown as `Error`, with `cause` when wrapping a lower-level error.
- Project's existing lint config respected — no new rule overrides added without approval.
