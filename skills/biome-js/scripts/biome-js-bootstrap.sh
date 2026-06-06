#!/bin/bash
set -e

scenario="${1:-strict}"

case "$scenario" in
  strict)
    description='Strict XO-like Biome setup for JavaScript and TypeScript projects.'
    package_scripts='{
  "scripts": {
    "format": "biome format --write .",
    "lint": "biome lint .",
    "lint:fix": "biome check --write .",
    "ci": "biome ci ."
  },
  "devDependencies": {
    "@biomejs/biome": "^2.3.11"
  }
}'
    biome_jsonc='{
  "$schema": "./node_modules/@biomejs/biome/configuration_schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "files": {
    "ignoreUnknown": false,
    "includes": [
      "**",
      "!dist/**",
      "!build/**",
      "!coverage/**",
      "!node_modules/**"
    ]
  },
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
  },
  "assist": {
    "enabled": true,
    "actions": {
      "source": {
        "recommended": true,
        "organizeImports": "on"
      }
    }
  },
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
        "noUselessCatch": "error",
        "noVoid": "error",
        "useArrowFunction": "error",
        "useOptionalChain": "error",
        "useRegexLiterals": "error"
      },
      "correctness": {
        "noInvalidUseBeforeDeclaration": "error",
        "noNodejsModules": "off",
        "noProcessGlobal": "error",
        "noUndeclaredDependencies": "error",
        "noUnusedFunctionParameters": "error",
        "noUnusedImports": "error",
        "noUnusedVariables": "error",
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
}'
    vscode_settings='{
  "editor.defaultFormatter": "biomejs.biome",
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.biome": "explicit",
    "source.organizeImports.biome": "explicit"
  },
  "biome.enabled": true,
  "biome.requireConfiguration": true
}'
    ;;
  *)
    echo "Usage: $0 [strict]" >&2
    exit 2
    ;;
esac

SCENARIO="$scenario" DESCRIPTION="$description" PACKAGE_SCRIPTS="$package_scripts" BIOME_JSONC="$biome_jsonc" VSCODE_SETTINGS="$vscode_settings" python3 <<'PY'
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "description": os.environ["DESCRIPTION"],
    "packageJson": os.environ["PACKAGE_SCRIPTS"],
    "biomeJsonc": os.environ["BIOME_JSONC"],
    "vscodeSettings": os.environ["VSCODE_SETTINGS"],
}, indent=2))
PY
