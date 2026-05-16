#!/bin/bash
set -euo pipefail

cleanup() {
  :
}
trap cleanup EXIT

mode="${1:-grpc}"
network="${2:-testnet}"

case "$mode" in
  grpc|core|legacy-json-rpc)
    ;;
  *)
    echo "Unsupported mode: $mode. Use grpc, core, or legacy-json-rpc." >&2
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

echo "Preparing Sui TypeScript SDK scaffold for $mode on $network" >&2

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

case "$mode" in
  grpc)
    imports="import { SuiGrpcClient } from '@mysten/sui/grpc';"
    case "$network" in
      localnet)
        base_url="http://127.0.0.1:9000"
        ;;
      *)
        base_url="https://fullnode.$network.sui.io:443"
        ;;
    esac
    snippet="const client = new SuiGrpcClient({ network: '$network', baseUrl: '$base_url' });"
    ;;
  core)
    imports="import type { ClientWithCoreApi } from '@mysten/sui/client';"
    snippet="export async function getChainIdentifier(client: ClientWithCoreApi) { return client.core.getChainIdentifier(); }"
    ;;
  legacy-json-rpc)
    imports="import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc';"
    snippet="const client = new SuiJsonRpcClient({ url: getJsonRpcFullnodeUrl('$network'), network: '$network' });"
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
  "dependencies": ["@mysten/sui"],
  "packageJson": {
    "type": "module"
  },
  "typescript": {
    "moduleResolution": ["NodeNext", "Node16", "Bundler"]
  },
  "imports": "$escaped_imports",
  "snippet": "$escaped_snippet",
  "notes": [
    "Prefer SuiGrpcClient for new code.",
    "Use client.core for reusable libraries.",
    "JSON-RPC is deprecated; use legacy-json-rpc only for existing compatibility."
  ]
}
JSON
