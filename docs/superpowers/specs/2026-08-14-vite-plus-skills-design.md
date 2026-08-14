# Vite+ Skill Family

## Goal

Add seven focused skills that teach agents to use the unified Vite+ toolchain
without duplicating the full documentation of Vite, Vitest, Oxlint, Oxfmt,
Rolldown, tsdown, or Vite Task.

The skills must distinguish Vite+ built-in commands from similarly named
`package.json` scripts, keep configuration in `vite.config.ts`, and route users
to the correct workflow for applications, tests, static checks, libraries, and
monorepo tasks.

## Source Baseline

Use current primary sources, rechecked on 2026-08-14:

- Vite+ repository and README: <https://github.com/voidzero-dev/vite-plus>
- Vite+ guide and command index: <https://viteplus.dev/guide>
- Vite+ configuration index: <https://viteplus.dev/config>
- Individual Vite+ guide and configuration pages for every command described
  by a skill
- Upstream documentation only for behavior Vite+ delegates to an integrated
  engine

Vite+ is still evolving. Each skill must tell agents to run `vp help`,
command-specific help, and `vp toolchain` before relying on version-sensitive
flags or bundled dependency versions.

## Chosen Structure

Create these skills under `skills/`:

1. `vite-plus`
2. `vite-plus-dev-build`
3. `vite-plus-test`
4. `vite-plus-lint`
5. `vite-plus-format`
6. `vite-plus-pack`
7. `vite-plus-run`

This structure follows user-visible workflows instead of creating one skill
for every `vp` subcommand or one skill for every embedded engine. It keeps the
trigger surface understandable while avoiding duplicated guidance where one
Vite+ command combines several engines.

## Shared Contract

Every skill must:

- Use a kebab-case directory containing `SKILL.md` and `scripts/`.
- Keep `SKILL.md` below 500 lines with only `name` and `description` in YAML
  frontmatter.
- Start the description with `Use when` and name concrete Vite+ triggers.
- Use imperative instructions and current Vite+ command names.
- Treat `vite.config.ts` as the unified project configuration.
- Explain the difference between a built-in command such as `vp test` and a
  project script such as `vp run test` whenever both can plausibly apply.
- Prefer project-local evidence and `vp help <command>` over remembered flags.
- Include a compact quick reference, one strong example, common mistakes, and
  a source-baseline section.
- Include one executable Bash helper using `#!/bin/bash` and `set -e`.
- Send status text to stderr and machine-readable JSON to stdout.
- Avoid network access and repository mutation in helpers; they generate
  snippets or inspect explicitly supplied local paths.
- Reference sibling skills by their exact names only when the workflow crosses
  a skill boundary.

Add one row per skill to the existing "JavaScript / TypeScript — libs & tools"
table in `README.md`. Each description must be derived from the corresponding
frontmatter description and shortened to at most ten words.

## Skill Responsibilities

### `vite-plus`

Own the cross-cutting Vite+ lifecycle:

- Install and verify `vp` without embedding secrets or bypassing project
  package-manager policy.
- Explain the global `vp` CLI versus the local `vite-plus` dependency.
- Cover `vp create`, `vp migrate`, `vp config`, hooks/staged workflows,
  `vp env`, dependency-management commands, `vp toolchain`, and upgrades.
- Show the unified `defineConfig` layout and route detailed work to the six
  specialized skills.
- Preserve existing configuration and scripts during migration, then verify
  with install, check, test, and build commands.

Helper: `scripts/vite-plus-bootstrap.sh` emits an installation/migration
checklist and a minimal unified-config skeleton as JSON.

### `vite-plus-dev-build`

Own application development and production builds:

- Cover `vp dev`, `vp build`, `vp preview`, watch mode, sourcemaps, modes,
  plugins, aliases, server, build, and preview configuration.
- State that Vite+ uses Vite 8 and Rolldown for the documented production
  build path, while standard Vite configuration remains the primary model.
- Distinguish `vp build` from `vp run build` and `vp dev` from `vp run dev`.
- Keep library packaging out of scope and route it to `vite-plus-pack`.

Helper: `scripts/vite-plus-dev-build-bootstrap.sh` emits a minimal application
config and verification command list as JSON.

### `vite-plus-test`

Own the bundled Vitest workflow:

- Cover normal, watch, coverage, filtering, and CI-oriented test execution.
- Record that `vp test` is a normal run by default and `vp test watch` enables
  watch mode.
- Put test configuration in the `test` block of `vite.config.ts` rather than a
  separate `vitest.config.ts` for a Vite+ project.
- Cover Vite+ test import paths and the bundled-version alignment required to
  avoid split Vitest runtime state.
