#!/bin/bash
set -euo pipefail

PACKAGE_ID="${1:-}"
OUTPUT_DIR="${2:-}"

if [ -z "$PACKAGE_ID" ]; then
  echo "Usage: sui-disassemble-package.sh <PACKAGE_ID> [OUTPUT_DIR]" >&2
  exit 2
fi

# Cleanup trap: remove the auto-created temp output directory on failure.
# On success the directory holds the deliverables and is kept.
TEMP_OUTPUT_DIR=""
cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ -n "$TEMP_OUTPUT_DIR" ]; then
    rm -rf "$TEMP_OUTPUT_DIR"
  fi
}
trap cleanup EXIT

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sui-package-${PACKAGE_ID:2:8}.XXXXXX")"
  TEMP_OUTPUT_DIR="$OUTPUT_DIR"
fi

MODULE_DIR="$OUTPUT_DIR/modules"
DISASM_DIR="$OUTPUT_DIR/disassembly"
PACKAGE_JSON="$OUTPUT_DIR/package.json"
CLIENT_ENV="${SUI_CLIENT_ENV:-}"
if [ -z "$CLIENT_ENV" ] && [ "${SUI_NETWORK:-}" != "localnet" ]; then
  CLIENT_ENV="${SUI_NETWORK:-}"
fi
SUI_CLIENT_ARGS=()
if [ -n "$CLIENT_ENV" ]; then
  SUI_CLIENT_ARGS=(--client.env "$CLIENT_ENV")
fi

mkdir -p "$MODULE_DIR" "$DISASM_DIR"

echo "Fetching package object $PACKAGE_ID" >&2
sui client "${SUI_CLIENT_ARGS[@]}" object "$PACKAGE_ID" --json > "$PACKAGE_JSON"

echo "Extracting module bytecode" >&2
node - "$PACKAGE_JSON" "$MODULE_DIR" <<'NODE'
const fs = require('fs');
const path = require('path');

const [packageJson, moduleDir] = process.argv.slice(2);
const object = JSON.parse(fs.readFileSync(packageJson, 'utf8'));
const moduleMap = object?.content?.Package?.module_map;

if (!moduleMap || typeof moduleMap !== 'object') {
  throw new Error('Package JSON did not contain content.Package.module_map');
}

function moduleBytesToBuffer(value) {
  // Some clients return module bytes as a base64 string, others as a byte array.
  if (typeof value === 'string') {
    return Buffer.from(value, 'base64');
  }
  if (Array.isArray(value) || value instanceof Uint8Array) {
    return Buffer.from(value);
  }
  throw new Error(`Unsupported module_map value type: ${Object.prototype.toString.call(value)}`);
}

for (const [name, bytes] of Object.entries(moduleMap)) {
  fs.writeFileSync(path.join(moduleDir, `${name}.mv`), moduleBytesToBuffer(bytes));
}

process.stderr.write(JSON.stringify(Object.keys(moduleMap)));
NODE
echo >&2

echo "Disassembling modules" >&2
for module_path in "$MODULE_DIR"/*.mv; do
  module_name="$(basename "$module_path" .mv)"
  sui move disassemble "$module_path" > "$DISASM_DIR/$module_name.disasm.move"
done

node - "$PACKAGE_ID" "$PACKAGE_JSON" "$MODULE_DIR" "$DISASM_DIR" <<'NODE'
const fs = require('fs');
const path = require('path');

const [packageId, packageJson, moduleDir, disasmDir] = process.argv.slice(2);
const modules = fs
  .readdirSync(disasmDir)
  .filter((name) => name.endsWith('.disasm.move'))
  .sort()
  .map((name) => {
    const file = path.join(disasmDir, name);
    const text = fs.readFileSync(file, 'utf8');
    return {
      module: name.replace(/\.disasm\.move$/, ''),
      bytecodeFile: path.join(moduleDir, `${name.replace(/\.disasm\.move$/, '')}.mv`),
      disassemblyFile: file,
      lines: text.split('\n').length,
    };
  });

console.log(JSON.stringify({ packageId, packageJson, modules }, null, 2));
NODE
