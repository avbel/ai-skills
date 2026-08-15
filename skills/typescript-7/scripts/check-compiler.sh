#!/bin/bash
set -euo pipefail

compiler_input="${1:-./node_modules/.bin/tsc}"
compiler="$compiler_input"
error_log="$(mktemp)"

cleanup() {
  rm -f "$error_log"
}
trap cleanup EXIT

if [[ "$compiler_input" != */* && "$compiler_input" =~ ^[0-9A-Za-z._+-]+$ ]]; then
  compiler="$(command -v "$compiler_input" 2>/dev/null || true)"
fi

if [[ -z "$compiler" || ! -x "$compiler" ]]; then
  echo "Compiler is not executable: $compiler_input" >&2
  printf '{"ok":false,"error":"compiler_not_executable"}\n'
  exit 1
fi

echo "Checking TypeScript compiler: $compiler" >&2

if ! version_output="$("$compiler" --version 2>"$error_log")"; then
  echo "Compiler version check failed." >&2
  sed -n '1,20p' "$error_log" >&2
  printf '{"ok":false,"error":"version_check_failed"}\n'
  exit 1
fi

version_output="${version_output%$'\r'}"
if [[ ! "$version_output" =~ ^Version[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?)$ ]]; then
  echo "Unrecognized TypeScript version output: $version_output" >&2
  printf '{"ok":false,"error":"version_unrecognized"}\n'
  exit 1
fi

version="${BASH_REMATCH[1]}"
if [[ ! "$version" =~ ^7\. ]]; then
  echo "Expected TypeScript 7, got: $version_output" >&2
  printf '{"ok":false,"error":"wrong_major"}\n'
  exit 1
fi

printf '{"ok":true,"version":"%s"}\n' "$version"
