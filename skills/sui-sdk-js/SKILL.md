---
name: sui-sdk-js
description: Sui TypeScript SDK conventions for JavaScript and TypeScript. Use when adding, reviewing, or debugging @mysten/sui clients, transactions, keypairs, signing, BCS, faucet calls, coins, objects, Move calls, sponsored transactions, zkLogin, or Sui SDK migration work.
---

# Sui TypeScript SDK

Use this skill for JavaScript and TypeScript projects that interact with Sui through `@mysten/sui`.

Primary source: Mysten Labs Sui TypeScript SDK docs at `https://sdk.mystenlabs.com/sui`.

## Current Defaults

- Use `@mysten/sui` v2+ docs and imports.
- The SDK is ESM-only. Ensure `package.json` has `"type": "module"` and TypeScript uses `moduleResolution` compatible with ESM, such as `NodeNext`, `Node16`, or `Bundler`.
- Prefer modular subpath imports like `@mysten/sui/grpc`, `@mysten/sui/transactions`, `@mysten/sui/keypairs/ed25519`, `@mysten/sui/bcs`, and `@mysten/sui/utils`.
- For new code, prefer `SuiGrpcClient` and the transport-agnostic `client.core` API.
- Treat JSON-RPC as deprecated. Do not introduce new `SuiJsonRpcClient` code unless the project or target network still requires it.
- Public Mysten fullnode endpoints are rate-limited. Production apps should use dedicated nodes or a provider endpoint.

## Install

```bash
pnpm add @mysten/sui
```

Use the repo's actual package manager. If the app uses a local Sui network built from Sui `main`, consider the SDK docs' experimental-tag guidance; otherwise use the standard npm package.

## Client Choice

For new application code:

```ts
import { SuiGrpcClient } from '@mysten/sui/grpc';

const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',
});
```

Use `client.core` when writing libraries or reusable code that should work with gRPC, GraphQL, or JSON-RPC clients:

```ts
import type { ClientWithCoreApi } from '@mysten/sui/client';

export async function loadObject(client: ClientWithCoreApi, objectId: string) {
  const { object } = await client.core.getObject({
    objectId,
    include: { content: true, owner: true },
  });

  return object;
}
```

Use native service APIs only when the Core API cannot express the query or operation.

## Compatibility With Existing Code

Older projects may use imports such as:

```ts
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
```

Do not mechanically rewrite an existing working codebase just because new docs prefer gRPC. First check package version, transport assumptions, wallet/dApp integrations, and available endpoint support. For new code in an already-old project, match the existing client unless the task is explicitly a migration.

## Query Patterns

Core API methods cover common reads:

```ts
const { object } = await client.core.getObject({
  objectId,
  include: { content: true, display: true, owner: true },
});

const { coins } = await client.core.listCoins({
  owner,
  coinType: '0x2::sui::SUI',
});

const balance = await client.core.getBalance({
  owner,
  coinType: '0x2::sui::SUI',
});
```

Common method groups:

- Objects: `getObject`, `getObjects`, `listOwnedObjects`.
- Coins and balances: `getBalance`, `listBalances`, `listCoins`, `getCoinMetadata`.
- Dynamic fields: `listDynamicFields`, `getDynamicField`, `getDynamicObjectField`.
- Transactions: `executeTransaction`, `simulateTransaction`, `signAndExecuteTransaction`, `getTransaction`, `waitForTransaction`.
- System: `getReferenceGasPrice`, `getCurrentSystemState`, `getChainIdentifier`.
- Move metadata: `getMoveFunction`.

Always request only the include fields needed by the caller.

## Keypairs and Signing

Use the keypair class that matches the signing scheme:

```ts
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Secp256k1Keypair } from '@mysten/sui/keypairs/secp256k1';
import { Secp256r1Keypair } from '@mysten/sui/keypairs/secp256r1';

const keypair = Ed25519Keypair.deriveKeypair(mnemonic);
const address = keypair.getPublicKey().toSuiAddress();
```

Supported schemes:

- `Ed25519Keypair` from `@mysten/sui/keypairs/ed25519`.
- `Secp256k1Keypair` from `@mysten/sui/keypairs/secp256k1`.
- `Secp256r1Keypair` from `@mysten/sui/keypairs/secp256r1`.

Use `fromSecretKey` only with secret material that is already in the expected format. Never log mnemonics, bech32 secrets, raw private keys, signatures, JWTs, or zkLogin proofs.

## Transactions

Build programmable transaction blocks with `Transaction`:

```ts
import { Transaction } from '@mysten/sui/transactions';
import { MIST_PER_SUI } from '@mysten/sui/utils';

const tx = new Transaction();
const [coin] = tx.splitCoins(tx.gas, [1n * MIST_PER_SUI]);
tx.transferObjects([coin], recipient);

const result = await client.core.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
  include: { effects: true, objectChanges: true },
});

if (result.FailedTransaction) {
  throw new Error(`Sui transaction failed: ${result.FailedTransaction.status.error}`);
}
```

Core commands:

- `tx.splitCoins(coin, amounts)` creates coins from an existing coin or `tx.gas`.
- `tx.mergeCoins(destinationCoin, sourceCoins)` merges coins into one coin.
- `tx.transferObjects(objects, address)` transfers objects.
- `tx.moveCall({ target, arguments, typeArguments })` calls a Move function.

