---
name: js-conventions
description: JavaScript and TypeScript project conventions for Node.js 24+, pnpm, ESM, ES2024+, async patterns, type safety, error handling, lint configuration, and post-edit validation. Use when writing or modifying .js, .jsx, .mjs, .ts, .tsx, or .mts files.
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

## Type Safety

- Do not use `any` in TypeScript. Use proper type mapping or `unknown`.
- Use `undefined` instead of `null`, except when inserting SQL `NULL` values into a database.
- Use `??` for default values instead of `||`.

## Error Handling

- Before creating a new error type, search the project and dependencies for an existing error class matching the failure context.
- Throw `Error` objects with descriptive messages. Do not throw strings or other primitive values.
- Do not leave `catch` blocks empty.
- Before throwing or logging an error, check whether the message includes sensitive information and sanitize it when needed.

## ESLint Rules

- If a rule needs to be disabled, prefer changing `eslint.config.js` or `xo.config.js` instead of adding inline disable comments.
- Explain the justification to the user and ask for confirmation before disabling a lint rule.
- Do not disable `unicorn/no-process-exit`. Add `import process from 'node:process'` when needed.

## Post-Edit Validation

- After modifying code, run `pnpm lint:fix` when both conditions are true:
  - The project `package.json` has a `lint:fix` script.
  - The working directory contains `pnpm-lock.yaml`.

