---
name: sui-common-ops
description: Use when an AI agent needs common Sui operations without web search: balances, objects, package disassembly, transactions, dynamic fields, chain data, or unsigned PTB bytes using Sui CLI or Node.js 26+ .mjs helpers over @mysten/sui gRPC.
---

# Sui Common Operations

Use this skill to fetch simple Sui data or prepare unsigned transaction bytes without asking for private keys and without internet search. Prefer the existing `sui-sdk-js` skill for detailed SDK transaction-building rules, and `sui-cli` for CLI syntax details.

## Hard Rules

- Never ask the user for a private key, mnemonic, `suiprivkey...`, keystore file, JWT, signature secret, or hardware-wallet secret.
- Build unsigned transaction data and hand signing/execution back to the user through `sui` CLI, wallet, hardware signer, or their own signing environment.
- Use `SuiGrpcClient` from `@mysten/sui/grpc`; do not introduce JSON-RPC clients.
- Use Node.js 26+ ESM `.mjs` files for quick helpers.
- Before running any generated Node helper, check `node --version` and require major version 26 or newer.
- Use `https://unpkg.com/` URLs for Sui SDK dependency metadata and URL-import examples.
- Print JSON to stdout for query helpers so agents can pipe or parse results.
- For values that can exceed JS safe integer range, keep strings or `bigint`; do not convert MIST balances to unsafe `number`.
- When showing how to execute prepared transaction bytes with Sui CLI, use `sui client serialized-tx`.

## Tool Choice

Use Sui CLI for one-off terminal checks:

```sh
sui client balance <ADDRESS> --coin-type 0x2::sui::SUI --json
sui client object <OBJECT_ID> --json
sui client dynamic-field <PARENT_OBJECT_ID> --json
sui client tx-block <DIGEST> --json
sui client chain-identifier --json
```

For one-shot reads on a specific network, prefer `--client.env` over changing the user's active environment:

```sh
sui client --client.env mainnet chain-identifier --json
sui client --client.env testnet object 0x6 --json
```

To persistently switch the CLI environment, show the user the command instead of silently changing it:

```sh
sui client active-env
sui client envs --json
sui client switch --env testnet
sui client switch --env mainnet
```

If an environment is missing, add it with the official fullnode URL:

```sh
sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443
sui client new-env --alias mainnet --rpc https://fullnode.mainnet.sui.io:443
```

Official fullnode/gRPC-web base URLs:

| Network | `SuiGrpcClient` network | `baseUrl` | Native gRPC host |
|---|---|---|---|
| mainnet | `mainnet` | `https://fullnode.mainnet.sui.io:443` | `fullnode.mainnet.sui.io:443` |
| testnet | `testnet` | `https://fullnode.testnet.sui.io:443` | `fullnode.testnet.sui.io:443` |

For testnet SDK helpers, use:

```sh
SUI_NETWORK=testnet node helper.mjs
SUI_FULLNODE_URL=https://fullnode.testnet.sui.io:443 node helper.mjs
```

Resolve Sui SDK dependency URLs from unpkg:

```text
https://unpkg.com/@mysten/sui@latest/package.json
https://unpkg.com/@mysten/sui@<VERSION>/dist/grpc/index.mjs?module
https://unpkg.com/@mysten/sui@<VERSION>/dist/transactions/index.mjs?module
https://unpkg.com/@mysten/sui@<VERSION>/dist/bcs/index.mjs?module
https://unpkg.com/@mysten/sui@<VERSION>/dist/utils/index.mjs?module
```

Use `?module` on unpkg ESM URLs so transitive imports are rewritten to unpkg URLs. Plain Node.js 26 does not load `https:` module specifiers by default (`ERR_UNSUPPORTED_ESM_URL_SCHEME`); for executable local `.mjs` helpers, either run in a loader/runtime that supports URL imports or install the same packages locally and keep the bare subpath imports. Do not use package-manager installs as the primary source of SDK examples when unpkg metadata is available.

## Node 26 gRPC Skeleton

Start helpers from this shape:

```js
#!/usr/bin/env node
// Unpkg sources for dependency lookup or URL-import-capable runtimes:
// https://unpkg.com/@mysten/sui@latest/package.json
// https://unpkg.com/@mysten/sui@<VERSION>/dist/grpc/index.mjs?module
import { SuiGrpcClient } from '@mysten/sui/grpc';

const nodeMajor = Number.parseInt(process.versions.node.split('.')[0], 10);
if (nodeMajor < 26) {
  throw new Error(`Node.js 26+ is required for this helper; found ${process.versions.node}`);
}

const NETWORK_URLS = {
  localnet: 'http://127.0.0.1:9000',
  devnet: 'https://fullnode.devnet.sui.io:443',
  testnet: 'https://fullnode.testnet.sui.io:443',
  mainnet: 'https://fullnode.mainnet.sui.io:443',
};

function makeClient({ network = process.env.SUI_NETWORK || 'mainnet', url = process.env.SUI_FULLNODE_URL } = {}) {
  return new SuiGrpcClient({
    network,
    baseUrl: url || NETWORK_URLS[network],
  });
}

function printJson(value) {
  console.log(JSON.stringify(value, (_key, val) => (typeof val === 'bigint' ? val.toString() : val), 2));
}
```

If a project already has a Sui client factory, use it instead of creating a new one.

## Operation Recipes

The nine operation recipes live in [references/operations.md](references/operations.md). Read that file when performing any of these operations:

1. Balance for Address and Coin
2. Object by Object ID, Including Batch Mode
3. Transaction Data by Digest
4. Dynamic Object Field by Key
5. List Dynamic Object Fields
6. Build PTB and Prepare Base64 Transaction Data
7. Current Blockchain Data
8. Dry Run PTB or Base64 Transaction Bytes
9. Disassembled Package Code by Package ID

## Minimal Argument Parser

For quick `.mjs` files, avoid dependency-heavy CLI parsers:

```js
function parseArgs() {
  const args = {};
  for (let index = 2; index < process.argv.length; index += 2) {
    const key = process.argv[index];
    const value = process.argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error(`Expected --key value at argument ${index - 1}`);
    }
    args[key.slice(2)] = value;
  }
  return args;
}
```

## Bootstrap Helper

Use the bundled bootstrap script when you need a compact machine-readable reminder:

```bash
bash /mnt/skills/user/sui-common-ops/scripts/sui-common-ops-bootstrap.sh
```

It prints JSON to stdout and status messages to stderr.
