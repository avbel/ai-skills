---
name: sui-sdk-js
description: Sui TypeScript SDK v2 conventions for JavaScript and TypeScript. Use when adding, reviewing, or debugging @mysten/sui clients (SuiGrpcClient, SuiGraphQLClient), transactions, keypairs, signing, BCS, faucet calls, coins, address balances, objects, Move calls, sponsored transactions, zkLogin, or Sui SDK migration work.
---

# Sui TypeScript SDK v2

Use this skill for JavaScript and TypeScript projects that interact with Sui through `@mysten/sui` v2+.

Primary source: Mysten Labs Sui TypeScript SDK docs at `https://sdk.mystenlabs.com/sui`.

**JSON-RPC is deprecated and will be decommissioned soon. Default to `SuiGrpcClient` (or `SuiGraphQLClient`) and migrate existing JSON-RPC code away from `SuiJsonRpcClient`. Documented exception: the Kiosk SDK requires `SuiJsonRpcClient` or `SuiGraphQLClient` because kiosk event queries are not available over gRPC — for kiosk work, follow the `sui-kiosk-sdk-js` skill.**

**All code in this skill targets SDK v2+. The legacy `SuiClient` from `@mysten/sui/client` (pre-v2) has been removed. Do not use it.**

## Current Defaults

- Use `@mysten/sui` v2+ docs and imports.
- The SDK is ESM-only. Ensure `package.json` has `"type": "module"` and TypeScript uses `moduleResolution` compatible with ESM, such as `NodeNext`, `Node16`, or `Bundler`.
- Prefer modular subpath imports like `@mysten/sui/grpc`, `@mysten/sui/transactions`, `@mysten/sui/keypairs/ed25519`, `@mysten/sui/bcs`, and `@mysten/sui/utils`.
- For new code, prefer `SuiGrpcClient` and the transport-agnostic `client.core` API. In reusable code, accept `ClientWithCoreApi` and call `client.core.*` even when native clients expose shortcuts.
- **JSON-RPC is deprecated and will be decommissioned. Do not introduce `SuiJsonRpcClient` code except for the documented kiosk/event-query exception (see the `sui-kiosk-sdk-js` skill). Migrate other JSON-RPC usage to gRPC or GraphQL.**
- Public Mysten fullnode endpoints are rate-limited (100 requests per 30 seconds). Production apps should use dedicated nodes or a provider endpoint.

## Install

```bash
pnpm add @mysten/sui
```

Use the repo's actual package manager.

## Client Choice

For new application code, use `SuiGrpcClient`:

```ts
import { SuiGrpcClient } from '@mysten/sui/grpc';

const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',
});
```

Network locations:

| Network | Full node URL | Faucet |
|---------|--------------|--------|
| localnet | `http://127.0.0.1:9000` | `http://127.0.0.1:9123/v2/gas` |
| Devnet | `https://fullnode.devnet.sui.io:443` | `https://faucet.devnet.sui.io/v2/gas` |
| Testnet | `https://fullnode.testnet.sui.io:443` | `https://faucet.testnet.sui.io/v2/gas` |
| Mainnet | `https://fullnode.mainnet.sui.io:443` | none |

Use `client.core` when writing libraries or reusable code that should work with gRPC or GraphQL clients:

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

Use `SuiClientTypes` from `@mysten/sui/client` for Core API option and response types when typing library boundaries.

Use native service APIs only when the Core API cannot express the query or operation.

### Transport Options

By default, `SuiGrpcClient` uses `GrpcWebFetchTransport` (works in browsers and Node.js via Fetch API).

For server-side applications (Node.js, Bun), use the native gRPC transport:

```ts
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { GrpcTransport } from '@protobuf-ts/grpc-transport';
import { ChannelCredentials } from '@grpc/grpc-js';

const transport = new GrpcTransport({
  host: 'fullnode.testnet.sui.io:443',
  channelCredentials: ChannelCredentials.createSsl(),
});

const grpcClient = new SuiGrpcClient({
  network: 'testnet',
  transport,
});
```

For local development without TLS:

```ts
const transport = new GrpcTransport({
  host: '127.0.0.1:9000',
  channelCredentials: ChannelCredentials.createInsecure(),
});

const grpcClient = new SuiGrpcClient({ network: 'localnet', transport });
```

### gRPC Service Clients

For lower-level access beyond the Core API (`transactionExecutionService`, `ledgerService`, `stateService`, `nameService`), read `references/queries.md`.

### GraphQL Client

For advanced query patterns not supported directly on full nodes:

