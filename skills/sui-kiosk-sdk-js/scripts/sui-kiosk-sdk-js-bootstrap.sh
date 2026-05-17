#!/bin/bash
set -euo pipefail

cleanup() {
  :
}
trap cleanup EXIT

mode="${1:-json-rpc}"
network="${2:-mainnet}"

case "$mode" in
  json-rpc|graphql|localnet)
    ;;
  *)
    echo "Unsupported mode: $mode. Use json-rpc, graphql, or localnet." >&2
    exit 2
    ;;
esac

case "$network" in
  local|localnet|devnet|testnet|mainnet)
    ;;
  *)
    echo "Unsupported network: $network. Use localnet, devnet, testnet, or mainnet." >&2
    exit 2
    ;;
esac

if [ "$network" = "local" ]; then
  network="localnet"
fi

echo "Preparing Sui Kiosk SDK scaffold for $mode on $network" >&2

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

case "$mode" in
  json-rpc)
    imports="import { kiosk } from '@mysten/kiosk'; import { getJsonRpcFullnodeUrl, SuiJsonRpcClient } from '@mysten/sui/jsonRpc';"
    snippet="const client = new SuiJsonRpcClient({ url: getJsonRpcFullnodeUrl('$network'), network: '$network' }).\$extend(kiosk());"
    ;;
  graphql)
    imports="import { kiosk } from '@mysten/kiosk'; import { SuiGraphQLClient } from '@mysten/sui/graphql';"
    snippet="const client = new SuiGraphQLClient({ url: '<graphql-url>', network: '$network' }).\$extend(kiosk());"
    ;;
  localnet)
    imports="import { kiosk } from '@mysten/kiosk'; import { SuiJsonRpcClient } from '@mysten/sui/jsonRpc';"
    snippet="const client = new SuiJsonRpcClient({ url: 'http://127.0.0.1:9000', network: 'localnet' }).\$extend(kiosk({ packageIds }));"
    ;;
esac

escaped_mode="$(json_escape "$mode")"
escaped_network="$(json_escape "$network")"
escaped_imports="$(json_escape "$imports")"
escaped_snippet="$(json_escape "$snippet")"

cat <<JSON
{
  "mode": "$escaped_mode",
  "network": "$escaped_network",
  "dependencies": ["@mysten/kiosk", "@mysten/sui"],
  "packageJson": {
    "type": "module"
  },
  "typescript": {
    "moduleResolution": ["NodeNext", "Node16", "Bundler"]
  },
  "imports": "$escaped_imports",
  "snippet": "$escaped_snippet",
  "notes": [
    "Kiosk SDK requires SuiJsonRpcClient or SuiGraphQLClient; do not use SuiGrpcClient.",
    "Add the extension with \$extend(kiosk()).",
    "Use explicit packageIds for Devnet or Localnet rules/extensions."
  ]
}
JSON
