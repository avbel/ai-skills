#!/bin/bash
set -e

echo "Preparing Sui common operations scaffold metadata" >&2

cat <<'JSON'
{
  "skill": "sui-common-ops",
  "runtime": "Node.js 26+ ESM",
  "versionCheck": "node --version must report v26 or newer before running generated .mjs helpers",
  "dependencySource": "https://unpkg.com/",
  "unpkg": {
    "packageJson": "https://unpkg.com/@mysten/sui@latest/package.json",
    "grpc": "https://unpkg.com/@mysten/sui@<VERSION>/dist/grpc/index.mjs?module",
    "transactions": "https://unpkg.com/@mysten/sui@<VERSION>/dist/transactions/index.mjs?module",
    "bcs": "https://unpkg.com/@mysten/sui@<VERSION>/dist/bcs/index.mjs?module",
    "utils": "https://unpkg.com/@mysten/sui@<VERSION>/dist/utils/index.mjs?module",
    "note": "Use ?module so transitive imports resolve to unpkg URLs. Plain Node 26 requires a loader/runtime for https imports; otherwise install the same packages locally for execution."
  },
  "networkEnv": {
    "network": "SUI_NETWORK",
    "fullnodeUrl": "SUI_FULLNODE_URL",
    "cliEnv": "SUI_CLIENT_ENV"
  },
  "networkSelection": {
    "oneShotCli": "sui client --client.env testnet <COMMAND> ... --json",
    "activeEnv": "sui client active-env",
    "listEnvs": "sui client envs --json",
    "switchToTestnet": "sui client switch --env testnet",
    "switchToMainnet": "sui client switch --env mainnet"
  },
  "officialFullnodeUrls": {
    "mainnet": "https://fullnode.mainnet.sui.io:443",
    "testnet": "https://fullnode.testnet.sui.io:443",
    "devnet": "https://fullnode.devnet.sui.io:443",
    "localnet": "http://127.0.0.1:9000"
  },
  "testnetGrpc": {
    "network": "testnet",
    "baseUrl": "https://fullnode.testnet.sui.io:443",
    "nativeHost": "fullnode.testnet.sui.io:443",
    "cliEnv": "testnet"
  },
  "wellKnownObjects": {
    "mainnetSystemInnerV2": "0x5b890eaf2abcfa2ab90b77b8e6f3d5d8609586c3e583baf3dccd5af17edf48d1",
    "clock": "0x6"
  },
  "operations": {
    "balance": "client.core.getBalance({ owner, coinType })",
    "object": "client.core.getObject({ objectId, include })",
    "objectsBatch": "client.core.getObjects({ objectIds, include })",
    "transaction": "client.core.getTransaction({ digest, include })",
    "dynamicObjectField": "client.core.getDynamicObjectField({ parentId, name, include })",
    "dynamicFields": "client.core.listDynamicFields({ parentId, cursor, limit })",
    "chainData": "SDK: getReferenceGasPrice + getCurrentSystemState + getChainIdentifier; CLI fast path: chain-identifier + object 0x5b890eaf2abcfa2ab90b77b8e6f3d5d8609586c3e583baf3dccd5af17edf48d1 + object 0x6",
    "ptbBytes": "toBase64(await tx.build({ client }))",
    "dryRunPtb": "client.core.simulateTransaction({ transaction: tx, include })",
    "dryRunTxBytes": "sui client serialized-tx '<TX_BYTES>' --sender <ALIAS_OR_ADDRESS> --dry-run --json",
    "disassembledPackage": "CLI: scripts/sui-disassemble-package.sh <PACKAGE_ID>; SDK: client.core.getObject({ objectId: packageId, include: { content: true, json: true } })"
  },
  "cliHandoff": {
    "inspect": "sui keytool decode-or-verify-tx --tx-bytes '<TX_BYTES>' --json",
    "dryRun": "sui client serialized-tx '<TX_BYTES>' --sender <ALIAS_OR_ADDRESS> --dry-run --json",
    "execute": "sui client serialized-tx '<TX_BYTES>' --sender <ALIAS_OR_ADDRESS> --json"
  },
  "cliSystemDataFastPath": [
    "sui client chain-identifier --json",
    "sui client object 0x5b890eaf2abcfa2ab90b77b8e6f3d5d8609586c3e583baf3dccd5af17edf48d1 --json",
    "sui client object 0x6 --json"
  ],
  "cliPackageDisassembly": "SUI_CLIENT_ENV=testnet bash /mnt/skills/user/sui-common-ops/scripts/sui-disassemble-package.sh <PACKAGE_ID> [OUTPUT_DIR]",
  "security": [
    "never ask for private keys or mnemonics",
    "produce unsigned transaction bytes",
    "hand signing and execution back to the user"
  ]
}
JSON
