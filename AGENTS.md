# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Cursor, Copilot, etc.) when working with code in this repository.

## Repository Overview

A collection of skills for Claude.ai and Claude Code for working with Vercel deployments. Skills are packaged instructions and scripts that extend Claude's capabilities.

## Creating a New Skill

### Directory Structure

```
skills/
  {skill-name}/           # kebab-case directory name
    SKILL.md              # Required: skill definition
    scripts/              # Required: executable scripts
      {script-name}.sh    # Bash scripts (preferred)
```

### Naming Conventions

- **Skill directory**: `kebab-case` (e.g., `vercel-deploy`, `log-monitor`)
- **SKILL.md**: Always uppercase, always this exact filename
- **Scripts**: `kebab-case.sh` (e.g., `deploy.sh`, `fetch-logs.sh`)

### SKILL.md Format

```markdown
---
name: {skill-name}
description: {One sentence describing when to use this skill. Include trigger phrases like "Deploy my app", "Check logs", etc.}
---

# {Skill Title}

{Brief description of what the skill does.}

## How It Works

{Numbered list explaining the skill's workflow}

## Usage

```bash
bash /mnt/skills/user/{skill-name}/scripts/{script}.sh [args]
```

**Arguments:**
- `arg1` - Description (defaults to X)

**Examples:**
{Show 2-3 common usage patterns}

## Output

{Show example output users will see}

## Present Results to User

{Template for how Claude should format results when presenting to users}

## Troubleshooting

{Common issues and solutions, especially network/permissions errors}
```

### Best Practices for Context Efficiency

Skills are loaded on-demand — only the skill name and description are loaded at startup. The full `SKILL.md` loads into context only when the agent decides the skill is relevant. To minimize context usage:

- **Keep SKILL.md under 500 lines** — put detailed reference material in separate files
- **Write specific descriptions** — helps the agent know exactly when to activate the skill
- **Use progressive disclosure** — reference supporting files that get read only when needed
- **Prefer scripts over inline code** — script execution doesn't consume context (only output does)
- **File references work one level deep** — link directly from SKILL.md to supporting files

### Script Requirements

- Use `#!/bin/bash` shebang
- Use `set -e` for fail-fast behavior
- Write status messages to stderr: `echo "Message" >&2`
- Write machine-readable output (JSON) to stdout
- Include a cleanup trap for temp files
- Reference the script path as `/mnt/skills/user/{skill-name}/scripts/{script}.sh`

### Keeping README in Sync

**After adding any new skill, update `README.md`.**

Find the correct ecosystem section (Rust, TypeScript / JavaScript, Sui / Move) and add one row to the table:

```markdown
| `{skill-name}` | Brief description of what the skill covers |
```

The description must come from the `description:` field in `SKILL.md` — trim it to ≤ 10 words. If no existing section fits, add a new `###` heading above the row.

Do not reorder or reformat other rows when inserting.

### Cross-Agent Validation

**Before merging a new skill, have a second AI coding agent review it.**

Skills are prescriptive, so a flawed `SKILL.md` spreads bad practice across every project that installs it. The agent that drafted the skill shares context blind spots with its author; a second agent from a different vendor catches issues the original drafter cannot.

After committing the `SKILL.md` and the README row, request a review of the new skill from one of:

- Claude Code (`claude`)
- Codex (`codex`)
- opencode (`opencode`)
- Gemini CLI (`gemini`)

The review should answer: is the skill accurate, is it actionable, are the prescriptions justified, does it conflict with existing skills in the same ecosystem? Address the feedback or document why it was rejected, then merge.

If you are an AI agent without access to peer agents, surface the request to the user and pause before merging.

### End-User Installation

Document these two installation methods for users:

**Claude Code:**
```bash
cp -r skills/{skill-name} ~/.claude/skills/
```

**claude.ai:**
Add the skill to project knowledge or paste SKILL.md contents into the conversation.

If the skill requires network access, instruct users to add required domains at `claude.ai/settings/capabilities`.
