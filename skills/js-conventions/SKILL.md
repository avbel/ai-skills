---
name: js-conventions
description: JavaScript and TypeScript project conventions for Node.js 24+, pnpm, ESM, ES2024+, async patterns, type safety, error handling, format and lint configuration (Biome, XO, or ESLint), and post-edit validation. Use when writing or modifying .js, .jsx, .mjs, .ts, .tsx, or .mts files.
---

# JavaScript and TypeScript Conventions

Apply these conventions in JavaScript and TypeScript projects. These rules are written for any coding agent, including Claude Code, Codex, Cursor, and Copilot.

## Package Manager

- Use `pnpm`, not `npm` or `yarn`.

## Format and Lint Toolchain

A project has exactly one authoritative formatter/linter setup. Detect it before writing or reformatting code, and never run a second one over the same files.

Detection order — first match wins:

1. [Biome](https://biomejs.dev/) — `biome.json`, `biome.jsonc`, or `@biomejs/biome` in `devDependencies`. See [Biome (when present)](#biome-when-present).
2. [XO](https://github.com/xojs/xo) — `xo.config.ts`, `xo.config.js`, an `xo` field in `package.json`, or `xo` in `devDependencies`. See [XO (when present)](#xo-when-present).
3. [ESLint](https://eslint.org/docs/latest/use/configure/configuration-files) — `eslint.config.{js,mjs,ts}` (flat config) or a legacy `.eslintrc*`.
4. Nothing configured — for a new project prefer Biome: one binary covers formatting, linting, and import sorting, so no Prettier is needed. Ask before adding it to an existing project.

Whatever is found, follow it exactly: change the code to fit the config, not the config to fit the code. Do not introduce Prettier — Biome and XO both format.

## Code Style

- Read and follow code style rules defined in Biome config (`biome.json` / `biome.jsonc`), XO config, ESLint config, or the ESLint/XO section in `package.json`.
- Use single quotes for strings.
- Use `const` for variables that are never reassigned. Use `let` only when reassignment is required.
- Use camelCase for constants and variables. Prefer camelCase over UPPER_SNAKE_CASE for constants; note that Biome's recommended `useNamingConvention` (see `biome-js`) still permits CONSTANT_CASE for module-level `const`s, so existing CONSTANT_CASE constants are not lint errors — just don't introduce new ones.
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

- If a rule needs to be disabled, prefer changing the project config (`biome.json` / `biome.jsonc`, `eslint.config.js`, or `xo.config.{js,ts}`) instead of adding inline disable comments.
- Explain the justification to the user and ask for confirmation before disabling a lint rule.
- Do not disable `unicorn/no-process-exit` (ESLint/XO) or `correctness.noProcessGlobal` (Biome). Both stop reporting once you `import process from 'node:process'` — do that instead.
- Only use narrow, justified, single-line suppressions, and always include a reason.

  ESLint and XO — reason after `--`:

  ```ts
  // eslint-disable-next-line unicorn/prefer-module -- Required by legacy CJS runtime.
  const path = require('node:path')
  ```

  Biome — reason after `:` is mandatory; target the most specific category ([suppression syntax](https://biomejs.dev/analyzer/suppressions/)):

  ```ts
  // biome-ignore lint/suspicious/noExplicitAny: Upstream package ships no types.
  const payload = raw as any;
  ```

- Never suppress a whole file: no `/* eslint-disable */`, no top-of-file `// biome-ignore-all`. If a rule must be off for a path, add a scoped `overrides` entry in the config and document why (requires user approval).
- Biome range suppressions (`// biome-ignore-start` / `// biome-ignore-end`) are a last resort for generated blocks; every start needs a matching end.

## Biome (when present)

[Biome](https://biomejs.dev/) is a single Rust binary that replaces Prettier plus ESLint: [formatter](https://biomejs.dev/formatter/), [linter](https://biomejs.dev/linter/), [assist and import sorting](https://biomejs.dev/assist/), and safe auto-fixes. Full configuration guidance lives in the `biome-js` skill — read it before creating or editing `biome.json`.

### Detect first, then act

1. Look for `biome.json` or `biome.jsonc` at the repo root (and in each package, for monorepos), then `@biomejs/biome` in `devDependencies`.
2. Check `package.json` scripts for `format`, `lint`, `lint:fix`, `ci`.
3. Follow the existing config exactly. Do not add rule overrides or change formatter options to make your code pass.

### Commands

| Task | Command |
|---|---|
| Format | `pnpm biome format --write .` |
| Lint | `pnpm biome lint .` |
| Format + safe lint fixes + import sorting | `pnpm biome check --write .` |
| CI check (no writes, non-zero exit on diagnostics) | `pnpm biome ci .` |
| Migrate an existing setup | `pnpm biome migrate eslint --write`, `pnpm biome migrate prettier --write` |

Typical project scripts:

```json
{
  "scripts": {
    "format": "biome format --write .",
    "lint": "biome lint .",
    "lint:fix": "biome check --write .",
    "ci": "biome ci ."
  }
}
```

### Rules of engagement

- Install locally: `pnpm add -D @biomejs/biome`. Do not invoke a global or `npx`-resolved Biome in a project that pins a version.
- Never run `--unsafe` fixes (`biome check --write --unsafe`) automatically. Unsafe fixes can change behavior — review the diff first, and keep them out of save hooks and CI.
- Biome is not a type checker. Keep `tsc --noEmit` in CI: type-aware rules such as `no-floating-promises` and `no-misused-promises` have no Biome equivalent. Keep a thin ESLint layer only if the project truly needs them.
- Biome defaults differ from the conventions above — double quotes and an 80-column width. A project following this style sets `javascript.formatter.quoteStyle: "single"` and its own `lineWidth` explicitly; see the `biome-js` skill for a full XO-strict config.
- Do not run Biome and ESLint/Prettier over the same files. If a migration is half-finished, either complete it or scope each tool to disjoint paths, and tell the user which is which.
- [`biome migrate`](https://biomejs.dev/guides/migrate-eslint-prettier/) is a starting point, not a finished config: review the output and tighten it manually. Use the [ESLint-to-Biome rule sources index](https://biomejs.dev/linter/rules-sources/) to find equivalents for rules the migration drops.

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
- For XO and ESLint projects, also run `pnpm lint` after `pnpm lint:fix` to surface remaining failures.
- For Biome projects, run `pnpm biome check --write .` (or the `lint:fix` script), then `pnpm biome lint .` to surface what auto-fix could not resolve. Never add `--unsafe` to make it pass.
- For TypeScript projects, also run `pnpm tsc --noEmit`. No linter — Biome included — replaces the type checker.

## Pre-finalize checklist

- Lint (`biome`, `xo`, or `eslint` — whichever the project uses) passes, or remaining failures are reported to the user.
- Formatting was applied by the project's formatter (`biome format` / `xo --fix`), not by hand.
- No `any`, no unused code, no unexplained suppressions.
- Errors thrown as `Error`, with `cause` when wrapping a lower-level error.
- Project's existing lint config respected — no new rule overrides added without approval.

## References

- Biome: [docs home](https://biomejs.dev/), [getting started](https://biomejs.dev/guides/getting-started/), [configuration reference](https://biomejs.dev/reference/configuration/), [CLI reference](https://biomejs.dev/reference/cli/), [JS/TS lint rules](https://biomejs.dev/linter/javascript/rules/), [suppressions](https://biomejs.dev/analyzer/suppressions/), [migrate from ESLint and Prettier](https://biomejs.dev/guides/migrate-eslint-prettier/)
- `biome-js` skill — XO-strict Biome config, XO-to-Biome rule map, VS Code save-time setup
- XO: [repository and rule documentation](https://github.com/xojs/xo)
- ESLint: [flat config files](https://eslint.org/docs/latest/use/configure/configuration-files)
