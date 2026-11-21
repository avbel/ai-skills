---
name: pnpm-js
description: pnpm 12 for single-package projects and monorepos — everyday commands, pnpm-workspace.yaml settings, workspace: and catalog: protocols, --filter selectors, recursive runs and task orchestration, pipeline caching, deploy, CI, security defaults, ERR_PNPM_* troubleshooting. Use for any pnpm command, setting up a monorepo, migrating from npm/Yarn, or fixing a failed install.
---

# pnpm

Baseline is pnpm 12 — a native executable that needs no Node.js to run and downloads the runtimes it needs. pnpm 11 reads the same lockfile, store, and `pnpm-workspace.yaml`; pnpm 10 and older do not (see [troubleshooting](references/troubleshooting.md) for migration).

## Project rules

- Pin pnpm in the root `package.json`: `"packageManager": "pnpm@12.4.1"` (exact) or `devEngines.packageManager` (a range, with `onFail: download`). pnpm switches to the pin on first use; `pnpm self-update 12` updates the binary and the pin together.
- Every project setting lives in `pnpm-workspace.yaml` (camelCase keys), committed with the repo. A `pnpm` field in `package.json` is ignored with a warning. `.npmrc` holds only auth and registry settings.
- Environment variables: `pnpm_config_*` (or `PNPM_CONFIG_*`). pnpm does not read other `npm_config_*` variables (exceptions: `NPM_CONFIG_WORKSPACE_DIR`, `npm_config_userconfig`, and URL-scoped auth tokens).
- Global config is `~/.config/pnpm/config.yaml` on Linux (`$XDG_CONFIG_HOME/pnpm/config.yaml`, `~/Library/Preferences/pnpm/config.yaml` on macOS, `%LOCALAPPDATA%\pnpm\config\config.yaml` on Windows). Project-only settings (`nodeLinker`, `hoistPattern`, `publicHoistPattern`, `shamefullyHoist`, `linkWorkspacePackages`) belong in `pnpm-workspace.yaml` so every machine installs the same layout.
- Run one-off tools with `pnx <pkg>` (alias `pnpm dlx`) — it honors catalogs and the project's security policies. Avoid `npx`/`npm install` in a pnpm repo; guard against them with a `"preinstall": "npx only-allow pnpm"` script (pnpm skips exactly that string).

## Everyday commands

| Command | Use |
|---|---|
| `pnpm add <pkg>` / `-D` / `-O` | Add a (dev / optional) dependency to the project in the current directory |
| `pnpm add -w <pkg>` | Add to the workspace root — fails without `-w` unless `ignoreWorkspaceRootCheck: true` |
| `pnpm add --filter=<pkg> <dep>` | Add into another workspace project |
| `pnpm add <pkg> --save-catalog` | Save the range to the default catalog and `catalog:` to package.json (`--save-catalog-name <n>` picks a named one) |
| `pnpm install` | Sync every project's `package.json` with `node_modules` and the lockfile |
| `pnpm update [--latest] [-r]` | Update in-range (or latest) versions; `-r` across all projects |
| `pnpm remove <pkg>` | Remove from the current project |
| `pnpm run` / `pnpm test` | Run scripts; `pnpm <script>` shorthand works |
| `pnx <pkg>[@ver] [args]` | Run a package without installing it (supports `shx@catalog:` specs) |
| `pnpm why <pkg>` / `pnpm outdated [-r]` | Explain a dependency / list upgrades |
| `pnpm clean` (alias `purge`) | Remove `node_modules` contents across the workspace, respects `--filter` |
| `pnpm ci` | Verify the lockfile is current, then clean + frozen install — for CI |
| `pnpm store prune` | Drop unreferenced store packages and stale metadata; safe to run occasionally |

A script named `clean`/`purge`, `setup`, `deploy`, `rebuild`/`rb`, or `tasks` shadows that built-in — `pnpm <name>` runs the script; `pnpm pm <name>` (e.g. `pnpm pm clean`) runs the built-in regardless.

