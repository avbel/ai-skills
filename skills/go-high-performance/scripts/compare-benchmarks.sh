#!/bin/bash
set -euo pipefail
unset CDPATH

fail() {
  echo "$*" >&2
  exit 1
}

if [[ $# -lt 5 || $# -gt 8 ]]; then
  fail "Usage: $0 BEFORE_DIR AFTER_DIR PACKAGE BENCH_REGEXP OUTPUT_PARENT [SAMPLES=10] [BENCHTIME=1s] [SAMPLE_TIMEOUT=10m]"
fi

package=$3
benchmark=$4
samples=${6-10}
benchtime=${7-1s}
sample_timeout=${8-10m}

[[ -n "$package" && "$package" != -* && -n "$benchmark" && -n "$benchtime" ]] ||
  fail 'Supply one package, a benchmark regexp and a benchtime.'
[[ "$samples" =~ ^[1-9][0-9]*$ ]] || fail 'Samples must be a positive integer.'
# Bash arithmetic wraps, so require the parsed value to match the input.
[[ "$samples" == "$((samples))" ]] || fail 'Sample count is too large.'
[[ "$sample_timeout" =~ ^[1-9][0-9]*[smhd]?$ ]] ||
  fail 'Sample timeout must be a positive whole duration such as 30s or 10m.'
command -v go >/dev/null || fail 'Go is required.'
command -v jq >/dev/null || fail 'jq is required for JSON output.'
if command -v gtimeout >/dev/null; then
  timeout_command=gtimeout
elif command -v timeout >/dev/null; then
  timeout_command=timeout
else
  fail 'GNU coreutils timeout (timeout or gtimeout) is required.'
fi

output_parent=$(cd -- "$5" && pwd -P)
before_version=$(cd -- "$1" && go env GOVERSION)
after_version=$(cd -- "$2" && go env GOVERSION)
[[ "$before_version" == "$after_version" ]] || fail "Toolchain mismatch: $before_version and $after_version."

run_dir=$(mktemp -d "$output_parent/go-bench.XXXXXX")
work_dir="$run_dir/work"
keep_results=false

cleanup() {
  if [[ "$keep_results" == true ]]; then
    rm -rf -- "$work_dir"
  else
    rm -rf -- "$run_dir"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -- "$work_dir"

build_benchmark() (
  cd -- "$1" || exit
  variant=$2
  package_dir=$(go list -f '{{.Dir}}' "$package") || exit
  [[ -n "$package_dir" && "$package_dir" != *$'\n'* ]] || fail "$package must select exactly one package in $variant."
  echo "Building $variant benchmark with $before_version" >&2
  go test -c -o "$work_dir/$variant.test" "$package" >&2 || exit
  [[ -x "$work_dir/$variant.test" ]] || fail "$package has no test binary in $variant."
  printf '%s\n' "$package_dir"
)

run_sample() (
  cd -- "$1"
  variant=$2
  sample_file="$work_dir/sample.txt"
  status=0
  "$timeout_command" --verbose --kill-after=5s "$sample_timeout" \
    "$work_dir/$variant.test" -test.run='^$' -test.bench="$benchmark" \
    -test.benchmem -test.benchtime="$benchtime" > "$sample_file" || status=$?
  if (( status != 0 )); then
    cat "$sample_file" >&2
    if (( status == 124 )); then
      fail "The $variant benchmark run timed out after $sample_timeout."
    fi
    fail "The $variant benchmark failed."
  fi

  benchmark_names=$(awk '$1 ~ /^Benchmark/ && $2 ~ /^[0-9]+$/ && NF >= 4 { print $1 }' "$sample_file" | LC_ALL=C sort -u)
  [[ -n "$benchmark_names" ]] || fail "No benchmarks matched '$benchmark' in $variant."
  if [[ -f "$work_dir/names.txt" ]]; then
    [[ "$benchmark_names" == "$(<"$work_dir/names.txt")" ]] || fail "Benchmark names or CPU settings changed in $variant."
  else
    printf '%s\n' "$benchmark_names" > "$work_dir/names.txt"
  fi
  cat "$sample_file" >> "$run_dir/$variant.txt"
)

before_package=$(build_benchmark "$1" before)
after_package=$(build_benchmark "$2" after)

echo "Collecting $samples sample(s) per build at $benchtime per benchmark" >&2
for ((sample = 0; sample < samples; sample++)); do
  if ((sample % 2 == 0)); then
    run_sample "$before_package" before
    run_sample "$after_package" after
  else
    run_sample "$after_package" after
    run_sample "$before_package" before
  fi
done

jq -n --arg before "$run_dir/before.txt" --arg after "$run_dir/after.txt" \
  --arg go_version "$before_version" --argjson samples_per_variant "$samples" --arg benchtime "$benchtime" \
  --arg sample_timeout "$sample_timeout" \
  '{before: $before, after: $after, go_version: $go_version, samples_per_variant: $samples_per_variant, benchtime: $benchtime, sample_timeout: $sample_timeout}'
keep_results=true
