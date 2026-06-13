#!/bin/bash
set -e

tmp_dir="${TMPDIR:-/tmp}/git-workflow-helper.$$"
mkdir -p "$tmp_dir"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

topic="${1:-all}"
echo "Generating Git workflow snippets for topic: $topic" >&2

case "$topic" in
  all|inspect|auth|merge|conflict|rebase|cleanup|executable|large-files|speed)
    ;;
  *)
    echo "Unknown topic: $topic" >&2
    echo "Usage: $0 [all|inspect|auth|merge|conflict|rebase|cleanup|executable|large-files|speed]" >&2
    exit 2
    ;;
esac

case "$topic" in
  inspect)
    cat <<'JSON'
{
  "topic": "inspect",
  "commands": [
    "git status --short --branch",
    "git branch --show-current",
    "git remote -v",
    "git log --oneline --decorate --graph --all -20",
    "git diff --stat",
    "git diff --cached --stat"
  ],
  "notes": [
    "Treat uncommitted changes as user work.",
    "Use -- before pathspecs that may look like flags."
  ]
}
JSON
    ;;
  auth)
    cat <<'JSON'
{
  "topic": "auth",
  "commands": [
    "gh auth login --git-protocol https",
    "gh auth status",
    "gh auth setup-git",
    "git config --global credential.helper manager",
    "git config --global --get credential.helper",
    "git config --global credential.helper osxkeychain",
    "git config --global credential.helper cache",
    "printf 'protocol=https\\nhost=github.com\\n\\n' | git credential reject",
    "ssh -T git@github.com",
    "ssh-add -l"
  ],
  "notes": [
    "Use gh auth setup-git for GitHub HTTPS credential helper setup.",
    "Prefer Git Credential Manager or OS keychain helpers for HTTPS remotes.",
    "Do not put tokens in commands, commits, shell history, .gitconfig, or remotes.",
    "SSH remotes use SSH keys and ssh-agent rather than Git credential helpers."
  ]
}
JSON
    ;;
  merge)
    cat <<'JSON'
{
  "topic": "merge",
  "commands": [
    "git fetch origin",
    "git switch main",
    "git merge --ff-only origin/main",
    "git merge feature/topic",
    "git merge --abort",
    "git revert -m 1 <merge-commit>"
  ],
  "notes": [
    "Use merge for shared branches or when preserving integration history matters.",
    "Use revert, not reset, to undo a pushed merge."
  ]
}
JSON
    ;;
  conflict)
    cat <<'JSON'
{
  "topic": "conflict",
  "commands": [
    "git status --short",
    "git diff",
    "git log --oneline --left-right --merge",
    "git diff --ours -- path/to/file",
    "git diff --theirs -- path/to/file",
    "git checkout --ours -- path/to/file",
    "git checkout --theirs -- path/to/file",
    "git add path/to/file",
    "git merge --continue"
  ],
  "notes": [
    "Remove conflict markers before staging.",
    "During rebase, ours/theirs semantics can feel inverted; inspect before choosing."
  ]
}
JSON
    ;;
  rebase)
    cat <<'JSON'
{
  "topic": "rebase",
  "commands": [
    "git fetch origin",
    "git switch feature/topic",
    "git rebase origin/main",
    "git rebase -i origin/main",
    "git rebase --continue",
    "git rebase --abort",
    "git push --force-with-lease"
  ],
  "notes": [
    "Rebase unpublished local commits.",
    "Do not rewrite shared history without explicit team coordination."
  ]
}
JSON
    ;;
  cleanup)
    cat <<'JSON'
{
  "topic": "cleanup",
  "commands": [
    "git restore --staged -- path/to/file",
    "git rm --cached -- path/to/file",
    "git commit --amend",
    "git branch backup/before-history-cleanup",
    "git filter-repo --path path/to/file --invert-paths",
    "git reflog expire --expire=now --all",
    "git gc --prune=now --aggressive"
  ],
  "notes": [
    "Rotate leaked secrets before Git cleanup.",
    "Prefer git-filter-repo or avbel/git-private-data-remover over git filter-branch."
  ]
}
JSON
    ;;
  executable)
    cat <<'JSON'
{
  "topic": "executable",
  "commands": [
    "chmod +x scripts/run.sh",
    "git add scripts/run.sh",
    "git add --chmod=+x scripts/run.sh",
    "git update-index --chmod=+x scripts/run.sh",
    "git ls-files -s scripts/run.sh"
  ],
  "notes": [
    "Use git add --chmod=+x or git update-index --chmod=+x when the filesystem cannot set executable bits.",
    "100755 in git ls-files -s means executable."
  ]
}
JSON
    ;;
  large-files)
    cat <<'JSON'
{
  "topic": "large-files",
  "commands": [
    "git lfs install",
    "git lfs track \"*.psd\"",
    "git add .gitattributes",
    "git count-objects -vH",
    "git filter-repo --analyze",
    "git lfs migrate import --include=\"*.psd\" --everything"
  ],
  "notes": [
    "Commit .gitattributes so LFS tracking applies to future clones.",
    "LFS migrate rewrites history; coordinate before use."
  ]
}
JSON
    ;;
  speed)
    cat <<'JSON'
{
  "topic": "speed",
  "commands": [
    "git maintenance start",
    "git maintenance run --task=commit-graph --task=incremental-repack",
    "git update-index --test-untracked-cache",
    "git config core.untrackedCache true",
    "git config core.fsmonitor true",
    "git update-index --index-version 4",
    "git clone --filter=blob:none --sparse <url>",
    "git sparse-checkout set src docs"
  ],
  "notes": [
    "Use maintenance, fsmonitor, untracked cache, and sparse checkout before blaming Git itself.",
    "Shallow history helps throwaway clones but can break tools that need tags or merge bases."
  ]
}
JSON
    ;;
  all)
    cat <<'JSON'
{
  "topic": "all",
  "topics": ["inspect", "auth", "merge", "conflict", "rebase", "cleanup", "executable", "large-files", "speed"],
  "commands": {
    "inspect": "git status --short --branch",
    "auth": "gh auth login --git-protocol https",
    "conflict": "git log --oneline --left-right --merge",
    "rebase": "git rebase origin/main",
    "cleanup": "git rm --cached -- path/to/file",
    "executable": "git add --chmod=+x scripts/run.sh",
    "large-files": "git lfs track \"*.psd\"",
    "speed": "git maintenance start"
  }
}
JSON
    ;;
esac