```ts
import { SuiGraphQLClient } from '@mysten/sui/graphql';
import { graphql } from '@mysten/sui/graphql/schema';

const gqlClient = new SuiGraphQLClient({
  url: 'https://graphql.testnet.sui.io/graphql',
  network: 'testnet',
});

const query = graphql(`
  query { chainIdentifier }
`);
const result = await gqlClient.query({ query });
```

## Coins and Address Balances

Prefer address balances for ordinary fungible-token payments and gas:

- Use `tx.balance()` with `0x2::balance::send_funds` for SUI, custom tokens, and multiple recipients.
- Use `0x2::coin::send_funds` to deposit an existing `Coin<T>` object into an address balance.
- Use `tx.coin()` with `transferObjects` only when the recipient or Move API requires `Coin<T>`.
- Let the SDK select gas automatically, or call `tx.setGasPayment([])` to require SUI address-balance gas.
- With address-balance gas, `tx.gas` is unavailable; use `tx.balance()` or `tx.coin()` for portable inputs.
- For sponsored address-balance gas, set the user as sender, the sponsor as gas owner, and `setGasPayment([])`.

Read [references/coins-and-balances.md](references/coins-and-balances.md) for complete payment, query, withdrawal, gas, sponsorship, and gasless-transfer examples.

## Query Patterns

Object, dynamic field, transaction, system, Move metadata, and name service queries via `client.core` (including execute/simulate/wait patterns and `include` options): read `references/queries.md`.

## Keypairs and Signing

```ts
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Secp256k1Keypair } from '@mysten/sui/keypairs/secp256k1';
import { Secp256r1Keypair } from '@mysten/sui/keypairs/secp256r1';
import { decodeSuiPrivateKey } from '@mysten/sui/cryptography';
import { fromHex } from '@mysten/sui/utils';

// Random keypair
const keypair = new Ed25519Keypair();

// From secret key (Bech32 `suiprivkey1...` or raw Uint8Array)
const keypair = Ed25519Keypair.fromSecretKey(secretKey);

// From mnemonic
const keypair = Ed25519Keypair.deriveKeypair(mnemonic);

// Decode when the bech32 scheme is unknown
const decoded = decodeSuiPrivateKey('suiprivkey1...');

// From hex-encoded raw secret
const keypairFromHex = Ed25519Keypair.fromSecretKey(fromHex('0x...'));

const address = keypair.toSuiAddress();
```

Use `getSecretKey()` to export a keypair as a Bech32 `suiprivkey...`; use `encodeSuiPrivateKey(rawBytes, scheme)` when converting raw private-key bytes.

Supported schemes:
- `Ed25519Keypair` from `@mysten/sui/keypairs/ed25519`
- `Secp256k1Keypair` from `@mysten/sui/keypairs/secp256k1`
- `Secp256r1Keypair` from `@mysten/sui/keypairs/secp256r1`
- `PasskeyKeypair` from `@mysten/sui/keypairs/passkey`

Never log mnemonics, bech32 secrets, raw private keys, signatures, JWTs, or zkLogin proofs.

### Sign and Execute

```ts
const result = await keypair.signAndExecuteTransaction({
  transaction: tx,
  client: grpcClient,
});
```

This automatically sets sender, builds, signs, and executes. Result includes transaction data and effects by default.

### Sign Without Executing

```ts
tx.setSender(keypair.toSuiAddress());
const bytes = await tx.build({ client: grpcClient });
const { signature } = await keypair.signTransaction(bytes);
```

### Manual Execution

```ts
const result = await grpcClient.executeTransaction({
  transaction: bytes,
  signatures: [signature],
  include: { effects: true, events: true, balanceChanges: true },
});
```

### Checking Results

```ts
if (result.$kind === 'FailedTransaction') {
  throw new Error(`Failed: ${result.FailedTransaction.status.error?.message}`);
}
// Or shorthand:
const tx = result.Transaction ?? result.FailedTransaction;
if (!tx.status.success) {
  throw new Error(`Failed: ${tx.status.error?.message}`);
}
```

## Transactions

Build programmable transaction blocks with `Transaction`:

```ts
import { Transaction } from '@mysten/sui/transactions';
import { MIST_PER_SUI } from '@mysten/sui/utils';

const tx = new Transaction();

// Send SUI via balance (preferred — deposits to recipient's address balance)
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [tx.balance({ balance: 1n * MIST_PER_SUI }), tx.pure.address('0xRecipientAddress')],
});

// Or send as a coin object
tx.transferObjects([tx.coin({ balance: 1n * MIST_PER_SUI })], '0xRecipientAddress');

const result = await keypair.signAndExecuteTransaction({
  transaction: tx,
  client: grpcClient,
  include: { effects: true, balanceChanges: true },
});
```