Use `bigint` for MIST and large integer values. Avoid JavaScript `number` for on-chain balances except for display-only formatting.

## Move Calls

Pass pure values and object references through transaction helpers:

```ts
const tx = new Transaction();

tx.moveCall({
  target: `${packageId}::module_name::function_name`,
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.object(objectId),
    tx.pure.address(recipient),
    tx.pure.u64(amountMist),
  ],
});
```

Before changing TypeScript transaction code, verify the actual Move function signature. Match object ownership, shared-object mutability, type arguments, and pure BCS types.

## Gas

By default, the SDK can derive gas budget by dry-running and can select available gas coins. Override only when needed:

```ts
tx.setGasBudget(50_000_000);
tx.setGasPrice(referenceGasPrice);
tx.setGasPayment([
  {
    objectId: gasCoinId,
    version: gasCoinVersion,
    digest: gasCoinDigest,
  },
]);
```

`tx.gas` can be split, merged into, borrowed by Move calls, or transferred. Be careful not to also use the same gas coin as a normal owned object input in a way that conflicts with gas payment selection.

## Offline and Sponsored Transactions

Offline builds must fully define sender, gas price, gas budget, gas payment, object references, and expiration if using address balances:

```ts
import { Inputs, Transaction } from '@mysten/sui/transactions';

const tx = new Transaction();
tx.setSender(sender);
tx.setGasPrice(referenceGasPrice);
tx.setGasBudget(50_000_000);
tx.setGasPayment([{ objectId, version, digest }]);

tx.object(Inputs.ObjectRef({ objectId, version, digest }));

const bytes = await tx.build();
```

For sponsored transactions, build only the transaction kind, then let the sponsor set gas owner and gas payment:

```ts
const kindBytes = await tx.build({ provider, onlyTransactionKind: true });
const sponsoredTx = Transaction.fromKind(kindBytes);

sponsoredTx.setSender(sender);
sponsoredTx.setGasOwner(sponsor);
sponsoredTx.setGasPayment(sponsorCoins);
```

Never let a user-controlled client choose sponsor coins without server-side validation.

## BCS

Use `@mysten/sui/bcs` for Sui-specific BCS schemes:

```ts
import { bcs } from '@mysten/sui/bcs';

const effects = bcs.TransactionEffects.parse(bytes);
```

Do not pass full `objectBcs` envelope bytes to a Move struct parser. Use the object's `content` bytes when parsing Move struct fields.

## Utils

Use `@mysten/sui/utils` for constants, validation, formatting, parsing, and encoding:

```ts
import {
  MIST_PER_SUI,
  formatAddress,
  fromBase64,
  isValidSuiAddress,
  normalizeSuiAddress,
  parseToMist,
  toBase64,
} from '@mysten/sui/utils';
```

Useful groups:

- Constants: `MIST_PER_SUI`, `SUI_DECIMALS`, `SUI_CLOCK_OBJECT_ID`, `SUI_SYSTEM_STATE_OBJECT_ID`.
- Formatters: `formatAddress`, `formatDigest`, `normalizeSuiAddress`, `normalizeStructTag`.
- Parsers: `parseToUnits`, `parseToMist`.
- Validators: `isValidSuiAddress`, `isValidSuiObjectId`, `isValidTransactionDigest`.
- Encodings: `fromHex`, `toHex`, `fromBase64`, `toBase64`.

Validate address and object ID shape at boundaries, but remember these validators do not prove the value exists on-chain.

## Faucet

Use faucets only for Devnet, Testnet, or local networks:

```ts
import { getFaucetHost, requestSuiFromFaucetV2 } from '@mysten/sui/faucet';

await requestSuiFromFaucetV2({
  host: getFaucetHost('testnet'),
  recipient,
});
```

Faucets are rate-limited. Mainnet has no faucet.

## zkLogin and Multisig

Use `@mysten/sui/zklogin` for zkLogin signatures and address computation. The docs note legacy zkLogin address behavior, so preserve `legacyAddress` handling when maintaining existing accounts.

Use `@mysten/sui/multisig` for `MultiSigPublicKey` and multisig signing flows. Treat zkLogin, passkey, and multisig flows as security-sensitive: verify exact docs and existing project conventions before changing production code.

## Review Checklist

- The package is imported through current modular subpaths.
- New code uses `SuiGrpcClient` or a `ClientWithCoreApi` abstraction unless there is a reason not to.
- Existing JSON-RPC code was not rewritten without a migration request.
- Transaction code matches the Move function signature and object ownership model.
- Balances and MIST amounts use `bigint` or strings, not unsafe `number` math.
- Transaction results are checked for failure before reporting success.
- Secrets and signatures are not logged.
- Production code does not depend on public rate-limited endpoints.
- Faucet code cannot run against mainnet.

## Helper Script

Use `scripts/sui-sdk-js-bootstrap.sh` when an agent needs a quick machine-readable scaffold:

```bash
bash /mnt/skills/user/sui-sdk-js/scripts/sui-sdk-js-bootstrap.sh grpc testnet
bash /mnt/skills/user/sui-sdk-js/scripts/sui-sdk-js-bootstrap.sh core mainnet
bash /mnt/skills/user/sui-sdk-js/scripts/sui-sdk-js-bootstrap.sh legacy-json-rpc devnet
```

The script prints JSON to stdout and status messages to stderr.
