#!/bin/bash
set -euo pipefail

cleanup() {
  :
}
trap cleanup EXIT

format="${1:-ts}"
service_name="${2:-my-service}"

case "$format" in
  ts|mjs|cjs)
    ;;
  *)
    echo "Unsupported format: $format. Use ts, mjs, or cjs." >&2
    exit 2
    ;;
esac

case "$format" in
  ts)
    file="instrumentation.ts"
    run="npx tsx --import ./instrumentation.ts ./src/server.ts"
    ;;
  mjs)
    file="instrumentation.mjs"
    run="node --import ./instrumentation.mjs ./dist/server.js"
    ;;
  cjs)
    file="instrumentation.js"
    run="node --require ./instrumentation.js ./dist/server.js"
    ;;
esac

echo "Preparing OpenTelemetry Node.js bootstrap scaffold for $format" >&2

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

escaped_service="$(json_escape "$service_name")"
escaped_file="$(json_escape "$file")"
escaped_run="$(json_escape "$run")"

cat <<JSON
{
  "serviceName": "$escaped_service",
  "instrumentationFile": "$escaped_file",
  "dependencies": [
    "@opentelemetry/api",
    "@opentelemetry/sdk-node",
    "@opentelemetry/auto-instrumentations-node",
    "@opentelemetry/sdk-metrics",
    "@opentelemetry/sdk-trace-node"
  ],
  "otlpDependencies": [
    "@opentelemetry/exporter-trace-otlp-proto",
    "@opentelemetry/exporter-metrics-otlp-proto"
  ],
  "resourceDependencies": [
    "@opentelemetry/resources",
    "@opentelemetry/semantic-conventions"
  ],
  "runCommand": "$escaped_run",
  "env": {
    "OTEL_SERVICE_NAME": "$escaped_service",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_TRACES_EXPORTER": "otlp",
    "OTEL_METRICS_EXPORTER": "otlp"
  }
}
JSON
