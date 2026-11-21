# Troubleshooting and migration

## Error codes

pnpm errors carry `ERR_PNPM_*` codes; match the code, not the message. Codes not listed here explain themselves.

| Code | Cause | Fix |
|---|---|---|
| `ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE` | the boot document (pinned pnpm / `configDependencies`) is stale | `pnpm install` without `--frozen-lockfile`, commit |
| `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH` | a lockfile-recorded setting differs: `overrides`, `patchedDependencies`, `catalogs`, `packageExtensions` checksum, pnpmfile checksum, resolution settings (e.g. `autoInstallPeers`) | `pnpm install`, commit; don't hand-edit the lockfile |
| `ERR_PNPM_OUTDATED_LOCKFILE` | manifest changed without a lockfile update (typical in CI) | `pnpm install`, commit |
| `ERR_PNPM_IGNORED_BUILDS` | `strictDepBuilds` blocked a dependency's build scripts | `pnpm approve-builds` or edit `allowBuilds` |
| `ERR_PNPM_HOIST_PATTERN_DIFF` / `ERR_PNPM_PUBLIC_HOIST_PATTERN_DIFF` / `ERR_PNPM_NODE_LINKER_DIFF` / `ERR_PNPM_VIRTUAL_STORE_DIR_MAX_LENGTH_DIFF` | modules dir was installed with different layout settings | rerun `pnpm install` |
| `ERR_PNPM_NO_MATCHING_VERSION_INSIDE_WORKSPACE` | a `workspace:` semver range matches no local version | align versions or `pnpm -r update` |
| `ERR_PNPM_WORKSPACE_PKG_NOT_FOUND` | `workspace:` name matches no project | check the `packages:` globs and spelling |
| `ERR_PNPM_TASK_CYCLE` | task graph has a cycle | fix `tasks`; `ignoreWorkspaceCycles: true` only if deliberate |
| `ERR_PNPM_UNEXPECTED_STORE` | modules dir is linked to a different store dir | rerun `pnpm install` |
| `ERR_PNPM_TARBALL_INTEGRITY` | tarball doesn't match lockfile integrity — corrupted lockfile merge, or a registry that re-publishes versions | `pnpm store prune` to drop stale metadata, verify the tarball URL |
| `ERR_PNPM_UNSUPPORTED_ENGINE` | `engines.pnpm` always enforced; `engines.node` only with `engineStrict` (which in v12 also fails through regular dependency edges) | switch runtime, or relax `engineStrict` |
| `ERR_PNPM_PEER_DEP_ISSUES` | unresolved peers with `strictPeerDependencies` | install the missing peers, or scope exceptions with `peerDependencyRules.ignoreMissing` / `.allowedVersions` |
| `ERR_PNPM_INVALID_NODE_VERSION` | `nodeVersion` setting is not an exact semver | write e.g. `nodeVersion: 22.22.3` |
| `ERR_PNPM_NO_OFFLINE_META` | `--offline` without cached metadata for a package | run once without `--offline`, or use `--prefer-offline` |
| `ERR_PNPM_REGISTRY_NAME_MISMATCH` | registry answered with a different package's metadata | check the registry/scope config and any proxy |
| `ERR_PNPM_APPROVE_BUILDS_NON_INTERACTIVE` | `pnpm approve-builds` needs a TTY in CI | pass package names or `--all` |
| `ERR_PNPM_SUDO_NOT_SUPPORTED` | global commands under `sudo` | run as the CI user |
| `ERR_PNPM_DEPLOY_DIR_NOT_EMPTY` | deploy target exists | `--force`, or a fresh directory |
| `ERR_PNPM_DEPLOY_AMBIGUOUS_PEER` | deploy can't bind a peer uniquely | pin the peer with `overrides`, or enable `injectWorkspacePackages` |
| `ERR_PNPM_UNRECOGNIZED_WORKSPACE_SETTINGS` | v12 rejects unknown `pnpm-workspace.yaml` keys (error when the pinned version is satisfied) | remove the key or fix its spelling |

## The two-document lockfile

`pnpm-lock.yaml` may hold **two** YAML documents separated by `---`:

- **Boot document** (first, only when present): `configDependencies`, the resolved pnpm version under `packageManagerDependencies`, and their package entries. Written when the project has config dependencies or pins pnpm 12+ via `packageManager`/`devEngines.packageManager` (unless `pmOnFail: ignore`).
- **Project document** (last, always): `importers`, `packages`, `snapshots`, plus a `settings` block recording resolution-affecting settings.