## Security defaults (check these before debugging a "broken" install)

- Dependency build scripts never run unless allowed. `strictDepBuilds` (on by default) fails the install with `ERR_PNPM_IGNORED_BUILDS`, naming the packages. Approve with `pnpm approve-builds` (interactive; `pnpm approve-builds esbuild fsevents !core-js` for positional approve/deny) or edit `pnpm-workspace.yaml`:

  ```yaml
  allowBuilds:
    esbuild: true
    core-js: false
  ```

  Packages with ignored builds are auto-added with the placeholder `set this to true or false` — decide, don't delete.
- `minimumReleaseAge` defaults to 1440 minutes: a version published less than a day ago is invisible to resolution. A brand-new release "not found" is policy, not an outage — wait, or exclude the package via `minimumReleaseAgeExclude`.
- `blockExoticSubdeps` (on): transitive dependencies on git repos or tarball URLs are rejected.
- Optional hardening: `trustPolicy: no-downgrade` (+ `trustPolicyExclude`, `trustPolicyIgnoreAfter`).
- Commit `pnpm-lock.yaml`. If a vulnerability scanner or SBOM tool reads it, verify it handles the two-document lockfile — see [troubleshooting](references/troubleshooting.md).

## Monorepo layout

`pnpm-workspace.yaml` at the root is the single source of truth:

```yaml
packages:
  - apps/*
  - packages/*
catalog:            # shared version ranges (see Catalogs)
  react: ^19.1.0
tasks:              # script dependency graph (see Task orchestration)
  build:
    dependsOn: ['^build']
    outputs: ['dist/**']
allowBuilds:
  esbuild: true
```

A repo set up for npm/Yarn/Bun with only a `package.json#workspaces` field gets this file generated on the first `pnpm install` (v12.7+); after that only `pnpm-workspace.yaml` is read.

- Link packages with the `workspace:` protocol: `"ui": "workspace:^"`. Plain ranges resolve from the registry — `linkWorkspacePackages` is `false` by default.
- On `pnpm publish`/`pnpm pack`, `workspace:*` becomes the exact version, `workspace:^`/`workspace:~` become the matching range, and `workspace:^1.5.0` stays `^1.5.0`; `catalog:` references are also replaced. A bare `workspace:` is `workspace:*`.
- `sharedWorkspaceLockfile: true` (default) → one `pnpm-lock.yaml` at the root; each project still sees only its declared dependencies.
- `pnpm -r <cmd>` iterates projects: `run`/`exec`/`test`/`add` exclude the root unless `includeWorkspaceRoot: true`; `install`/`update`/`list`/`publish`/… include it.
- Inject workspace packages that need per-consumer peer bindings via `dependenciesMeta.<name>.injected: true` — details in [monorepo reference](references/monorepo.md).

## Catalogs

```yaml
catalog:               # default catalog
  react: ^19.1.0
catalogs:              # named catalogs, opt-in per package
  react18:
    react: ^18.3.1
```

- Reference as `"react": "catalog:"` (default) or `"react": "catalog:react18"` in `dependencies`, `devDependencies`, `peerDependencies`, `optionalDependencies`, and in `overrides`. `pnx shx@catalog:` works too.
- Defining both `catalog` and `catalogs.default` fails. Entries may hold `workspace:` (v12.2+), `file:`, and `link:` specs (v12.6+) — relative paths resolve from the `pnpm-workspace.yaml` directory.
- Upgrade a dependency once in YAML; a catalog change also marks every referencing project as changed for `--filter "[<since>]"`.
- Migrate an existing workspace with `pnx codemod pnpm/catalog`.
- Errors: `ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC` (missing entry), `ERR_PNPM_CATALOG_ENTRY_INVALID_RECURSIVE_DEFINITION` (a catalog entry referencing `catalog:`).

## Filters

