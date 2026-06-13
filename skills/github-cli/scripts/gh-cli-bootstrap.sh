#!/bin/bash
set -e

tmp_dir="${TMPDIR:-/tmp}/gh-cli-bootstrap.$$"
mkdir -p "$tmp_dir"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

topic="${1:-all}"
echo "Generating GitHub CLI command snippets for topic: $topic" >&2

case "$topic" in
  all|auth|pr|actions|repo|api)
    ;;
  *)
    echo "Unknown topic: $topic" >&2
    echo "Usage: $0 [all|auth|pr|actions|repo|api]" >&2
    exit 2
    ;;
esac

case "$topic" in
  auth)
    cat <<'JSON'
{
  "topic": "auth",
  "commands": [
    "gh auth status",
    "gh auth login",
    "GH_PROMPT_DISABLED=1 gh auth status",
    "GH_HOST=github.example.com gh auth status"
  ],
  "notes": [
    "Prefer GH_TOKEN or GITHUB_TOKEN for automation.",
    "Do not print gh auth token output in logs."
  ]
}
JSON
    ;;
  pr)
    cat <<'JSON'
{
  "topic": "pr",
  "commands": [
    "gh pr status",
    "gh pr view --json number,title,state,url,headRefName,baseRefName",
    "gh pr create --base main --title \"Title\" --body-file pr.md --draft",
    "gh pr checks --watch",
    "gh pr merge 123 --squash --delete-branch"
  ],
  "notes": [
    "Use explicit --title and --body-file for deterministic PR creation.",
    "gh pr create --dry-run may still push git changes."
  ]
}
JSON
    ;;
  actions)
    cat <<'JSON'
{
  "topic": "actions",
  "commands": [
    "gh workflow list",
    "gh workflow run ci.yml --ref main -f environment=staging",
    "gh run list --workflow ci.yml --limit 20",
    "gh run view <run-id> --log-failed",
    "gh run watch <run-id> --compact --exit-status"
  ],
  "notes": [
    "workflow run requires on.workflow_dispatch in the workflow.",
    "run watch --exit-status is suitable for blocking automation."
  ]
}
JSON
    ;;
  repo)
    cat <<'JSON'
{
  "topic": "repo",
  "commands": [
    "gh repo view OWNER/REPO --json name,owner,defaultBranchRef,visibility,url",
    "gh repo clone OWNER/REPO",
    "gh repo create OWNER/REPO --private --description \"Service\" --source . --remote origin",
    "gh release create v1.2.3 dist/* --title \"v1.2.3\" --notes-file RELEASE.md"
  ],
  "notes": [
    "For non-interactive repo creation, pass --public, --private, or --internal.",
    "Inspect git remotes before using --source . --push."
  ]
}
JSON
    ;;
  api)
    cat <<'JSON'
{
  "topic": "api",
  "commands": [
    "gh api repos/{owner}/{repo}",
    "gh api repos/{owner}/{repo}/branches/{branch}/protection",
    "gh api graphql -F owner='{owner}' -F name='{repo}' -f query='query($owner:String!, $name:String!) { repository(owner:$owner, name:$name) { id name } }'"
  ],
  "notes": [
    "Use purpose-built gh commands before gh api when available.",
    "-f sends string fields; -F performs typed conversion and @file reads."
  ]
}
JSON
    ;;
  all)
    cat <<'JSON'
{
  "topic": "all",
  "commands": {
    "auth": "gh auth status",
    "pr": "gh pr view --json number,title,state,url",
    "actions": "gh run watch <run-id> --compact --exit-status",
    "repo": "gh repo view OWNER/REPO --json name,owner,defaultBranchRef,visibility,url",
    "api": "gh api repos/{owner}/{repo}"
  },
  "topics": ["auth", "pr", "actions", "repo", "api"]
}
JSON
    ;;
esac
