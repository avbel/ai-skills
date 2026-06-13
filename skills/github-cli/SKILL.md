---
name: github-cli
description: "Use when operating GitHub from the terminal with `gh`: authentication, repository setup, pull requests, issues, GitHub Actions workflow runs, releases, secrets, search, and direct REST or GraphQL API calls."
---

# GitHub CLI

Use these conventions for GitHub's `gh` command line tool. Prefer `gh` when the
task touches GitHub state and the user has not explicitly asked for raw `git`,
browser-only work, or direct API calls.

## Source Baseline

- Authoritative manual: <https://cli.github.com/manual/>.
- Verify local capabilities first: `gh --version` and `gh help <command>`.
- Use `gh help formatting` for command output, `gh help environment` for auth
  and automation variables, and `gh api --help` for endpoints not covered by a
  purpose-built command.
- In scripts and CI, set `GH_PROMPT_DISABLED=1` and pass explicit flags so
  prompts cannot hang the run.

## Authentication and Host Selection

```sh
gh auth status
gh auth login
gh auth login --hostname github.example.com
gh auth refresh -s project
gh auth token
```

- `gh auth login` defaults to a browser flow and stores a token in the system
  credential store when possible.
- For automation, prefer `GH_TOKEN` or `GITHUB_TOKEN` over `gh auth login
  --with-token`. Fine-grained PATs are often less surprising through
  `GH_TOKEN` than stdin login.
- Use `GH_HOST=<host>` for GitHub Enterprise Server defaults and `GH_REPO` or
  `-R OWNER/REPO` when running outside the target repository checkout.
- Do not print tokens. Treat `gh auth token` output like a secret.

## Output for Agents and Scripts

Prefer JSON-capable commands when parsing output:

```sh
gh pr view --json number,title,state,url,headRefName,baseRefName
gh issue list --state open --json number,title,labels,url
gh run list --limit 10 --json databaseId,status,conclusion,workflowName,url
```

- `--json` requires a comma-separated field list. Omit the field list only when
  discovering available fields for a command.
- Use `--jq` for small selections without requiring external `jq`:

```sh
gh pr list --json number,title,author --jq '.[] | {number, title, author: .author.login}'
```

- Use `--template` for human-readable tables when returning results directly to
  a user:

```sh
gh pr list --json number,title,headRefName,updatedAt \
  --template '{{range .}}{{tablerow (printf "#%v" .number) .title .headRefName (timeago .updatedAt)}}{{end}}{{tablerender}}'
```

## Pull Requests

```sh
gh pr status
gh pr list --state open --author @me
gh pr view --web
gh pr view --json number,title,body,commits,files,reviews,statusCheckRollup
gh pr checkout 123
gh pr create --base main --title "Add feature" --body-file pr.md --draft
gh pr ready
gh pr checks --watch
gh pr review 123 --comment --body-file review.md
gh pr merge 123 --squash --delete-branch
```

- Before `gh pr create`, check the branch has been pushed intentionally. If the
  branch is not pushed, `gh` may prompt to push or fork.
- Use `--title` and `--body`/`--body-file` for deterministic PR creation. Use
  `--fill` only when commit messages are already polished; explicit title/body
  flags override autofilled content.
- `--dry-run` prints PR details but may still push git changes. Do not treat it
  as a guaranteed no-network operation.
- For merge queues, `gh pr merge` may enqueue or enable auto-merge instead of
  choosing a merge strategy.

## Issues and Project Triage

```sh
gh issue list --state open --label bug --json number,title,labels,assignees,url
gh issue view 123 --comments
gh issue create --title "Bug title" --body-file issue.md --label bug
gh issue comment 123 --body-file note.md
gh issue develop 123 --checkout
gh issue close 123 --comment "Fixed by #456"
```

- Use labels, assignees, milestones, and `--repo` flags explicitly when the
  current directory is not the source of truth.
- For project fields, check scopes first. Project operations often require
  `gh auth refresh -s project`.

## GitHub Actions

```sh
gh workflow list
gh workflow view ci.yml
gh workflow run ci.yml --ref main -f environment=staging
gh run list --workflow ci.yml --limit 20
gh run view <run-id> --log-failed
gh run watch <run-id> --compact --exit-status
gh run rerun <run-id> --failed
```

- `gh workflow run` only works for workflows that define
  `on.workflow_dispatch`.
- Use `-f/--raw-field` for string inputs, `-F/--field` when `@file` expansion
  or typed API-style fields are desired, and `--json` to read workflow inputs
  from standard input.
- `gh run watch --exit-status` is the right shape for CI-style blocking because
  it exits non-zero on failed runs.
- Fine-grained PATs may not support every Actions operation, including some run
  watch/checks paths. Prefer the built-in `GITHUB_TOKEN` in Actions or a classic
  token with the needed scopes when local automation requires it.

## Repositories and Releases

```sh
gh repo view OWNER/REPO --json name,owner,defaultBranchRef,visibility,url
gh repo clone OWNER/REPO
gh repo fork OWNER/REPO --clone=false
gh repo create OWNER/REPO --private --description "Service" --source . --remote origin
gh repo set-default OWNER/REPO
gh release list
gh release create v1.2.3 dist/* --title "v1.2.3" --notes-file RELEASE.md
gh release upload v1.2.3 dist/checksum.txt --clobber
```

- For non-interactive `gh repo create`, pass one visibility flag:
  `--public`, `--private`, or `--internal`.
- `gh repo create --source . --push` mutates remotes and pushes commits; inspect
  `git remote -v` and branch state first.
- Use `--notes-file` for releases when notes are generated or reviewed outside
  the command line.

## Secrets and Variables

```sh
gh secret list
gh secret set NAME --body "$VALUE"
gh secret set NAME < secret.txt
gh variable list
gh variable set NAME --body "value"
```

- Never echo secret values in logs. Prefer stdin or environment variables already
  supplied by the execution environment.
- Add `--repo`, `--org`, or `--env` deliberately so secrets land at the intended
  scope.

## Search and Raw API Calls

```sh
gh search repos "language:rust topic:sui" --json fullName,description,url
gh search prs "is:open author:@me" --json number,title,repository,url
gh api repos/{owner}/{repo}/branches/{branch}/protection
gh api graphql -F owner='{owner}' -F name='{repo}' -f query='
  query($owner:String!, $name:String!) {
    repository(owner:$owner, name:$name) { id name defaultBranchRef { name } }
  }'
```

- Use purpose-built commands first (`gh pr`, `gh issue`, `gh run`, `gh release`)
  because their flags encode GitHub behavior and produce clearer errors.
- Use `gh api` for gaps. Place `{owner}`, `{repo}`, and `{branch}` in endpoint
  paths to let `gh` fill values from the current repository or `GH_REPO`.
- `gh api -f key=value` sends string fields; `-F key=value` performs type
  conversion for booleans, nulls, integers, placeholders, and `@file` reads.

## Helper Script

Run the bundled helper to print JSON snippets for common workflows:

```sh
bash /mnt/skills/user/github-cli/scripts/gh-cli-bootstrap.sh all
bash /mnt/skills/user/github-cli/scripts/gh-cli-bootstrap.sh pr
bash /mnt/skills/user/github-cli/scripts/gh-cli-bootstrap.sh actions
```

The helper writes status to stderr and machine-readable JSON to stdout so agents
can copy commands without reloading this whole skill.
