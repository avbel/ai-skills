---
name: biome-js
description: Use when configuring Biome for JavaScript or TypeScript projects, especially when replacing XO/ESLint/Prettier with strict formatter, linter, assist, import sorting, and VS Code save-time checks.
---

# Biome JS/TS

Use Biome as the single fast formatter, linter, import organizer, and safe-fix runner for JavaScript and TypeScript projects. The target style is XO-strict where Biome can express it, with explicit notes for XO rules Biome cannot fully replace.

## Baseline Workflow

1. Inspect existing tooling before changing anything:
   - `biome.json`, `biome.jsonc`, `.prettierrc*`, `eslint.config.*`, `.eslintrc*`, `xo.config.*`, and `package.json` scripts.
   - If XO or ESLint already exists, run `biome migrate eslint --write` only as a starting point, then tighten the config manually.
2. Install locally:
   ```bash
   pnpm add -D @biomejs/biome
   ```
3. Add scripts:
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
4. Keep `tsc --noEmit` in CI for semantic TypeScript checks. Biome replaces many XO/ESLint/Prettier checks, but it is not a full type-aware TypeScript checker.
5. After edits, run `pnpm lint:fix`, then `pnpm lint`, then project tests.

For snippet generation, run:

```bash
bash /mnt/skills/user/biome-js/scripts/biome-js-bootstrap.sh strict
```

## Formatter Sample

XO-like formatter settings:

```jsonc
{
  "$schema": "./node_modules/@biomejs/biome/configuration_schema.json",
  "formatter": {
    "enabled": true,
    "formatWithErrors": false,
    "indentStyle": "tab",
    "lineEnding": "lf",
    "lineWidth": 100,
    "bracketSpacing": false
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "single",
      "jsxQuoteStyle": "single",
      "quoteProperties": "asNeeded",
      "trailingCommas": "all",
      "semicolons": "always",
      "arrowParentheses": "asNeeded",
      "operatorLinebreak": "before"
    }
  },
  "json": {
    "formatter": {
      "trailingCommas": "none"
    }
  }
}
```

Adjust only when the existing repo already has a deliberate style. Biome defaults differ from XO: Biome defaults to double quotes and 80-column formatting, while XO prefers single quotes and semicolons.

## Strict Linter Sample

Start with recommended rules, then promote XO-equivalent and XO-adjacent rules explicitly:

```jsonc
{
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "complexity": {
        "noExcessiveCognitiveComplexity": {
          "level": "warn",
          "options": { "maxAllowedComplexity": 15 }
        },
        "noExcessiveLinesPerFunction": {
          "level": "warn",
          "options": { "maxLines": 80, "skipBlankLines": true }
        },
        "noForEach": "warn",
        "noStaticOnlyClass": "error",
        "noUselessCatch": "error",
        "noVoid": "error",
        "useArrowFunction": "error",
        "useOptionalChain": "error",
        "useRegexLiterals": "error"
      },
      "correctness": {
        "noChildrenProp": "error",
        "noInvalidUseBeforeDeclaration": "error",
        "noNodejsModules": "off",
        "noProcessGlobal": "error",
        "noUndeclaredDependencies": "error",
        "noUnusedFunctionParameters": "error",
        "noUnusedImports": "error",
        "noUnusedVariables": "error",
        "useImportExtensions": "off",
        "useJsonImportAttributes": "error",
        "useParseIntRadix": "error"
      },
      "security": {
        "noBlankTarget": "error",
        "noDangerouslySetInnerHtml": "error",
        "noGlobalEval": "error"
      },
      "style": {
        "noCommonJs": "error",
        "noDefaultExport": "off",
        "noDoneCallback": "error",
        "noInferrableTypes": "error",
        "noNamespace": "error",
        "noNonNullAssertion": "warn",
        "noParameterAssign": "error",
        "noRestrictedGlobals": {
          "level": "error",
          "options": {
            "deniedGlobals": {
              "event": "Use an explicit local variable instead.",
              "error": "Use an explicit local variable instead.",
              "atob": "Use Buffer, Uint8Array helpers, or a project-approved decoder.",
              "btoa": "Use Buffer, Uint8Array helpers, or a project-approved encoder."
            }
          }
        },
        "noRestrictedImports": {
          "level": "error",
          "options": {
            "paths": {
              "domain": "Deprecated Node.js module.",
              "freelist": "Deprecated Node.js module.",
              "punycode": "Deprecated Node.js module.",
              "querystring": "Use URLSearchParams.",
              "smalloc": "Deprecated Node.js module.",
              "sys": "Deprecated Node.js module.",
              "colors": "Use util.styleText() or a project-approved logger."
            }
          }
        },
        "useAsConstAssertion": "error",
        "useBlockStatements": "error",
        "useConsistentArrayType": "error",
        "useConst": "error",
        "useDefaultParameterLast": "error",
        "useEnumInitializers": "error",
        "useExportType": "error",
        "useFilenamingConvention": "warn",
        "useImportType": "error",
        "useNamingConvention": "error",
        "useNodejsImportProtocol": "error",
        "useSelfClosingElements": "error",
        "useShorthandFunctionType": "error",
        "useTemplate": "error"
      },
      "suspicious": {
        "noArrayIndexKey": "error",
        "noAssignInExpressions": "error",
        "noConsole": "warn",
        "noDebugger": "error",
        "noDoubleEquals": "error",
        "noExplicitAny": "error",
        "noFocusedTests": "error",
        "noImplicitAnyLet": "error",
        "noShadowRestrictedNames": "error",
        "noTsIgnore": "error",
        "noUnsafeDeclarationMerging": "error",
        "useDefaultSwitchClauseLast": "error"
      }
    }
  }
}
```

