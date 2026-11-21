# Monorepo reference

Details behind the SKILL.md monorepo sections. All settings below go in the root `pnpm-workspace.yaml`.

## Worked example

```text
repo/
├── pnpm-workspace.yaml
├── package.json          # root: devDeps for shared tooling, pinned packageManager
├── apps/
│   ├── web/              # name: web,        deps: @repo/ui workspace:^
│   └── api/              # name: @repo/api,  deps: @repo/db workspace:^
└── packages/
    ├── ui/               # name: @repo/ui
    └── db/               # name: @repo/db
```

```yaml title="pnpm-workspace.yaml"
packages:
  - apps/*
  - packages/*
catalog:
  react: ^19.1.0
  '@repo/ui': workspace:^
tasks:
  build:
    dependsOn: ['^build']
    outputs: ['dist/**']
  test:
    dependsOn: ['build']
    outputs: []
allowBuilds:
  esbuild: true
```

## workspace: protocol

| Declaration | Links | Publishes as |
|---|---|---|
| `"foo": "workspace:*"` | foo@any | the exact version present at publish time |
| `"foo": "workspace:^"` / `"workspace:~"` | foo@any | `^x.y.z` / `~x.y.z` of that version |
| `"foo": "workspace:^1.5.0"` | foo@1.5.x only | `^1.5.0` |
| `"foo": "workspace:../foo"` | relative-path project | the converted regular spec |
| `"bar": "workspace:foo@*"` | aliased link | `"bar": "npm:foo@<version>"` |

