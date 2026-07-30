#!/bin/bash
set -e

output_file="$(mktemp)"

cleanup() {
  rm -f "$output_file"
}
trap cleanup EXIT

json_escape() {
  local value="$1"
  local code octal control replacement
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\b'/\\b}"
  value="${value//$'\f'/\\f}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"

  for code in {1..31}; do
    case "$code" in
      8 | 9 | 10 | 12 | 13)
        continue
        ;;
    esac
    printf -v octal '%03o' "$code"
    printf -v control '%b' "\\$octal"
    printf -v replacement '\\u%04x' "$code"
    value="${value//$control/$replacement}"
  done

  printf '%s' "$value"
}

usage() {
  echo "Usage: verify-unit.sh [--system|--user] UNIT_FILE..." >&2
}

mode="system"
if [[ "${1:-}" == "--system" || "${1:-}" == "--user" ]]; then
  mode="${1#--}"
  shift
fi

if [[ "$#" -eq 0 ]]; then
  usage
  printf '{"ok":false,"mode":"%s","exitCode":64,"error":"no unit files provided"}\n' "$mode"
  exit 64
fi

if ! command -v systemd-analyze >/dev/null 2>&1; then
  echo "systemd-analyze is required for semantic unit validation" >&2
  printf '{"ok":false,"mode":"%s","exitCode":127,"error":"systemd-analyze not found"}\n' "$mode"
  exit 127
fi

for unit_file in "$@"; do
  if [[ ! -f "$unit_file" ]]; then
    escaped_file="$(json_escape "$unit_file")"
    echo "Unit file not found: $unit_file" >&2
    printf '{"ok":false,"mode":"%s","exitCode":66,"error":"unit file not found","file":"%s"}\n' \
      "$mode" "$escaped_file"
    exit 66
  fi
done

echo "Validating $* with the $mode manager search path" >&2

analyze_args=()
if [[ "$mode" == "user" ]]; then
  analyze_args+=(--user)
fi
analyze_args+=(verify)

set +e
systemd-analyze "${analyze_args[@]}" "$@" >"$output_file" 2>&1
status=$?
set -e

output="$(<"$output_file")"
escaped_output="$(json_escape "$output")"

printf '{"ok":%s,"mode":"%s","exitCode":%d,"files":[' \
  "$([[ "$status" -eq 0 ]] && printf true || printf false)" \
  "$mode" \
  "$status"

first=true
for unit_file in "$@"; do
  if [[ "$first" == true ]]; then
    first=false
  else
    printf ','
  fi
  printf '"%s"' "$(json_escape "$unit_file")"
done

printf '],"output":"%s"}\n' "$escaped_output"
exit "$status"