- Reuse `vitest-js` for deep Vitest testing semantics instead of duplicating
  mocking, snapshots, browser mode, and coverage reference material.

Helper: `scripts/vite-plus-test-bootstrap.sh` emits a test config, import
examples, and run/watch/coverage commands as JSON.

### `vite-plus-lint`

Own linting, type-aware analysis, and the composite static-check workflow:

- Cover `vp lint`, autofix, Oxlint rules, plugins, ignore patterns, and
  workspace overrides.
- Explain `typeAware` and `typeCheck`, including the tsgolint/TypeScript Go
  path exposed by Vite+.
- Own `vp check`, including `--fix`, `--no-fmt`, `--no-lint`, and how the
  `check` configuration block changes defaults.
- Keep formatter-specific option reference in `vite-plus-format`.

Helper: `scripts/vite-plus-lint-bootstrap.sh` emits recommended lint/check
configuration and validation commands as JSON.

### `vite-plus-format`

Own formatting through Oxfmt:

- Cover `vp fmt`, check/write modes, ignore patterns, and the `fmt` block.
- Explain why Vite+ projects should not split the configuration into a nested
  `.oxfmtrc.json`.
- Include editor integration that makes format-on-save honor the root Vite+
  configuration.
- Route combined formatting, linting, and type checking to `vite-plus-lint`.

Helper: `scripts/vite-plus-format-bootstrap.sh` emits formatter config, editor
settings, and check/write commands as JSON.

### `vite-plus-pack`

Own library and standalone-artifact packaging:

- Cover `vp pack`, entry points, declarations, output formats, sourcemaps,
  minification, watch mode, and CSS support.
- Use the `pack` block in `vite.config.ts` rather than a separate
  `tsdown.config.ts`.
- Distinguish library packaging from application builds.
- Treat standalone executable support as experimental and verify the active
  Node.js requirement with current docs and `vp env` before use.

Helper: `scripts/vite-plus-pack-bootstrap.sh` emits library and executable
config variants plus verification commands as JSON.

### `vite-plus-run`

Own package scripts, Vite Task, workspaces, scheduling, and caching:

- Cover `vp run`, the `vpr` shorthand, interactive selection, task
  definitions, dependencies, workspace targeting, and cache management.
- Make the built-in-command versus project-script distinction explicit.
- Explain that `package.json` scripts are not cached by default and require
  `--cache`, while configured tasks can opt into richer cache behavior.
- Cover automatic and explicit input/output tracking, environment
  fingerprinting, cache disabling, and safe cache cleanup.

Helper: `scripts/vite-plus-run-bootstrap.sh` emits a task graph configuration
and cache-safe command examples as JSON.

## Error Handling and Safety

- Never install or upgrade Vite+ merely to answer a documentation question.
- Before migration, inspect the workspace root, package manager, lockfiles,
  existing Vite/Vitest/lint/format/task configuration, and dirty Git state.
- Do not delete legacy configuration until equivalent Vite+ behavior is
  demonstrated.
- Do not assume a built-in command invokes a same-named `package.json` script.
- Do not enable unsafe lint or formatting fixes by default.
- Do not claim a cache hit is valid when task inputs or relevant environment
  variables are untracked.
- Do not claim executable packaging works without checking the active runtime
  and current Vite+/tsdown requirements.

## Validation Strategy

Develop and validate one skill at a time.

For each skill:

1. Run a realistic baseline scenario with a fresh agent that does not receive
   the new skill, and record concrete omissions or incorrect choices.
2. Initialize the folder with the skill-creator scaffolding script.
3. Add the minimal `SKILL.md` and helper that address the observed failures.
4. Execute the helper and parse its stdout as JSON.
5. Run the skill-creator `quick_validate.py` validator.
6. Run `bash scripts/lint-skills.sh` and `git diff --check`.
7. Re-run the scenario with the new skill and verify that the observed
   failures are corrected without inventing unsupported guidance.
8. Inspect the diff before moving to the next skill.

After all seven skills:

- Run every helper through Bash and validate every JSON result.
- Run the full repository skill linter.
- Check README completeness and exact skill-name cross-references.
- Compare all command, config, import-path, and version-sensitive claims with
  the current Vite+ primary documentation.
- Commit without adding an AI co-author.
- Ask a second AI coding agent to review accuracy, actionability,
  justification, and conflicts with existing JavaScript/TypeScript skills.
- Address review findings or document why a finding is rejected before the
  work is considered ready to merge.

## Non-Goals

- Reproducing the complete upstream API reference for every embedded engine.
- Creating a separate skill for every `vp` subcommand.
- Replacing the existing `vitest-js` skill.
- Installing Vite+ globally or migrating this repository itself.
- Changing unrelated skills, README rows, repository policy, or CI.
