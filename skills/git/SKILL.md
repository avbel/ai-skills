---
name: git
description: "Use when working with Git repositories: authentication, branching, merge conflicts, rebase, history cleanup, executable bits, large files, and repository performance."
---

# Git

Use these conventions for source-control work with Git. Prefer small, explicit
steps that preserve user work and make history intent easy to audit.

## Source Baseline

- Pro Git book: <https://git-scm.com/book/en/v2>.
- Client credential storage: <https://git-scm.com/book/en/v2/Git-Tools-Credential-Storage>
  and <https://git-scm.com/docs/gitcredentials>.
- GitHub CLI authentication: <https://cli.github.com/manual/gh_auth_login>
  and <https://cli.github.com/manual/gh_auth_setup-git>.
- Git Credential Manager:
  <https://github.com/git-ecosystem/git-credential-manager>.
- Branching, merging, and rebase: Git book chapters 3.2 and 3.6.
- Conflict tools: Git book chapters 7.8 and 7.9.
- History rewriting and cleanup: Git book chapters 7.6, 7.7, and 10.7.
- Executable bits: <https://git-scm.com/docs/git-add> and
  <https://git-scm.com/docs/git-update-index>.
- Maintenance: <https://git-scm.com/docs/git-maintenance>.
- Large files: <https://git-lfs.com/>.
- Private-data removal pattern:
  <https://github.com/avbel/git-private-data-remover>.

Before relying on a flag, check local support with `git --version` and
`git help <command>`. Prefer the newer `git switch` and `git restore` commands
for human workflows, but use older equivalents when the local Git version or
project docs require them.

Scope: local/client Git usage only.

## First Look

Run a quick read-only inspection before changing anything:

```sh
git status --short --branch
git branch --show-current
git remote -v
git log --oneline --decorate --graph --all -20
git diff --stat
git diff --cached --stat
```

- Treat uncommitted changes as user work unless the user says otherwise.
- Do not run `reset --hard`, `clean -fd`, force-push, history rewrite, or file
  deletion without explicit intent and a recovery path.
- Use `--` before paths that may look like flags:
  `git restore --staged -- --odd-name`.

## Authentication and Credentials

Prefer secure, client-side credential flows. Do not put tokens in commands,
commits, shell history, `.gitconfig`, or remotes.

For GitHub, the GitHub CLI is usually the easiest HTTPS or SSH setup:

```sh
gh auth login --git-protocol https
gh auth status
gh auth setup-git
```

For SSH through GitHub CLI:

```sh
gh auth login --git-protocol ssh
gh auth setup-git
```

- `gh auth login` uses a browser flow by default and stores the token in the
  system credential store when available.
- Use `gh auth status` to verify the account, host, token scopes, and storage
  location.
- Use `GH_TOKEN` or `GH_ENTERPRISE_TOKEN` for automation instead of interactive
  prompts or hard-coded tokens.
- `gh auth setup-git` configures Git to use GitHub CLI as the credential helper
  for authenticated GitHub hosts.

For general HTTPS remotes, prefer Git Credential Manager when available:

```sh
git config --global credential.helper manager
git config --global --get credential.helper
```

- Git Credential Manager is cross-platform and supports browser/OAuth-style
  flows for major hosts over HTTPS.
- On macOS, `osxkeychain` is also common:
  `git config --global credential.helper osxkeychain`.
- On Linux, use Git Credential Manager or a secure helper such as `libsecret`
  when installed.
- `credential.helper cache` stores credentials in memory for a limited time.
- `credential.helper store` writes plain-text credentials to disk; avoid it
  unless the user deliberately accepts that risk.

For host-specific usernames, prefer an explicit credential context:

```ini
[credential "https://github.com"]
    username = USERNAME
```

To forget a cached HTTPS credential and re-authenticate:

```sh
printf 'protocol=https\nhost=github.com\n\n' | git credential reject
gh auth logout --hostname github.com
gh auth login
```

For SSH remotes, verify client keys and agent state:

```sh
ssh -T git@github.com
ssh-add -l
```

- HTTPS authentication uses credential helpers; SSH authentication uses SSH keys
  and `ssh-agent`.
- Keep remote URLs intentional: `git remote -v` should show either HTTPS or SSH
  based on the team's preferred auth mode.

