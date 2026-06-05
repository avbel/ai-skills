---
name: github-actions-ci
description: Build-CI recipes for GitHub Actions — install pinned Node/pnpm and Rust toolchains, build and push Docker images, make workflows manually runnable (workflow_dispatch), cache node/rust/docker layers, and validate workflow files. Use when writing or reviewing .github/workflows/*.yml for pnpm, Rust, or Docker projects.
---

# Build CI with GitHub Actions

Opinionated, copy-paste recipes for the parts of CI that are easy to get
subtly wrong: pinning toolchains, ordering setup steps so caching actually
works, building Docker images with layer reuse, exposing a manual trigger, and
validating the YAML before it ever runs.

Snippets below are deliberately minimal. For one complete workflow that wires
Node + Rust + Docker together, copy [`reference/ci.yml`](reference/ci.yml).

## Cross-cutting defaults (every workflow)

Bake these into the top of every workflow file, not as an afterthought:

```yaml
permissions:
  contents: read          # GITHUB_TOKEN is read-write by default — clamp it
```

```yaml
- uses: actions/checkout@v4
  with:
    persist-credentials: false   # don't leave the token in .git/config for later steps
```

Grant more only where a single job needs it (e.g. the Docker job adds
`packages: write` to push to ghcr.io — shown below). Also worth considering,
though not required: a `concurrency` group with `cancel-in-progress: true` to
kill stale runs, and `timeout-minutes` per job so a hung step can't burn the
6-hour default.

### Pin actions for production

Samples here use readable major tags (`actions/checkout@v4`). A tag is mutable —
the owner can repoint it. For anything beyond a personal repo, **pin to a full
commit SHA** and let Dependabot bump it:

```yaml
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
```

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
```

First-party `actions/*` are lower risk; third-party actions (`pnpm/*`,
`docker/*`, `Swatinem/*`, `dtolnay/*`) are the ones a SHA pin most protects.

## Node + pnpm

Install order matters: **pnpm must exist before `setup-node`**, because
`cache: pnpm` shells out to `pnpm store path` to locate the cache. Reverse the
order and the cache step fails. Keep versions in repo files (`.nvmrc` and the
`packageManager` field of `package.json`) so the workflow stays version-agnostic.

```yaml
# package.json → "packageManager": "pnpm@9.x.x"
# .nvmrc       → 24

steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false

  - uses: pnpm/action-setup@v4   # reads the version from packageManager

  - uses: actions/setup-node@v4
    with:
      node-version-file: .nvmrc
      cache: pnpm                 # caches the pnpm content-addressable store

  - run: pnpm install --frozen-lockfile
  - run: pnpm lint
  - run: pnpm test
```

- `--frozen-lockfile` fails the build if `pnpm-lock.yaml` is out of date —
  exactly what you want in CI; never let CI silently resolve a different tree.
- `cache: pnpm` keys on `pnpm-lock.yaml`, so the cache invalidates only when
  dependencies actually change.

## Rust

`dtolnay/rust-toolchain` installs the toolchain (and honours
`rust-toolchain.toml` for channel, components, and targets);
`Swatinem/rust-cache` handles caching — it keys on `Cargo.lock` and the
toolchain, and deliberately caches dependencies but not your own crates.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      persist-credentials: false

  - uses: dtolnay/rust-toolchain@stable
    with:
      components: clippy, rustfmt

  - uses: Swatinem/rust-cache@v2   # place AFTER the toolchain step

  - run: cargo fmt --all --check
  - run: cargo clippy --all-targets --all-features -- -D warnings
  - run: cargo test --all-features
```

- The `@stable` in `dtolnay/rust-toolchain@stable` is the **toolchain channel**,
  not an action version. Pin a specific toolchain with
  `dtolnay/rust-toolchain@1.85.0`, or drop a `rust-toolchain.toml` in the repo
  and use `@stable` as a harmless default.
- `Swatinem/rust-cache` must come *after* the toolchain action so its cache key
  includes the resolved compiler version.
- An all-in-one alternative is `actions-rust-lang/setup-rust-toolchain@v1`, which
  bundles toolchain install and the same caching in one step.

## Docker image build (and push to ghcr.io)

Use Buildx + `build-push-action` with the GitHub-native layer cache
(`type=gha`). Push to GitHub Container Registry using the built-in
`GITHUB_TOKEN` — no extra secret needed. The `metadata-action` generates sane
tags and labels from the git ref.

```yaml
docker:
  runs-on: ubuntu-latest
  permissions:
    contents: read
    packages: write           # required to push to ghcr.io
  steps:
    - uses: actions/checkout@v4
      with:
        persist-credentials: false

    - uses: docker/setup-buildx-action@v3

    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - id: meta
      uses: docker/metadata-action@v5
      with:
        # metadata-action lowercases the image name, so an uppercase
        # org/repo (MyOrg/MyRepo) works without a manual `tr` step.
        images: ghcr.io/${{ github.repository }}

    - uses: docker/build-push-action@v6
      with:
        context: .
        push: ${{ github.event_name != 'pull_request' }}  # build on PRs, push elsewhere
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

- `mode=max` caches **all** layers (including intermediate build stages), not
  just the final image — far better hit rate for multi-stage Dockerfiles.
- `push: ${{ github.event_name != 'pull_request' }}` builds (and caches) on PRs
  for validation but only publishes on push/dispatch.
- **Build-only** variant: set `push: false` and `load: true` to load the image
  into the runner's Docker for testing. **Cross-runner / large images**: swap
  the cache backend to
  `type=registry,ref=ghcr.io/${{ github.repository }}:buildcache,mode=max`.
- Multi-arch (`platforms: linux/amd64,linux/arm64`) needs
  `docker/setup-qemu-action@v3` before Buildx.

## Manual runs (workflow_dispatch)

Add `workflow_dispatch` alongside the automatic triggers so the **same**
workflow runs on push/PR and on demand from the Actions tab (or `gh workflow
run`). Inputs are typed — `boolean`, `choice`, and `environment` render as
proper form controls.

```yaml
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
    inputs:
      environment:
        description: Target environment
        type: environment        # dropdown of repo environments
      release:
        description: Publish artifacts
        type: boolean
        default: false
      log_level:
        type: choice
        options: [info, debug, trace]
        default: info
```

Read inputs with `${{ inputs.<name> }}`; they're empty when the workflow was
triggered by push/PR, so branch on the event:

```yaml
- if: github.event_name == 'workflow_dispatch' && inputs.release
  run: ./publish.sh --log ${{ inputs.log_level }}
```

Trigger from the CLI:

```bash
gh workflow run ci.yml -f environment=staging -f release=true
```

## Caching cheat-sheet

| Ecosystem | Mechanism | Keyed on |
|-----------|-----------|----------|
| Node / pnpm | `cache: pnpm` on `setup-node` | `pnpm-lock.yaml` |
| Rust | `Swatinem/rust-cache@v2` | `Cargo.lock` + toolchain |
| Docker | `cache-from/to: type=gha` on `build-push-action` | layer digests |

Three things that silently kill cache hits:

- **Wrong step order** — pnpm after `setup-node`, or `rust-cache` before the
  toolchain. The cache key is computed from state that doesn't exist yet.
- **`actions/cache` GC** — the GitHub Actions cache has a **10 GB per-repo**
  limit and evicts least-recently-used entries; a fat Docker `type=gha` cache
  can evict your pnpm/cargo caches. Watch total size if hit rates drop.
- **Branch scoping** — caches are restored from the current branch and its base
  branch only. A PR can't read a sibling feature branch's cache; `main` warms
  the shared baseline.

## Validating workflows

Validate **before** pushing — a typo in an `if:` expression or a shell-injection
sink only surfaces at runtime otherwise.

| Tool | Catches |
|------|---------|
| [`actionlint`](https://github.com/rhysd/actionlint) | YAML/syntax errors, bad `${{ }}` expressions, undefined `needs`/`matrix` refs, shellcheck on `run:` blocks |
| [`zizmor`](https://github.com/woodruffw/zizmor) | security issues — injection via untrusted `${{ github.event.* }}`, over-broad `permissions`, unpinned/dangerous actions |
| [`act`](https://github.com/nektos/act) | runs jobs locally in Docker; `act --list` confirms the workflow even parses into jobs |

Run all three over `.github/workflows` with the bundled script:

```bash
bash /mnt/skills/user/github-actions-ci/scripts/validate-workflows.sh [path-to-repo]
```

It runs `actionlint` and `zizmor` (fetching them on demand — preferring
`go install` over a pinned download, never a live `curl | bash`) and lists `act`
jobs when `act` is available. Set `GA_CI_NO_AUTOINSTALL=1` to require both tools
pre-installed. Exit code is non-zero if any check fails — wire it into a
pre-commit hook or a CI job of its own.

> zizmor reports an `unpinned-uses` finding for every major-tag action (like the
> samples here). That's not a false positive — it's the same SHA-pinning advice
> from the [pin actions](#pin-actions-for-production) section. Pin to commit
> SHAs to clear it.

Manual equivalents:

```bash
actionlint
zizmor .github/workflows/
act --list
```

## Anti-patterns

- **No `permissions:` block** → workflow runs with a read-write token; a
  compromised dependency can push commits or packages. Always clamp to
  `contents: read` and widen per job.
- **Interpolating untrusted input into `run:`** —
  `run: echo "${{ github.event.pull_request.title }}"` is a shell-injection
  sink. Pass it through `env:` and reference `"$TITLE"` instead. (zizmor flags
  this.)
- **`npm install` / unpinned `pnpm install`** in CI → non-reproducible builds.
  Use `--frozen-lockfile`.
- **Caching the cargo `target/` of your own crate** — `Swatinem/rust-cache`
  intentionally skips it; restoring stale local artifacts causes confusing
  incremental-compilation bugs. Don't roll your own `actions/cache` for it.
- **`latest` toolchains** — `node-version: latest` or `rust-toolchain@master`
  makes CI fail on an upstream release you didn't choose. Pin via `.nvmrc` /
  `rust-toolchain.toml`.

## Installation

```bash
# Claude Code
cp -r skills/github-actions-ci ~/.claude/skills/
```

For claude.ai, paste this `SKILL.md` into project knowledge. The validation
script needs `actionlint`, `zizmor`, and optionally `act` available (or a
network connection to fetch the first two on demand).