- Only `workspace:` guarantees a local link. `linkWorkspacePackages: true` also links plain ranges that match a local project (uncertainty: a non-matching registry version installs silently); `deep` extends linking into subdependencies. Prefer the protocol, leave the setting `false`.
- `saveWorkspaceProtocol: rolling` (default) makes `pnpm add foo` inside the workspace save a rolling spec — `workspace:*` with the default empty `savePrefix`, or `workspace:^`/`workspace:~` when `savePrefix` is `^`/`~` (`true` saves pinned specs like `workspace:^1.2.3`, `false` saves plain ranges — don't).
- `preferWorkspacePackages: true` prefers local packages even when the registry has a newer version.

## Injected dependencies (per-consumer peer bindings)

Symlinked workspace deps share one peer context; inject a package when different consumers must bind different peers (e.g. React 16 vs 17):

```json title="apps/web/package.json"
{
  "dependencies": { "ui": "workspace:^", "react": "16" },
  "dependenciesMeta": { "ui": { "injected": true } }
}
```

- Inject = hard-linked copy in the virtual store, so edits to the source are NOT visible until synced. `pnpm install` re-syncs; `syncInjectedDepsAfterScripts: [build]` re-syncs copies whenever the listed script runs in the package (watch-mode friendly). Workspace-wide: `injectWorkspacePackages: true`; `dedupeInjectedDeps: true` (default) symlinks where peers already match.
- Injected peers bind to what the consuming chain provides; `pnpm deploy` preserves those bindings.

## Catalogs

- `catalog:` is the default catalog; `catalogs:<name>` defines named ones; reference with `catalog:` or `catalog:<name>`. Usable in all dependency fields, `overrides`, and `pnx` specs.
- `catalogMode` makes `pnpm add` write to the default catalog without `--save-catalog`.
- Entries accept `workspace:` (v12.2+), `file:`, `link:`, and bare relative paths (v12.6+), resolved from the workspace root.
- A catalog entry itself referencing `catalog:` is invalid (`ERR_PNPM_CATALOG_ENTRY_INVALID_RECURSIVE_DEFINITION`).
- On publish, `catalog:` is replaced with the resolved range, so published packages stay usable by any package manager.

## Filter cookbook

```sh
pnpm --filter web... test                    # web + everything it uses
pnpm --filter "...^@repo/ui" build           # everything that consumes ui
pnpm --filter "./apps/**" run build           # directory-based
pnpm --filter "...[origin/main]" test        # changed + dependents (merge-base since v12.7)
pnpm --filter "[origin/main]" --changed-files-ignore-pattern="**/*.md" lint
pnpm --filter "...[origin/main]" --test-pattern="test/*" test   # dep tests skipped when only test files changed
pnpm --filter=!web --filter "@repo/*" build   # order matters: later selectors re-include
```

- In zsh escape `!` as `\!` or single-quote the pattern.
- `{<dir>}` globs: `{packages/*}` matches one level, `{packages/**}` deeper; `legacyDirFiltering: true` restores "whole subtree" matching.
- `--filter-prod` selects via production edges only.
- `pnpm install --filter web...` installs only the deps of matching projects.

## Task orchestration details

- Defaults: recursive `run`/`exec`/`test` sort topologically; `--no-sort` and `--parallel` disable ordering (and ignore `tasks`); `--bail` (default) stops dispatch and SIGTERMs running tasks (SIGKILL 2 s later).
- `--resume-from <pkg>`: pnpm persists which tasks passed for the same invocation signature (selection, command, args, settings, script bodies). A matching record skips exactly those tasks; without one it assumes the resume point's transitive dependencies already ran.
- Output: inherited only when at most one task can run at a time; otherwise use `--stream` (live prefixed) or `--aggregate-output` (per-task after completion).
- `concurrencyGroups` slots are machine-wide across pnpm processes sharing the same `stateDir`; a nested `pnpm run` in the same group reuses its parent's slot. `pnpm tasks status` lists running/waiting tasks (use `pnpm pm tasks status` if a project defines a `tasks` script).
- Install/rebuild/pack/publish/stage also schedule on the workspace dependency graph — an unrelated project never waits for a full topological group.
- `ignoreWorkspaceCycles: true` downgrades `ERR_PNPM_TASK_CYCLE` to a warning (unordered within the cycle); `disallowWorkspaceCycles: true` fails installs with cyclic workspace deps.

## pnpm pipeline details

- Selection: projects affected since `pipelineBase` (default `origin/main`) plus their dependents; root excluded unless `includeWorkspaceRoot: true`. Override with `--base <ref>` or `--full`.
- Cache keys: script text, dependency tasks' keys, the lockfile, the runtime, plus declared `inputs` (default: all tracked files; `+glob` adds untracked/workspace paths, `!glob` excludes) and `env` variable names (values hashed, never stored). A task depending on an uncacheable task always runs.
- `outputs: []` is the positive statement "produces no files" — required to cache test/lint. A task with no `outputs` key never caches.
- Remote cache: set `remoteCache` to a Turborepo Remote Cache API server (Vercel Remote Cache or a pnpr server); publish from CI with `PNPM_REMOTE_CACHE_PRIVATE_KEY` / `PNPM_REMOTE_CACHE_PUBLISH=true`; restore only results signed by a key in `trustedKeys`. Limits: ≤10,000 files, ≤4 GiB each, ≤16 GiB total. Unreachable server = cache miss, never a failure.
- Cargo tasks: `cargoTargetDir: target` restores an immutable snapshot of previous build state across runs and worktrees instead of caching outputs.
- Every run writes a summary + event stream under `<cacheDir>/pipeline/<workspace-hash>`; `--report` ships it to the `pnprServer`.

## Deploy details

- `pnpm --filter=<name> [--prod|--dev] deploy <dir>` — the filter must select exactly one project (`ERR_PNPM_NOTHING_TO_DEPLOY` / `ERR_PNPM_CANNOT_DEPLOY_MANY`); the workspace root is an invalid target (`ERR_PNPM_INVALID_DEPLOY_TARGET`).
- Files copied = what `pnpm pack` includes (`files` field → `.npmignore` → `.gitignore`; `deployAllFiles: true` for everything).
- The deployed `package.json` drops `packageManager`/`devEngines.packageManager`; `prepare` is not run; a project with `publishConfig.directory` installs from that directory.
- Reproducible deploys: set `SOURCE_DATE_EPOCH` (v12.15+) so repeated deploys produce identical files and Docker layers stay cached.
- `pnpm deploy --offline` with a store populated by `pnpm store add ./tarballs` or `pnpm fetch`; `--trust-lockfile` skips supply-chain policy checks on locked versions.

```dockerfile
FROM workspace AS pruned
RUN pnpm --filter web --prod deploy pruned

FROM node:24-alpine
WORKDIR /app
COPY --from=pruned /app/pruned .
ENTRYPOINT ["node", "index.js"]
```

## Versioning and release

- `pnpm version -r` bumps all workspace packages; [`pnpm change`](https://pnpm.io/cli/change) records changesets-style releases for workspace packages. Changesets and Rush also work with pnpm.
- `pnpm publish` / `pnpm pack` rewrite `workspace:` and `catalog:` ranges (tables above) — no intermediate publish steps needed; consumers get normal semver ranges.
- `pnpm -r publish` publishes every workspace package; useful flags: `--no-git-checks`, `--publish-branch`, `--access`, `--tag`, `--dry-run`, `--report-summary`.