Core transaction commands and inputs:
- `tx.splitCoins(coin, amounts)` — creates coins from an existing coin or `tx.gas`
- `tx.mergeCoins(destinationCoin, sourceCoins)` — merges coins into one
- `tx.transferObjects(objects, address)` — transfers objects
- `tx.moveCall({ target, arguments, typeArguments })` — calls a Move function; `package`, `module`, and `function` can be passed separately instead of `target`
- `tx.makeMoveVec({ elements, type? })` — creates a vector of object inputs for Move calls
- `tx.publish({ modules, dependencies })` and `tx.upgrade({ modules, dependencies, package, ticket })` — publish or upgrade Move packages
- `tx.coin({ balance, type?, useGasCoin? })` — produces a `Coin<T>` intent
- `tx.balance({ balance, type?, useGasCoin? })` — produces a `Balance<T>` intent
- `tx.withdrawal({ amount, type? })` — produces a direct address-balance withdrawal for `coin::redeem_funds` / `balance::redeem_funds`
- `tx.pure.address()`, `tx.pure.u64()`, `tx.pure.vector()`, `tx.pure.option()`, `tx.pure('vector<u8>', value)`, etc. — pure value inputs
- `tx.object(objectId)` — object reference input resolved at build time
- `tx.objectRef()`, `tx.sharedObjectRef()`, and `tx.receivingRef()` — fully resolved owned/immutable, shared/party, and receiving object inputs for offline builds
- `tx.object.system()`, `tx.object.clock()`, `tx.object.random()`, `tx.object.denyList()`, and `tx.object.option()` — system object and object-option helpers

Use `bigint` for MIST and large integer values. Avoid JavaScript `number` for on-chain balances.

When a command returns multiple values, use destructuring or indexing (`const [coin] = ...`, `result[0]`). Never spread a transaction result or pass it to `Array.from()`; the docs warn that this causes an infinite loop.

### Move Calls

```ts
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

### Thunks for Composable Building

```ts
function mintNft(name: string) {
  return (tx: Transaction) => {
    return tx.moveCall({
      target: '0xPackage::nft::mint',
      arguments: [tx.pure.string(name)],
    });
  };
}

const tx = new Transaction();
const [nft] = tx.add(mintNft('My NFT'));
tx.transferObjects([nft], '0xRecipientAddress');
```

### Serializing Transactions

```ts
// Serialize to JSON
const json = await tx.toJSON({ client: grpcClient });
// Reconstruct
const tx = Transaction.from(json);
```

## Additional References

Read `references/advanced.md` when the task needs any of:

- **Gas** — automatic gas handling and overrides (`setGasPrice`, `setGasBudget`, `setGasPayment`, `tx.gas` caveats).
- **Offline and sponsored transactions** — offline building with resolved refs, coin-based and address-balance sponsorship, `useGasCoin: false`.
- **BCS** — serialization, parsing object content, transaction effects.
- **Utils** — constants, formatting, validation, and encoding helpers from `@mysten/sui/utils`.
- **Faucet** — requesting test SUI with `requestSuiFromFaucetV2`.
- **zkLogin and multisig** — module pointers and security notes.

## Client Extensions

All clients support extensions through `$extend`:

```ts
import { walrus } from '@mysten/walrus';

const client = new SuiGrpcClient({ network: 'mainnet', baseUrl: '...' }).$extend(walrus());
await client.walrus.writeBlob({ ... });
```

## Review Checklist

- The package is imported through current modular subpaths.
- New code uses `SuiGrpcClient` or a `ClientWithCoreApi` abstraction.
- **No `SuiJsonRpcClient` or `@mysten/sui/jsonRpc` imports exist outside the documented kiosk/event-query exception (see the `sui-kiosk-sdk-js` skill). JSON-RPC is deprecated.**
- **No legacy `SuiClient` from `@mysten/sui/client` (pre-v2) exists.**
- Transaction code matches the Move function signature and object ownership model.
- Balances and MIST amounts use `bigint` or strings, not unsafe `number` math.
- Transaction results are checked for failure before reporting success.
- Secrets and signatures are not logged.
- Production code does not depend on public rate-limited endpoints.
- Faucet code cannot run against mainnet.
- `package.json` has `"type": "module"`.
- TypeScript `moduleResolution` is `NodeNext`, `Node16`, or `Bundler`.

## Helper Script

Use `scripts/sui-sdk-js-bootstrap.sh` when an agent needs a quick machine-readable scaffold:

```bash
bash /mnt/skills/user/sui-sdk-js/scripts/sui-sdk-js-bootstrap.sh grpc testnet
bash /mnt/skills/user/sui-sdk-js/scripts/sui-sdk-js-bootstrap.sh graphql mainnet
```

The script prints JSON to stdout and status messages to stderr.
