---
name: typescript-7
description: Use when configuring new TypeScript 7 projects, porting TypeScript 6 codebases, diagnosing TypeScript 7 compiler or tsconfig errors, or checking whether compiler-API, editor, framework, and embedded-language tooling must remain on TypeScript 6.
---

# TypeScript 7

Use stable TypeScript 7 for new `tsc` and LSP-based projects. Microsoft's [7.0 release announcement](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/) documents this Go-native port, its typical 8-12x full-build speedup, and the absence of a stable 7.0 programmatic API. Treat CLI/LSP adoption separately from tools that import `typescript`.

## Quick Reference

| Need | Action |
|---|---|
| Install stable 7.x | `pnpm add -D typescript@^7 @types/node` |
| Confirm the compiler | `pnpm exec tsc --version` |
| Keep the TypeScript 6 API | Use the `@typescript/typescript6` compatibility package side-by-side |

Stable releases use the ordinary `typescript` package and `tsc`. Do not prescribe the preview-only `@typescript/native-preview` package or `tsgo` command.

## Choose 7 or 6

Use 7 for new `.ts` projects. Verify explicit 7.x support before switching a Compiler API consumer, custom transformer, legacy `tsserver` plugin, or embedded-language stack such as Vue, MDX, Astro, Svelte, or Angular template checking. A project can run TypeScript 7 CLI checks while API-dependent tools use TypeScript 6 side-by-side.

## New Node.js 26 Project

Use [Node.js 26](../nodejs-26/SKILL.md) for runtime behavior. For ESM output executed directly by Node, pin the defaults:

```jsonc
{
  "compilerOptions": {
    "target": "es2025",
    "lib": ["es2025", "esnext.temporal"],
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "rootDir": "./src",
    "outDir": "./dist",
    "types": ["node"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noUncheckedSideEffectImports": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "sourceMap": true,
    "noEmitOnError": true
  },
  "include": ["src/**/*.ts"]
}
```

Set `"type": "module"` in `package.json` and use `.js` extensions in relative imports. For bundler-owned resolution/emission, use `module: "preserve"`, `moduleResolution: "bundler"`, and usually `noEmit: true`. TypeScript does not make source directly executable by Node.

## Port TypeScript 6 Projects to TypeScript 7

Read [Porting from TypeScript 6](references/porting-from-typescript-6.md) before changing dependencies:

1. Update TypeScript 6, remove `ignoreDeprecations`, fix 6.0 deprecations, and pass `tsc --stableTypeOrdering`.
2. Inventory tools that import `typescript` or embed its language service.
3. Make each required configuration/runtime change under TypeScript 6 and verify it separately.
4. Install TypeScript 7 alone, or use the official TypeScript 6 compatibility package side-by-side.
5. Compare diagnostics, output, tests, consumers, wall time, and peak memory.

Do not combine the compiler switch with optional ESM, target, or strictness modernization. TypeScript 7 turns deprecated TypeScript 6 options into hard errors.

## Verify the Installed Compiler

```bash
bash /mnt/skills/user/typescript-7/scripts/check-compiler.sh ./node_modules/.bin/tsc
```

For a Claude Code installation, use `~/.claude/skills/typescript-7/scripts/check-compiler.sh` instead.

**Arguments:** optional compiler command or executable path; defaults to `./node_modules/.bin/tsc`.

## Output

Success writes `{"ok":true,"version":"7.0.2"}` to stdout. Failures return non-zero with `compiler_not_executable`, `version_check_failed`, `version_unrecognized`, or `wrong_major` JSON.

## Present Results to User

Report the resolved compiler version, or the exact error key and remediation.

## Troubleshooting

- `compiler_not_executable`: install dependencies or pass an executable/PATH command. TypeScript 7 uses platform-specific optional packages, so do not omit optional dependencies; verify the compiler inside the target CI/container platform.
- `version_check_failed`: run the compiler directly and inspect stderr.
- `version_unrecognized`: inspect the reported version output; the checker accepts stable `Version X.Y.Z` output.
- `wrong_major`: fix the package-manager link; do not continue the migration.

## Primary Sources

- [Announcing TypeScript 7.0](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/)
- [TypeScript 7 native-port repository](https://github.com/microsoft/typescript-go)
- [Intentional TypeScript 6-to-7 changes](https://github.com/microsoft/typescript-go/blob/typescript/v7.0.2/CHANGES.md)
