#!/bin/bash
set -euo pipefail

cleanup() {
  :
}
trap cleanup EXIT

mode="${1:-grpc}"
network="${2:-testnet}"

case "$mode" in
  grpc|graphql|json-rpc|relay)
    ;;
  *)
    echo "Unsupported mode: $mode. Use grpc, graphql, json-rpc, or relay." >&2
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

echo "Preparing Walrus SDK scaffold for $mode on $network" >&2

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

case "$network" in
  localnet)
    grpc_url="http://127.0.0.1:9000"
    json_rpc_url="http://127.0.0.1:9000"
    ;;
  *)
    grpc_url="https://fullnode.$network.sui.io:443"
    json_rpc_url="https://fullnode.$network.sui.io:443"
    ;;
esac

case "$mode" in
  grpc)
    imports="import { SuiGrpcClient } from '@mysten/sui/grpc'; import { walrus } from '@mysten/walrus';"
    snippet="const client = new SuiGrpcClient({ network: '$network', baseUrl: '$grpc_url' }).\$extend(walrus());"
    ;;
  graphql)
    imports="import { SuiGraphQLClient } from '@mysten/sui/graphql'; import { walrus } from '@mysten/walrus';"
    snippet="const client = new SuiGraphQLClient({ url: '<graphql-url>', network: '$network' }).\$extend(walrus());"
    ;;
  json-rpc)
    imports="import { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'; import { walrus } from '@mysten/walrus';"
    snippet="const client = new SuiJsonRpcClient({ url: '$json_rpc_url', network: '$network' }).\$extend(walrus());"
    ;;
  relay)
    imports="import { SuiGrpcClient } from '@mysten/sui/grpc'; import { walrus } from '@mysten/walrus';"
    snippet="const client = new SuiGrpcClient({ network: '$network', baseUrl: '$grpc_url' }).\$extend(walrus({ uploadRelay: { host: '<relay-url>', sendTip: { max: 1_000 } } }));"
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
  "dependencies": ["@mysten/walrus", "@mysten/sui"],
  "packageJson": {
    "type": "module"
  },
  "typescript": {
    "moduleResolution": ["NodeNext", "Node16", "Bundler"]
  },
  "imports": "$escaped_imports",
  "snippet": "$escaped_snippet",
  "notes": [
    "Use client.\$extend(walrus()); do not pass network to walrus().",
    "Direct storage-node reads and writes are request-heavy.",
    "Writes require signer funds for SUI gas and WAL storage fees."
  ]
}
JSON