Tune frontend-only security/a11y rules for React, Vue, Qwik, and Solid projects. For Node-only packages, keep JSX-specific rules enabled if they never trigger; disable them only when they create false positives.

## XO to Biome Porting

Use this map when replacing XO:

| XO / ESLint intent | Biome equivalent |
|---|---|
| `eqeqeq` | `suspicious.noDoubleEquals` |
| `no-debugger` | `suspicious.noDebugger` |
| `no-unused-vars`, unused imports | `correctness.noUnusedVariables`, `correctness.noUnusedImports`, `correctness.noUnusedFunctionParameters` |
| `prefer-const` | `style.useConst` |
| `curly` | `style.useBlockStatements` |
| `no-process-exit` / Node globals discipline | `correctness.noProcessGlobal` plus explicit `import process from 'node:process'` |
| `unicorn/prefer-node-protocol` | `style.useNodejsImportProtocol` |
| `@typescript-eslint/no-explicit-any` | `suspicious.noExplicitAny` |
| `@typescript-eslint/consistent-type-imports` | `style.useImportType`, `style.useExportType` |
| `no-restricted-imports` | `style.noRestrictedImports` |
| `no-restricted-globals` | `style.noRestrictedGlobals` |
| `complexity`, `max-lines`, `max-params` | `complexity.noExcessiveCognitiveComplexity`, `complexity.noExcessiveLinesPerFunction`, `complexity.useMaxParams` |
| `sort-imports`, `import/order`, duplicate imports | `assist.source.organizeImports` |
| Prettier/XO stylistic formatting | Biome formatter options, not linter rules |

Known gaps:

- Biome does not fully replace type-aware rules such as `no-floating-promises`, `no-misused-promises`, or exhaustive switch checks. Keep `tsc --noEmit`; keep a small ESLint/XO layer only if the project truly needs those semantic rules.
- Biome does not implement every Unicorn rule. Prefer explicit Biome rules plus project conventions instead of inventing broad suppressions.
- Biome unsafe fixes may change behavior. Do not apply `--unsafe` automatically in save hooks or CI.

## Assist and Import Sorting

Enable safe source actions:

```jsonc
{
  "assist": {
    "enabled": true,
    "actions": {
      "source": {
        "recommended": true,
        "organizeImports": "on"
      }
    }
  }
}
```

Use `biome check --write .` for safe format, lint fixes, and assist actions. Use `biome lint --write --unsafe ./src` only after reviewing the diff.

## VS Code

Install the official extension:

- `biomejs.biome` — first-party Biome language server, formatter, linter diagnostics, quick fixes, and import organization.

Use workspace settings:

```jsonc
{
  "editor.defaultFormatter": "biomejs.biome",
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.biome": "explicit",
    "source.organizeImports.biome": "explicit"
  },
  "biome.enabled": true,
  "biome.requireConfiguration": true
}
```

If the repo still has ESLint or Prettier, set their save-time formatters/fixers off for Biome-owned file types to avoid dueling edits.

## Present Results

When reporting a Biome migration:

- Name what was replaced: formatter, linter, import sorting, safe fixes, CI command.
- Call out any XO rules that remain unmatched and whether `tsc` or a small ESLint layer covers them.
- Report exact validation commands and remaining diagnostics.
