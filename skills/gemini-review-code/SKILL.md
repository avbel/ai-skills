---
name: gemini-review-code
description: Run a code review of local git changes by delegating to the Antigravity CLI (`agy`). Use when the user says "review my code/changes with Gemini/Antigravity", "agy review", "second-opinion review", or wants an external agent to review the working tree or branch diff. Review-only — never fixes code.
---

# Gemini Review Code

Delegate a code review of your local git state to Google's Antigravity CLI
(command `agy`). This is the Antigravity equivalent of the Codex review plugin:
it detects what changed, captures the exact diff into a self-contained review
brief, hands it to `agy` running non-interactively, and returns the verdict.

**This skill is review-only.** It never edits, fixes, or stages anything — its
single job is to run the review and surface `agy`'s output. If the review finds
issues, present them to the user and let them decide what to fix.

## How It Works

1. Detects the review scope from git:
   - `working-tree` — staged + unstaged + untracked changes (the default when the working tree is dirty).
   - `branch` — `git diff <base>...HEAD` (the default when the working tree is clean). Base auto-resolves to `origin/HEAD`, then `main`, then `master`.
2. Captures the changed-file list and full diff (plus the contents of any new untracked files) into a temporary Markdown **review brief** containing the review instructions, finding bar, and required output format.
3. Invokes `agy --print` non-interactively, pointing it at the brief. `agy` reads the brief, may read surrounding repository files for context, and produces the report.
4. Streams `agy`'s review to stdout verbatim. The temp brief is deleted on exit.

## Usage

```bash
bash /mnt/skills/user/gemini-review-code/scripts/review.sh [options] [focus text]
```

(When installed for Claude Code, the path is
`~/.claude/skills/gemini-review-code/scripts/review.sh`.)

**Options:**
- `--scope auto|working-tree|branch` — what to review. Defaults to `auto`.
- `--base <ref>` — base ref for `branch` scope (e.g. `--base develop`). Defaults to `origin/HEAD` → `main` → `master`.
- `--adversarial` — challenge framing: the reviewer tries to break confidence in the change and report why it should not ship, rather than a balanced pass.
- `--timeout <duration>` — print-mode wait passed to `agy --print-timeout`. Defaults to `10m`.
- `focus text` — any trailing words become a reviewer focus hint (e.g. `concurrency in the queue worker`).

**Examples:**

```bash
# Review whatever is currently changed in the working tree
bash scripts/review.sh

# Adversarial review of the current branch against develop
bash scripts/review.sh --scope branch --base develop --adversarial

# Focused review with a hint
bash scripts/review.sh auth and tenant isolation in the new middleware
```

## Requirements

- `agy` must be installed and on `PATH` (`agy install` configures the shell). The script exits with a clear message if it is missing.
- Must be run inside a git working tree.
- `agy` runs with `--dangerously-skip-permissions` so it can read the brief and repo files without interactive prompts. It is given a review-only prompt and is told not to edit files, but the flag does grant tool access — only run this in a repo you trust.

## Output

The raw review from `agy`, formatted as Markdown:

```
### Verdict
NEEDS ATTENTION — race on the shared counter can double-charge under retry.

### Findings
- **[HIGH] Non-atomic read-modify-write on `balance`**
  `src/wallet/charge.ts:42`
  Impact: two concurrent charges can both read the old balance and overwrite
  each other, dropping a debit.
  Recommendation: use a single `UPDATE ... SET balance = balance - $1` or a row lock.

### Next steps
- [ ] Make the balance update atomic.
- [ ] Add a concurrent-charge test.
```

Progress and scope-detection messages go to stderr; the review itself goes to stdout.

## Present Results to User

Show the review verbatim under a short heading, e.g. "Antigravity (`agy`) code
review:". Do **not** start fixing the findings unless the user explicitly asks.
If the user wants changes applied, treat that as a separate follow-up task.

## Troubleshooting

- **`'agy' ... is not installed`** — install the Antigravity CLI and run `agy install`, then retry.
- **`not inside a git working tree`** — `cd` into the repository first.
- **`Nothing to review`** — there are no changes for the chosen scope. For a clean working tree, pass `--scope branch` (optionally with `--base`).
- **Timeout / empty output** — large diffs take longer; raise `--timeout` (e.g. `--timeout 20m`). On first use, `agy` may require authentication — run `agy -p "hello"` once interactively to complete sign-in.
- **Permission prompts despite the flag** — ensure your `agy` version supports `--dangerously-skip-permissions` (`agy --help`).