| Selector | Selects |
|---|---|
| `foo` | exact name; scope optional, but an ambiguous unscoped name selects nothing |
| `foo...` | `foo` and its dependencies |
| `foo^...` | only `foo`'s dependencies |
| `...foo` | `foo` and its dependents |
| `...^foo` | only `foo`'s dependents |
| `./packages/**` | projects under a directory; combine as `...{packages/**}[origin/main]...` |
| `[origin/main]` | projects changed since the merge base of that ref |
| `!pattern` | exclusion; selectors apply in order, a later one can re-include |

```sh
pnpm --filter "./apps/**" -r run build
pnpm --filter "...[origin/main]" --no-bail test     # CI: test changed + dependents
pnpm --filter='!./legacy/**' --filter "@scope/*" install
```

- `*`/`?` never match a dot-prefixed directory; `**` crosses path segments. Requires Git ≥ 2.24 for `[<since>]`; a catalog bump or a git rename counts as a change.
- Fail on empty selections with `--fail-if-no-match` (or setting `failIfNoMatch: true`).
- `--filter-prod` walks only production dependency edges; `--test-pattern` and `--changed-files-ignore-pattern` refine changed-based selections (settings `testPattern`, `changedFilesIgnorePattern`).

## Recursive runs and task orchestration

`pnpm -r run <script>` schedules a task graph — a task is `<project>#<script>`. Dependencies run first (topological by default), ready tasks run in parallel under `--workspace-concurrency` (default: min(4, CPU cores)).

Declare cross-script relationships in `pnpm-workspace.yaml`:

```yaml
tasks:
  build:
    dependsOn: ['^build']   # after build in each workspace dependency
  test:
    dependsOn: ['build']    # after this project's own build
```

- `^<task>` = that task in the project's workspace dependencies; `<task>` = same project.
- An unconfigured task defaults to `dependsOn: ['^<same>']`; but once a task has any entry, an omitted `dependsOn` means `[]` — declare `^build` explicitly if you add another key.
- A selected project without the script is a pass-through; the chain still connects through it.
- Cap parallelism per task with `concurrency: N`; across processes with `concurrencyGroups: { cargo: 2 }` and order the queue with `priority`. Inspect live groups with `pnpm tasks status`.
- Flags: `--no-bail` (keep running independent tasks after a failure; exit code still non-zero), `--resume-from <pkg>` (skip tasks that already passed), `--reverse`, `--parallel` (= `--no-sort`, ignores `tasks`), `--report-summary`, `--stream` / `--aggregate-output`.
- Inspect the graph without running it: `pnpm -r run --dry-run --json build`.
- A cycle in the task graph fails before anything runs: `ERR_PNPM_TASK_CYCLE`. Fix the graph; only deliberate cycles get `ignoreWorkspaceCycles: true` (or make cycles fail the install with `disallowWorkspaceCycles: true`).

## pnpm pipeline (v12.4+, experimental)

```yaml
pipelines:
  default: [build, test, lint]
  release: [build]
```

`pnpm pipeline` runs like a CI job: frozen install → select projects affected since `pipelineBase` (default `origin/main`) → task graph → restore cached results instead of re-running. A task is cacheable when it declares `outputs` (`outputs: []` asserts "no files", which makes lint/test cacheable); the cache key covers script text, dependency tasks, the lockfile, and the runtime — tune with `inputs` and `env`; opt out with `cache: false`. Use `--full` to ignore the affected selection, `--base <ref>` to move it, `--no-cache`, `--dry-run` / `--json` to inspect. A remote cache server (Turborepo Remote Cache API) can be attached via `remoteCache` — see [monorepo reference](references/monorepo.md).

## Deploying one app

```sh
pnpm --filter=web --prod deploy out/web
```