Consequences:

- A tool that parses only one document silently reports the wrong graph — single-document YAML loaders return the boot document (which looks valid but describes an empty project). Dependency-graph tools: take the **last** document. Scanners/SBOM: union **every** document.
- Since v12, `packages:` entries may carry a `revision` field (registry-replaced tarballs); treat it as metadata, `integrity` stays standard SRI.
- `pnpm audit` handles both shapes natively — prefer it over external lockfile scanners.

## Store operations

- `pnpm store path` — active store dir; `pnpm store status` — verify installed files are unmodified (`ERR_PNPM_MODIFIED_DEPENDENCY` otherwise); `pnpm store prune` — remove unreferenced packages + metadata cache (safe; re-downloads on demand); `pnpm store add ./tarballs` — prefill for `pnpm install --offline --frozen-lockfile`.
- Every install registers the project in `$(pnpm store path)/projects` (symlinks) — useful to see what shares a store.
- Change `storeDir` deliberately? Expect `ERR_PNPM_UNEXPECTED_STORE` once; `pnpm install` relinks.

## Migrating from npm / Yarn / Bun

1. `pnpm import` — generates `pnpm-lock.yaml` from `yarn.lock`, `package-lock.json`, or `npm-shrinkwrap.json` (checked in that order).
2. `pnpm install`, verify the lockfile diff, then delete the old lockfile.
3. `pnpm clean` (purge `node_modules`) before the first install if the layout was hoisted.
4. Pin pnpm: `"packageManager": "pnpm@12.x.y"` in the root `package.json`.
5. Guard the repo: `"preinstall": "npx only-allow pnpm"` (pnpm skips that exact script).
6. If the repo used `package.json#workspaces`, the first `pnpm install` creates `pnpm-workspace.yaml` (v12.7+); move other `pnpm`-specific config into it — see below.

## Moving pnpm 10 → 11/12

Run the codemod: `pnx codemod run pnpm-v10-to-v11` (applies to v12 too). It moves `package.json#pnpm` settings and non-auth `.npmrc` settings into `pnpm-workspace.yaml` (camelCase), merges `onlyBuiltDependencies`-family settings into `allowBuilds`, collapses package-manager strictness into `pmOnFail`, renames `allowNonAppliedPatches` → `allowUnusedPatches` and `auditConfig.ignoreCves` → `auditConfig.ignoreGhsas`, and converts `useNodeVersion` into `devEngines.runtime`.

Manual follow-ups the codemod cannot do:

- Rename `npm_config_*` variables to `pnpm_config_*` in CI configs, shell profiles, Docker images.
- Convert CVE IDs to GHSA IDs for `auditConfig.ignoreGhsas`.
- Dockerfiles: `COPY pnpm-workspace.yaml` before `pnpm install`.
- `pnpm link <name>` no longer resolves from the global store — use a path (`pnpm link ./foo`).
- `pnpm install -g` with no arguments is gone — use `pnpm add -g <pkg>`.
- `pnpm server` removed; `importPackage`/`filterLog` pnpmfile hooks no longer run.
- Script names can now shadow built-in commands (`clean`, `deploy`, …) — use `pnpm pm <name>`.

## v11 → v12 behavior changes to watch

- Unknown `pnpm-workspace.yaml` settings fail (`ERR_PNPM_UNRECOGNIZED_WORKSPACE_SETTINGS`) when the pin is satisfied — fix spelling.
- Boolean flags need `--frozen-lockfile=false` or `--no-frozen-lockfile`; `--frozen-lockfile false` is rejected.
- Git-hosted deps always resolve over HTTPS; SSH URLs are never recorded — configure Git itself for private SSH fetches.
- `engineStrict` fails installs reached through regular dependency edges, even under an `optionalDependencies` subtree.
- Global Node follows the project's pin (`devEngines.runtime`, `.nvmrc`, `.node-version`); opt out with `globalShims: false`.
- Global commands under `sudo` fail (`ERR_PNPM_SUDO_NOT_SUPPORTED`).
- `pnpm dlx`/`pnx` keep a per-entry virtual store instead of the global one.
- Linux `packageImportMethod: auto` prefers hard links; use `clone` on CoW filesystems like btrfs.