## Everyday Branching

```sh
git fetch origin
git switch -c feature/topic origin/main
git status --short --branch
git add -p
git commit -m "Short imperative summary"
```

- Create topic branches from an up-to-date base.
- Use `git add -p` when only part of a file belongs in the commit.
- Keep commits reviewable: one reason per commit, no generated or private files.
- Use `git worktree add ../repo-topic -b feature/topic origin/main` when you
  need multiple branches open at once without stashing.

## Merge

Use merge when preserving the real integration point matters, when the branch is
shared, or when project policy wants merge commits.

```sh
git fetch origin
git switch main
git merge --ff-only origin/main
git merge feature/topic
```

- `--ff-only` updates a branch only when no merge commit is needed.
- `--no-ff` records a merge commit even if a fast-forward is possible.
- A normal merge uses the branch tips plus the common ancestor. If histories
  diverged, Git creates a merge commit.
- To back out of a conflicted merge before committing, use
  `git merge --abort`.
- To undo a local, unpushed merge commit, `git reset --hard HEAD~1` works but
  discards uncommitted work. Prefer asking before using it.
- To undo a pushed merge, use `git revert -m 1 <merge-commit>` so shared
  history remains append-only.

## Merge Conflicts

When Git stops with conflicts:

```sh
git status --short
git diff
git log --oneline --left-right --merge
git diff --ours -- path/to/file
git diff --theirs -- path/to/file
git diff --base -- path/to/file
```

Conflict markers mean the following. The example is shown with one leading
space on marker lines so Git does not treat this documentation as an unresolved
conflict:

```text
 <<<<<<< HEAD
current side
 =======
incoming side
 >>>>>>> branch-name
```

Resolution loop:

```sh
git status --short
# edit conflicted files; remove conflict markers
git add path/to/file
git status --short
git merge --continue
```

- Use `git config --global merge.conflictstyle diff3` to include the common
  ancestor in conflict markers. This helps when both sides changed from the same
  original text.
- For one file, `git checkout --ours -- path` chooses the current side and
  `git checkout --theirs -- path` chooses the incoming side.
- During rebase conflicts, "ours" is the already-rebased target side and
  "theirs" is the commit being replayed. Verify with `git diff` before choosing
  a side.
- For whitespace-only conflicts, abort and retry with
  `git merge -Xignore-space-change branch` or
  `git merge -Xignore-all-space branch`.
- Enable `git config --global rerere.enabled true` if you repeatedly merge or
  rebase long-lived branches. Git can then reuse recorded conflict resolutions.

## Rebase

Use rebase to replay local, unpublished commits onto a newer base, clean a topic
branch before review, or turn a stack into a linear story.

```sh
git fetch origin
git switch feature/topic
git rebase origin/main
```

Conflict loop:

```sh
git status --short
# edit files
git add path/to/file
git rebase --continue
```

Escape hatches:

```sh
git rebase --abort
git rebase --skip
```

Interactive cleanup:

```sh
git rebase -i origin/main
git rebase -i --autosquash origin/main
```

- Never rebase commits that other people may have based work on unless the team
  explicitly coordinates the rewrite.
- If a rewritten branch must be pushed, use `git push --force-with-lease`, not
  plain `--force`.
- Use `git pull --rebase` only when your team expects it; otherwise fetch first
  and choose merge or rebase deliberately.
- Use `git range-diff origin/main...HEAD @{u}...HEAD` when reviewing how a
  rebased series changed relative to a previous version.
- Use `git rebase --rebase-merges` only when preserving local merge structure is
  part of the goal.

## Remove Accidentally Added Files

If the file is staged but not committed:

```sh
git restore --staged -- path/to/file
```

If the file should stay on disk but stop being tracked:

```sh
git rm --cached -- path/to/file
printf '%s\n' 'path/to/file' >> .gitignore
git add .gitignore
git commit -m "Stop tracking local file"
```

If the file was committed only in the latest local commit:

```sh
git rm --cached -- path/to/file
git commit --amend
```

If private data or a large file reached history:

1. Rotate or revoke the leaked secret first. Git cleanup does not make an
   exposed credential safe again.
2. Create a backup ref before rewriting:
   `git branch backup/before-history-cleanup`.
