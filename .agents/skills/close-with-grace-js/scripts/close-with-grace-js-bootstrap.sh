#!/bin/bash
set -euo pipefail

cleanup() {
  :
}
trap cleanup EXIT

module_format="${1:-esm}"
scenario="${2:-generic}"

case "$module_format" in
  esm|cjs)
    ;;
  *)
    echo "Unsupported module format: $module_format. Use esm or cjs." >&2
    exit 2
    ;;
esac

case "$scenario" in
  generic|fastify|worker)
    ;;
  *)
    echo "Unsupported scenario: $scenario. Use generic, fastify, or worker." >&2
    exit 2
    ;;
esac

echo "Preparing close-with-grace scaffold for $module_format/$scenario" >&2

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if [ "$module_format" = "esm" ]; then
  import_line="import closeWithGrace from 'close-with-grace';"
else
  import_line="const closeWithGrace = require('close-with-grace');"
fi

case "$scenario" in
  fastify)
    snippet="closeWithGrace({ delay: 10_000 }, async ({ signal, err }) => { if (err) app.log.error({ err }, 'server closing with error'); else app.log.info({ signal }, 'server closing'); await app.close(); });"
    ;;
  worker)
    snippet="closeWithGrace({ delay: 10_000 }, async ({ signal, err, manual }) => { logger.info({ signal, err, manual }, 'worker shutting down'); await consumer.stop(); await db.end(); await telemetry.shutdown(); });"
    ;;
  generic)
    snippet="const closeListeners = closeWithGrace({ delay: 10_000 }, async ({ signal, err, manual }) => { await server.close(); await db.end(); });"
    ;;
esac

escaped_module_format="$(json_escape "$module_format")"
escaped_scenario="$(json_escape "$scenario")"
escaped_import_line="$(json_escape "$import_line")"
escaped_snippet="$(json_escape "$snippet")"

cat <<JSON
{
  "moduleFormat": "$escaped_module_format",
  "scenario": "$escaped_scenario",
  "dependencies": ["close-with-grace"],
  "install": "pnpm add close-with-grace",
  "import": "$escaped_import_line",
  "snippet": "$escaped_snippet",
  "aiUseTriggers": [
    "Node process entrypoint needs async cleanup on SIGTERM or SIGINT.",
    "Server, Fastify app, worker, queue consumer, scheduler, DB pool, or telemetry provider must close before process exit.",
    "Code has duplicate ad hoc process signal/error handlers."
  ],
  "notes": [
    "Register once at the process entrypoint, not in reusable libraries.",
    "Default delay is 10000 ms; choose a value below orchestrator hard-kill grace.",
    "Use uninstall() in tests or temporary harnesses."
  ]
}
JSON