Copies the files `pnpm pack` would include plus an isolated, self-contained `node_modules`; workspace links are rewritten to `file:` dependencies in a dedicated deploy lockfile (no `injectWorkspacePackages` needed since v12.2). `--force` allows a non-empty target; `--offline` works from a pre-populated store. Docker: run the deploy in a builder stage and `COPY --from` the output into the runtime image — any Dockerfile that runs `pnpm install` must `COPY pnpm-workspace.yaml` first (pnpm 11+).

## CI

- GitHub Actions: use the `pnpm/setup` action — it reads the `packageManager` pin, installs the runtime, runs install, and with `cache: true` caches the store. (This supersedes `pnpm/action-setup` recipes pinned to pnpm 9.)
- Other systems: `curl -fsSL https://get.pnpm.io/ | sh -` installs a self-contained pnpm that follows the project pin; export `PNPM_HOME` and put `$PNPM_HOME/bin` on `PATH`. Container jobs can start from `ghcr.io/pnpm/pnpm`.
- pnpm switches to frozen-lockfile automatically when it detects CI; `pnpm ci` adds a clean first. A lockfile written by a newer pnpm major errors instead of being silently rewritten.
- Cache the store (`pnpm store path`) and the metadata cache (`pnpm cache path`) — the metadata cache also skips re-checking an unchanged lockfile against supply-chain policies. Never let untrusted jobs write a store or cache that trusted jobs restore.
- `pnpm setup`, `pnpm self-update`, and `pnpm add -g` fail under `sudo` (`ERR_PNPM_SUDO_NOT_SUPPORTED`) — run as the CI user.

## Node versions

- Global: `pnpm runtime set node 24 -g` (also `lts`, `latest`, `rc`, codenames; supports `deno` and `bun`).
- Project: `pnpm runtime set node 22` saves `node@runtime:22` under `devEngines.runtime` (`--save-prod` → `engines.runtime`); then `pnpm shim add node` makes the bare `node` command use it. A globally installed `node` runs the version the current project pins.
- Runtime installs do not bundle `npm`, `npx`, or corepack — `pnpm add -g npm` if you need npm itself.

## When it breaks

| Error | Fix |
|---|---|
| `ERR_PNPM_OUTDATED_LOCKFILE` | a `package.json` changed without installing — `pnpm install`, commit the lockfile |
| `ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE` | pinned pnpm or `configDependencies` changed — run `pnpm install` and commit |
| `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH` | a recorded setting (`overrides`, `catalogs`, `patchedDependencies`, …) differs — `pnpm install`, commit |
| `ERR_PNPM_IGNORED_BUILDS` | `pnpm approve-builds`, or set `strictDepBuilds: false` |
| `ERR_PNPM_WORKSPACE_PKG_NOT_FOUND` | `workspace:` name matches no project — check `packages:` globs and spelling |
| `ERR_PNPM_NO_MATCHING_VERSION_INSIDE_WORKSPACE` | a `workspace:` range matches no version — align versions or `pnpm -r update` |
| `ERR_PNPM_TASK_CYCLE` | fix the `tasks` graph, or `ignoreWorkspaceCycles: true` if deliberate |
| `ERR_PNPM_UNEXPECTED_STORE`, `ERR_PNPM_HOIST_PATTERN_DIFF`, `ERR_PNPM_NODE_LINKER_DIFF`, `ERR_PNPM_PUBLIC_HOIST_PATTERN_DIFF` | the modules dir was installed with other settings — rerun `pnpm install` |
| `ERR_PNPM_TARBALL_INTEGRITY` | stale metadata for a re-published version — `pnpm store prune`, retry |
| `ERR_PNPM_UNSUPPORTED_ENGINE` | wrong Node/pnpm version for `engines`/`engines.pnpm` |

All codes, npm→pnpm migration, and the v10→v11→v12 changes: [troubleshooting](references/troubleshooting.md). Injected dependencies, publish flow, and pipeline details: [monorepo reference](references/monorepo.md).

For general JavaScript/TypeScript conventions use `js-conventions`; for Node.js 26 runtime features see `nodejs-26`.