3. Prefer `git filter-repo` for full-file removals:
   `git filter-repo --path path/to/file --invert-paths`.
4. For line-level private data, use the
   `avbel/git-private-data-remover` pattern: dry run, inspect the blamed source
   commits, interactively replace only the private lines, and keep the automatic
   backup branch.
5. Clean local storage after the rewrite:
   `git reflog expire --expire=now --all` then
   `git gc --prune=now --aggressive`.
6. Push with `--force-with-lease` only after coordination. Ask collaborators to
   rebase carefully or reclone so old and new histories are not mixed.

Avoid `git filter-branch` for new cleanup work. Git's own documentation warns
about safety and performance problems; keep it as a last-resort fallback when
`git filter-repo` cannot be installed.

## Executable Files on Windows or Other Limited Filesystems

On Unix-like filesystems:

```sh
chmod +x scripts/run.sh
git add scripts/run.sh
```

On filesystems where executable bits are unsupported or unreliable:

```sh
git add --chmod=+x scripts/run.sh
# or, for an already tracked path:
git update-index --chmod=+x scripts/run.sh
git commit -m "Mark run script executable"
```

Verify the index mode:

```sh
git ls-files -s scripts/run.sh
# 100755 means executable; 100644 means not executable
```

- `core.filemode=false` makes Git ignore filesystem mode changes; it does not
  set the index executable bit by itself.
- Commit the mode change so future checkouts receive the executable bit.

## Large Files

Avoid committing large generated artifacts, build outputs, datasets, media, and
archives directly to normal Git history.

Use Git LFS for large files that belong in the repo workflow:

```sh
git lfs install
git lfs track "*.psd"
git add .gitattributes
git add design.psd
git commit -m "Track design asset with Git LFS"
```

- Commit `.gitattributes`; it is the contract that tells future clones which
  paths use LFS.
- Tracking a pattern does not convert existing history. Use
  `git lfs migrate import --include="*.psd" --everything` only with coordinated
  history-rewrite approval.
- For files that are outputs rather than source inputs, keep them outside
  normal Git history or use storage designed for binary artifacts.
- Check repository size with `git count-objects -vH`.
- Use `git filter-repo --analyze` to identify historical large paths when the
  repository is already bloated.

## Speed and Repository Health

Start with the cheap, safe knobs:

```sh
git maintenance start
git maintenance run --task=commit-graph --task=incremental-repack
git update-index --test-untracked-cache
git config core.untrackedCache true
git config core.fsmonitor true
git update-index --index-version 4
```

- `git maintenance start` schedules incremental repository optimization on the
  local machine.
- Commit-graph and incremental repack help large histories and many packfiles.
- `core.fsmonitor` helps large working trees by avoiding full file scans.
- `core.untrackedCache` speeds commands that need to list untracked files, but
  test filesystem support first.
- Index version 4 reduces index size for large repositories.

For very large repos or temporary local checkouts:

```sh
git clone --filter=blob:none --sparse <url>
git sparse-checkout init --cone
git sparse-checkout set src docs
git fetch --depth=1 origin main
```

- Partial clone avoids downloading blobs until needed.
- Sparse checkout reduces the working tree and index scope.
- Shallow fetches are useful for throwaway work but can break versioning,
  changelog, tag, and merge-base logic. Deepen when history is required:
  `git fetch --deepen=100` or `git fetch --unshallow`.

## Helper Script

Run the bundled helper to print JSON snippets for common workflows:

```sh
bash /mnt/skills/user/git/scripts/git-workflow-helper.sh all
bash /mnt/skills/user/git/scripts/git-workflow-helper.sh auth
bash /mnt/skills/user/git/scripts/git-workflow-helper.sh conflict
bash /mnt/skills/user/git/scripts/git-workflow-helper.sh rebase
bash /mnt/skills/user/git/scripts/git-workflow-helper.sh cleanup
bash /mnt/skills/user/git/scripts/git-workflow-helper.sh executable
bash /mnt/skills/user/git/scripts/git-workflow-helper.sh large-files
bash /mnt/skills/user/git/scripts/git-workflow-helper.sh speed
```

The helper writes status to stderr and machine-readable JSON to stdout so agents
can copy commands without reloading this whole skill.
