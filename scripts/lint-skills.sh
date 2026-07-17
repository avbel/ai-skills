#!/bin/bash
# Lint the skills/ tree against the conventions in CLAUDE.md.
# Run from the repository root: bash scripts/lint-skills.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ERRORS=0
fail() { echo "FAIL: $*" >&2; ERRORS=$((ERRORS + 1)); }

# Backticked tokens that look like skill names but are legitimately not skills
# (crate/package/tool names). Extend as needed.
CROSSREF_ALLOWLIST=(
  "hotpath-rs"   # upstream GitHub repo pawurb/hotpath-rs
  "rust-cache"   # Swatinem/rust-cache GitHub Action
  "core-js"      # npm polyfill package
  "rust-rocksdb" # RocksDB Rust crate
  "rust-src"     # rustup component
)

all_skills=()
for dir in skills/*/; do
  all_skills+=("$(basename "$dir")")
done

is_skill() {
  local needle="$1" s
  for s in "${all_skills[@]}"; do [ "$s" = "$needle" ] && return 0; done
  return 1
}

is_allowlisted() {
  local needle="$1" s
  for s in "${CROSSREF_ALLOWLIST[@]}"; do [ "$s" = "$needle" ] && return 0; done
  return 1
}

for dir in skills/*/; do
  name="$(basename "$dir")"
  skill_md="$dir/SKILL.md"

  # 1. Directory naming: kebab-case
  if ! [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    fail "$name: directory name is not kebab-case"
  fi

  if [ ! -f "$skill_md" ]; then
    fail "$name: missing SKILL.md"
    continue
  fi

  # 1b. Frontmatter name matches directory
  fm_name="$(awk '/^name:/{sub(/^name:[ ]*/,""); print; exit}' "$skill_md")"
  if [ "$fm_name" != "$name" ]; then
    fail "$name: frontmatter name '$fm_name' != directory name"
  fi

  # 2. Description present, non-empty, not oversized (loaded at startup for every session)
  desc="$(awk '/^description:/{sub(/^description:[ ]*/,""); print; exit}' "$skill_md")"
  if [ -z "$desc" ]; then
    fail "$name: missing or empty frontmatter description"
  elif [ "${#desc}" -gt 400 ]; then
    fail "$name: description is ${#desc} chars (max 400)"
  fi

  # 3. Line limit and H1 title
  lines="$(wc -l < "$skill_md")"
  if [ "$lines" -gt 500 ]; then
    fail "$name: SKILL.md is $lines lines (max 500) — move reference material to references/"
  fi
  if ! awk 'NR==1 && /^---$/ {infm=1; next} infm && /^---$/ {infm=0; next} !infm && NF {print; exit}' "$skill_md" | grep -q '^# '; then
    fail "$name: SKILL.md has no H1 title after the frontmatter"
  fi

  # 4. Script requirements
  for script in "$dir"scripts/*.sh; do
    [ -e "$script" ] || continue
    if [ "$(head -1 "$script")" != "#!/bin/bash" ]; then
      fail "$name: $(basename "$script") missing '#!/bin/bash' shebang"
    fi
    if ! grep -qE '^set -e' "$script"; then
      fail "$name: $(basename "$script") missing 'set -e'"
    fi
    if [ ! -x "$script" ]; then
      fail "$name: $(basename "$script") is not executable (chmod +x)"
    fi
    if grep -qE 'mktemp|/tmp/' "$script" && ! grep -q 'trap ' "$script"; then
      fail "$name: $(basename "$script") uses temp files but has no cleanup trap"
    fi
  done

  # 5a. README row exists
  if ! grep -q "| \`$name\` |" README.md; then
    fail "$name: no row in README.md"
  fi

  # 6. Cross-references to sibling skills must exist.
  # Heuristic: backticked kebab-case tokens shaped like this repo's skill names.
  while IFS= read -r token; do
    is_skill "$token" && continue
    is_allowlisted "$token" && continue
    fail "$name: SKILL.md references \`$token\` which is not a skill in this repo"
  done < <(grep -ohE '`(dev|sui|move)-[a-z0-9-]+`|`rust-[a-z0-9-]+`|`[a-z0-9-]+-(rust|js|ts)`' "$dir"SKILL.md "$dir"references/*.md 2>/dev/null \
    | tr -d '`' | sort -u)
done

# 5b. Every README skill row points at a real directory
while IFS= read -r row; do
  if [ ! -d "skills/$row" ]; then
    fail "README.md row '$row' has no skills/$row directory"
  fi
done < <(grep -oP '(?<=^\| `)[a-z0-9_-]+(?=`)' README.md)

if [ "$ERRORS" -gt 0 ]; then
  echo "lint-skills: $ERRORS problem(s) found" >&2
  exit 1
fi
echo "lint-skills: OK (${#all_skills[@]} skills checked)"
