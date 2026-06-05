#!/bin/bash
# Validate GitHub Actions workflow files with actionlint (syntax/expressions/
# shellcheck) and zizmor (security audit), then list act jobs if available.
#
# Usage:
#   bash /mnt/skills/user/github-actions-ci/scripts/validate-workflows.sh [repo-path]
#
#   repo-path  Directory containing .github/workflows (defaults to current dir).
#
# Exit code is non-zero if any validator reports a problem. Missing actionlint /
# zizmor are fetched on demand; set GA_CI_NO_AUTOINSTALL=1 to disable that and
# require them to be pre-installed. Status goes to stderr; findings to stdout.
set -euo pipefail

repo_root="${1:-.}"
workflows_dir="${repo_root%/}/.github/workflows"
no_autoinstall="${GA_CI_NO_AUTOINSTALL:-0}"

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

log() { echo "$*" >&2; }

if [ ! -d "$workflows_dir" ]; then
  log "error: no workflows directory at $workflows_dir"
  exit 2
fi

# Collect root-level workflow files. Group the -name tests so -maxdepth applies
# to BOTH extensions (find binds -o looser than the implicit -and otherwise).
# Built without mapfile so this still runs under macOS's bash 3.2.
wf_files=()
while IFS= read -r f; do
  wf_files+=("$f")
done < <(find "$workflows_dir" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) | sort)

if [ "${#wf_files[@]}" -eq 0 ]; then
  log "error: no .yml/.yaml workflow files in $workflows_dir"
  exit 2
fi

status=0

# --- actionlint -------------------------------------------------------------
# Prefer an already-installed binary, then `go install` (no pipe-to-shell), then
# the official release script — downloaded to a file and pinned to a tag, not
# streamed live into bash.
actionlint_version="1.7.12"
resolve_actionlint() {
  if command -v actionlint >/dev/null 2>&1; then
    echo actionlint
    return 0
  fi
  if [ "$no_autoinstall" = "1" ]; then
    return 1
  fi
  if command -v go >/dev/null 2>&1; then
    log "actionlint not found — installing via 'go install' (v$actionlint_version)..."
    if GOBIN="$tmp_dir" go install "github.com/rhysd/actionlint/cmd/actionlint@v$actionlint_version" >&2 2>&1; then
      echo "$tmp_dir/actionlint"
      return 0
    fi
  fi
  log "actionlint not found — downloading pinned release binary (v$actionlint_version)..."
  local script="$tmp_dir/download-actionlint.bash"
  if curl -fsSL "https://raw.githubusercontent.com/rhysd/actionlint/v$actionlint_version/scripts/download-actionlint.bash" -o "$script" \
      && bash "$script" "$actionlint_version" "$tmp_dir" >&2; then
    echo "$tmp_dir/actionlint"
    return 0
  fi
  return 1
}

log "==> actionlint"
if actionlint_bin="$(resolve_actionlint)"; then
  # actionlint exits non-zero on findings; capture without aborting the script.
  if "$actionlint_bin" -color "${wf_files[@]}"; then
    log "actionlint: no issues"
  else
    log "actionlint: issues found"
    status=1
  fi
else
  log "actionlint: unavailable (install from https://github.com/rhysd/actionlint) — skipped"
  status=1
fi

# --- zizmor ------------------------------------------------------------------
# Resolve a runnable command FIRST (probing --version), so a later non-zero exit
# unambiguously means "found security issues", not "tool failed to start".
resolve_zizmor() {
  if command -v zizmor >/dev/null 2>&1; then
    echo "zizmor"
    return 0
  fi
  if [ "$no_autoinstall" = "1" ]; then
    return 1
  fi
  if command -v uvx >/dev/null 2>&1 && uvx zizmor --version >/dev/null 2>&1; then
    echo "uvx zizmor"
    return 0
  fi
  if command -v pipx >/dev/null 2>&1 && pipx run zizmor --version >/dev/null 2>&1; then
    echo "pipx run zizmor"
    return 0
  fi
  return 1
}

log "==> zizmor"
# Offline unless a token is present, to avoid unauthenticated-API rate limits.
zizmor_args=(--persona regular)
if [ -z "${GITHUB_TOKEN:-}" ]; then
  zizmor_args+=(--offline)
fi
if zizmor_cmd="$(resolve_zizmor)"; then
  # zizmor_cmd may be two words ("uvx zizmor"); intentional word-split.
  # shellcheck disable=SC2086
  if $zizmor_cmd "${zizmor_args[@]}" "$workflows_dir"; then
    log "zizmor: no findings above threshold"
  else
    log "zizmor: findings reported"
    status=1
  fi
else
  log "zizmor: unavailable (install via 'uv tool install zizmor' or 'pipx install zizmor') — skipped"
  status=1
fi

# --- act (optional) ----------------------------------------------------------
log "==> act (job parse check)"
if command -v act >/dev/null 2>&1; then
  if act --list -W "$workflows_dir"; then
    log "act: workflows parsed into jobs"
  else
    log "act: failed to parse workflows"
    status=1
  fi
else
  log "act: not installed (optional) — skipped"
fi

if [ "$status" -eq 0 ]; then
  log "All validators passed."
else
  log "One or more validators reported problems."
fi
exit "$status"
