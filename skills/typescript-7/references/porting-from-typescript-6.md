# Porting from TypeScript 6

## Contents

- [Prepare TypeScript 6](#prepare-typescript-6)
- [Inventory API coupling](#inventory-api-coupling)
- [Replace removed configuration](#replace-removed-configuration)
- [Choose one compiler or side-by-side](#choose-one-compiler-or-side-by-side)
- [Validate the port](#validate-the-port)
- [Review JavaScript and JSDoc projects](#review-javascript-and-jsdoc-projects)

## Prepare TypeScript 6

Update to the latest TypeScript 6 patch. Remove `ignoreDeprecations`, fix every 6.0 deprecation, and enable stable type ordering before changing compilers:

```bash
pnpm exec tsc -p tsconfig.json --noEmit --stableTypeOrdering
pnpm test
pnpm run build
```

A TypeScript 6 project that is clean with `stableTypeOrdering`, no ignored deprecations, and the removed-configuration table below applied should type-check compatibly under TypeScript 7. Preserve the lockfile plus baseline diagnostics, emitted JavaScript, declarations, build time, and peak memory.

## Inventory API Coupling

Identify dependencies and scripts that import `typescript`, call the Compiler API, load custom transformers, register `tsserver` plugins, or assume `tsc` is a JavaScript file. Check framework compilers, `typescript-eslint`, API Extractor, test transforms, editor integrations, and build plugins against their current TypeScript 7 support matrices.

Do this before replacing the package. TypeScript 7.0's `tsc` and LSP are production-ready, but 7.0 does not expose a stable programmatic API.

## Replace Removed Configuration

TypeScript 7 turns these TypeScript 6 deprecations into hard errors or fixed behavior:

| TypeScript 6 configuration or syntax | TypeScript 7 action |
|---|---|
| `target: "es5"` | Raise the target to a supported runtime |
| `downlevelIteration` | Remove it |
| `moduleResolution: "node"`, `"node10"`, or `"classic"` | Use `nodenext` for direct Node execution or `bundler` for bundler-owned resolution |
| `module: "amd"`, `"umd"`, `"system"`, or `"none"` | Use `nodenext`, `esnext`, or `preserve` as appropriate |
| `baseUrl` | Remove it; make `paths` relative to the tsconfig file that declares them, or use package import maps |
| `esModuleInterop: false` or `allowSyntheticDefaultImports: false` | Remove the false setting; both behaviors are enabled |
| `alwaysStrict: false` | Remove it; strict-mode emit is assumed |
| `outFile` | Remove it and use an external bundler |
| `module X {}` namespace declarations | Write `namespace X {}` |
| Static `assert { type: "json" }` imports | Use `with { type: "json" }` |
| Dynamic import option `{ assert: { type: "json" } }` | Use `{ with: { type: "json" } }` |
| `/// <reference no-default-lib="true" />` | Use `noLib` or `libReplacement` as appropriate |
| Source-file arguments while a local `tsconfig.json` exists | Use `-p`, or pass `--ignoreConfig` deliberately |

`paths` does not rewrite emitted imports. Direct Node output still needs runtime-resolvable specifiers, package exports/imports, or an appropriate loader.

Make unavoidable changes, such as raising `es5`, as separate TypeScript 6 commits and verify their runtime effects before switching compilers. Do not mix in optional ESM, target, or strictness modernization.

## Choose One Compiler or Side-by-Side

If no tool imports the TypeScript API:

```bash
pnpm add -D typescript@^7
pnpm exec tsc --version
```

If API-dependent tools still require TypeScript 6, use Microsoft's [documented alias arrangement](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/#running-side-by-side-with-typescript-60):

```jsonc
{
  "devDependencies": {
    "@typescript/native": "npm:typescript@^7.0.2",
    "typescript": "npm:@typescript/typescript6@^6.0.2"
  },
  "scripts": {
    "typecheck": "tsc -p tsconfig.json --noEmit",
    "typecheck:legacy": "tsc6 -p tsconfig.json --noEmit"
  }
}
```

The compatibility package's bin map exposes only `tsc6`; TypeScript 7 exposes `tsc`, so the names do not collide. After `pnpm install`, verify the selected compiler before continuing:

```bash
bash /mnt/skills/user/typescript-7/scripts/check-compiler.sh ./node_modules/.bin/tsc
pnpm exec tsc6 --version
```

Remove this bridge once API consumers support TypeScript 7.

TypeScript 7's npm package selects a platform-specific compiler through optional dependencies. Do not omit optional dependencies. For cross-platform lockfiles, configure pnpm `supportedArchitectures`, and run the compiler check inside every release container or target CI platform.

## Validate the Port

```bash
pnpm exec tsc --version
pnpm exec tsc -p tsconfig.json --noEmit
pnpm test
pnpm run build
```

Also verify:

- emitted JavaScript and application smoke behavior;
- `.d.ts` output, declaration snapshots, and representative downstream consumers;
- ESM/CommonJS interop, package exports, and relative extensions;
- TypeScript code generation such as decorators, enums, namespaces, and class fields;
- CI wall time and peak memory.

Start parallelism tuning only after correctness. `--checkers` and `--builders` multiply; use `--singleThreaded` to distinguish compiler concurrency from an externally parallel build.

## Review JavaScript and JSDoc Projects

JavaScript checking and declaration emit have larger intentional differences. Review the upstream [CHANGES.md](https://github.com/microsoft/typescript-go/blob/typescript/v7.0.2/CHANGES.md), especially Closure-style JSDoc, constructor/expando patterns, CommonJS inference, and declarations emitted from `.js`.

Template-literal inference also preserves full Unicode code points in TypeScript 7. Re-run type-level string tests that assumed UTF-16 code units.
