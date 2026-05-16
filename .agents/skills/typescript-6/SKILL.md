---
name: typescript-6
description: TypeScript 6.0 (March 2026) conventions — the final JS-based compiler before the Go-native 7.0 rewrite. New defaults (strict, module esnext, target es2025, types []), language features (less context-sensitive this-less functions, #/ subpath imports, --moduleResolution bundler + --module commonjs), new built-in types (Temporal, Map upsert, RegExp.escape), and deprecations (baseUrl, target es5, --downlevelIteration, --moduleResolution node, AMD/UMD/SystemJS, import assertions). Use when configuring or upgrading to TypeScript 6.
---

Apply these conventions when working with TypeScript 6.0+ (released 2026-03-23). 6.0 is a **bridge release** — the final version on the JavaScript-based compiler. The next major (7.0) is a Go-native rewrite. Most 6.0 changes are about modern defaults and deprecations; the goal is to make the 7.0 jump uneventful.

## New Compiler Defaults (these change build behavior)
- `strict: true` — was `false`. Implicit `any`, null checks, function types, bind/call/apply, property init, etc. all enforced by default.
- `module: "esnext"` — was `"commonjs"`. Output is ESM unless overridden.
- `target` — floats to the latest stable; in 6.0 it resolves to `"es2025"`.
- `types: []` — was implicitly "all `@types/*` in `node_modules`". Now you must opt-in: `"types": ["node", "jest"]`. Big perf and correctness win.
- `noUncheckedSideEffectImports: true` — bare `import "./foo"` now type-checks the imported module's existence.
- `rootDir: "."` — was inferred from the input file set. Output layout in monorepos is now stable across edits.

If a project breaks on upgrade, the cause is almost always one of these defaults — pin the old value explicitly in `tsconfig.json` and migrate one flag at a time.

## New Language / Inference Features

### Less context-sensitivity on `this`-less functions
- Method-syntax functions (`{ foo() { ... } }`) used to be treated as contextually sensitive because of an implicit `this` parameter, blocking them from being inference *sources* in generic calls.
- 6.0: if the body does not reference `this`, the function is no longer contextually sensitive — it participates in first-pass generic inference like arrow functions.
- Practical effect: many generic call sites no longer need explicit type arguments.
  ```ts
  declare function pipe<T>(value: T, fn: (x: T) => T): T

  // 5.x: needed pipe<number>(...), 6.0: inferred
  const result = pipe(42, { run(x) { return x + 1 } }.run)
  ```
- **Regression risk:** code that accidentally got correct types via *deferred* inference may now infer earlier with less context. Symptom: a generic param resolves to a narrower or wider type than before. Fix by adding an explicit type argument at the call site.

### `#/` subpath imports
- Node.js supports `imports` map entries whose key is `#/...` (a leading hash + slash). TypeScript now resolves these under `moduleResolution: "node16" | "nodenext" | "bundler"`.
  ```jsonc
  // package.json
  { "type": "module", "imports": { "#/utils/": "./src/utils/" } }
  ```
  ```ts
  import { slugify } from '#/utils/slugify.js'
  ```
- Prefer `#/` subpaths over `baseUrl`/`paths` for new code — they are a real Node feature (work at runtime), not a TS-only convention.

### `--moduleResolution bundler` + `--module commonjs`
- Previously disallowed; now permitted. Provides a migration path off the deprecated `--moduleResolution node` (alias `node10`) without forcing a full ESM switch.
- Recommended trajectory: `node10` → `bundler` + `commonjs` → `nodenext` (with ESM) or `preserve` + `bundler`.

### `--stableTypeOrdering` migration flag
- Forces deterministic union/intersection ordering matching the TS 7.0 Go compiler.
- Use it to compare `.d.ts` output and inferred type strings between 6.0 and 7.0 previews so you can fix order-sensitive snapshots before the 7.0 jump.

## New Built-in Type Coverage

### `target`/`lib`: `es2025`
- New `"es2025"` option for `target` and `lib`. No new ES2025 language syntax, but consolidates types for `Promise.try`, `Iterator.prototype.*` helpers, set-theory `Set` methods, `RegExp.escape`, etc. that previously lived in `esnext`.

### Temporal
- Built-in types via `lib: ["esnext.temporal"]` (or any `lib` that transitively pulls it in).
- Covers `Temporal.Instant`, `Temporal.ZonedDateTime`, `Temporal.PlainDate`, `Temporal.PlainTime`, `Temporal.PlainDateTime`, `Temporal.PlainYearMonth`, `Temporal.PlainMonthDay`, `Temporal.Duration`, `Temporal.Now`.

### Upsert / `Map.getOrInsert`
- Types for the Stage 4 upsert proposal: `Map.prototype.getOrInsert`, `Map.prototype.getOrInsertComputed`, plus `WeakMap` equivalents.

### `RegExp.escape`
- Typed as `(str: string) => string`.

### DOM lib consolidation
- `dom` now transitively includes `dom.iterable` and `dom.asynciterable` — you no longer need to list them separately in `lib`.

## Type-Checking Adjustments (may catch new bugs)
- Tighter checking for function expressions used as arguments in **generic JSX expressions**. Some calls may now need an explicit type argument.
- DOM types refreshed to current standards (includes Temporal alignment in web APIs).
- Import-assertion `assert` keyword on dynamic `import()` is deprecated — same as static imports.

## Deprecations (still work in 6.0, removed in 7.0)
- `baseUrl` — replace with `paths` (explicit mappings) or `#/` subpath imports.
- `target: "es5"` — pick `es2020` or later. Real engines have moved on.
- `--downlevelIteration` — irrelevant once `target` is `es2015`+; setting it at all now errors.
- `--moduleResolution node` / `node10` — migrate to `bundler`, `node16`, `node20`, or `nodenext`.
- `module: "amd" | "umd" | "system"` — pick a modern format.
- `assert { type: 'json' }` import attributes — use the standardized `with { type: 'json' }`.
- Some less-used `out*` and concatenation options (`outFile` with non-AMD/System targets, etc.).

A 6.0 build emits these as deprecation diagnostics. Fix them now — they will fail in 7.0.

## Recommended tsconfig.json for new Node.js 24+/26 services

```jsonc
{
  "compilerOptions": {
    "target": "es2025",
    "lib": ["es2025", "esnext.temporal"],
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "types": ["node"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "noUncheckedSideEffectImports": true,
    "skipLibCheck": true,
    "rootDir": ".",
    "outDir": "./dist"
  }
}
```

## Upgrade Checklist
- [ ] Bump `typescript` to `^6.0.0` in `package.json`. Confirm the editor uses the workspace version, not a bundled older one.
- [ ] If your tsconfig was implicit, set the **old** defaults explicitly first (`strict: false`, `module: "commonjs"`, `target: "es2020"`, `types`-list, `rootDir`) so the upgrade is a no-op, then flip flags one at a time.
- [ ] Grep for `assert { type:` in dynamic `import(...)` — rewrite as `with { type: ... }`.
- [ ] Replace `baseUrl` with either `paths` or `#/` subpath imports.
- [ ] Replace `moduleResolution: "node"` / `"node10"` — pick `bundler`, `node16`, or `nodenext`.
- [ ] Remove `--downlevelIteration` from scripts and `tsconfig`.
- [ ] If you ship `target: "es5"`, choose `es2020`+; rely on engine support, not transpilation.
- [ ] Once green, run `tsc --stableTypeOrdering` and update any `.d.ts` golden files / Cypress/Vitest type snapshots ahead of the 7.0 jump.
- [ ] Try the TypeScript 7.0 native preview against the project to surface lingering issues early.

## Editor / Tooling Notes
- VS Code TypeScript Server, eslint-plugin-typescript, ts-node, tsx, esbuild, swc, and Vite all received same-week 6.0 compatibility patches — pin recent versions.
- Linters that read tsconfig (`@typescript-eslint/parser`) need the new defaults — bump to a version released after 2026-03-23.

## 7.0 Outlook (informational — do not target yet)
- 7.0 is a ground-up Go rewrite of the compiler and language service. Multi-threaded type checking, much faster cold builds, native binaries.
- 7.0 will **not** carry the 6.0-deprecated options. The 6.0 release is the deprecation window — get clean now to make the 7.0 jump near-trivial.
