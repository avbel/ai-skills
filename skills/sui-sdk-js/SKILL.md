---
name: sui-sdk-js
description: Sui TypeScript SDK v2 conventions for JavaScript and TypeScript. Use when adding, reviewing, or debugging @mysten/sui clients (SuiGrpcClient, SuiGraphQLClient), transactions, keypairs, signing, BCS, faucet calls, coins, address balances, objects, Move calls, sponsored transactions, zkLogin, or Sui SDK migration work.
---

# Sui TypeScript SDK v2

Use this skill for JavaScript and TypeScript projects that interact with Sui through `@mysten/sui` v2+.

Primary source: Mysten Labs Sui TypeScript SDK docs at `https://sdk.mystenlabs.com/sui`.

**JSON-RPC is deprecated and will be decommissioned soon. Do not use `SuiJsonRpcClient` under any circumstances. Migrate all existing JSON-RPC code to `SuiGrpcClient` or `SuiGraphQLClient`.**

**All code in this skill targets SDK v2+. The legacy `SuiClient` from `@mysten/sui/client` (pre-v2) has been removed. Do not use it.**

## Current Defaults

- Use `@mysten/sui` v2+ docs and imports.
- The SDK is ESM-only. Ensure `package.json` has `"type": "module"` and TypeScript uses `moduleResolution` compatible with ESM, such as `NodeNext`, `Node16`, or `Bundler`.
- Prefer modular subpath imports like `@mysten/sui/grpc`, `@mysten/sui/transactions`, `@mysten/sui/keypairs/ed25519`, `@mysten/sui/bcs`, and `@mysten/sui/utils`.
- For new code, prefer `SuiGrpcClient` and the transport-agnostic `client.core` API. In reusable code, accept `ClientWithCoreApi` and call `client.core.*` even when native clients expose shortcuts.
- **JSON-RPC is deprecated and will be decommissioned. Never introduce `SuiJsonRpcClient` code. Migrate existing JSON-RPC usage to gRPC or GraphQL.**
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

For lower-level access beyond the Core API, `SuiGrpcClient` exposes service clients:

```ts
// Transaction execution
const { response } = await grpcClient.transactionExecutionService.executeTransaction({
  transaction: { bcs: { value: transactionBytes } },
  signatures: signatures.map((sig) => ({
    bcs: { value: fromBase64(sig) },
    signature: { oneofKind: undefined },
  })),
});
if (!response.finality?.effects?.status?.success) {
  throw new Error(`Transaction failed: ${response.finality?.effects?.status?.error || 'Unknown error'}`);
}

// Ledger service
const { response } = await grpcClient.ledgerService.getTransaction({ digest: '0x123...' });
const { response: epochInfo } = await grpcClient.ledgerService.getEpoch({});

// State service
const { response } = await grpcClient.stateService.listOwnedObjects({
  owner: '0xabc...',
  objectType: '0x2::coin::Coin<0x2::sui::SUI>',
});

// Name service
const { response } = await grpcClient.nameService.reverseLookupName({ address: '0xabc...' });
```

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

Sui has **two systems** for holding fungible token balances:

1. **Coin objects** — individual onchain objects, each with its own ID, version, and balance. You own specific coin objects and need to split, merge, and track them.
2. **Address balances** — an accumulator per address per coin type. No objects to manage: deposits automatically merge into a single balance, and you withdraw from it as needed.

An address's total balance = coin object balances + address balance.

### `tx.coin()` and `tx.balance()`

These are the **recommended** ways to get tokens in a transaction. They automatically draw from both coin objects and address balances.

```ts
import { Transaction, coinWithBalance } from '@mysten/sui/transactions';
import { MIST_PER_SUI } from '@mysten/sui/utils';

const tx = new Transaction();

// Send SUI via tx.coin() — produces a Coin<T> for transfers
tx.transferObjects([tx.coin({ balance: 1n * MIST_PER_SUI })], '0xRecipientAddress');

// Or use coinWithBalance() standalone alias
tx.transferObjects([coinWithBalance({ balance: 1n * MIST_PER_SUI })], '0xRecipientAddress');

// Send to address balance (no coin object created) — preferred for gasless transactions
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [tx.balance({ balance: 1n * MIST_PER_SUI }), tx.pure.address('0xRecipientAddress')],
});
```

Options for `tx.coin()` and `tx.balance()`:

| Option       | Type               | Default | Description |
|-------------|--------------------|---------|-------------|
| `balance`    | `bigint \| number` | required | Amount in base units (MIST for SUI) |
| `type`       | `string`           | `0x2::sui::SUI` | Coin type |
| `useGasCoin` | `boolean`          | `true` | For SUI, split from gas coin. Set `false` for sponsored transactions |

Resolution behavior:
- If sufficient address balance exists, uses `FundsWithdrawal` via `balance::redeem_funds` (no versioned object dependencies, enables parallel execution).
- Otherwise, fetches coin objects, merges as needed, splits exact amounts.
- Zero-balance requests resolve to `balance::zero` or `coin::zero` with no network lookups.

### Checking Balances

```ts
// Get balance for a specific coin type
const { balance } = await client.core.getBalance({
  owner: '0xabc...',
  coinType: '0x2::sui::SUI', // optional, defaults to SUI
});
console.log(balance.balance);        // total (coin objects + address balance)
console.log(balance.coinBalance);    // from coin objects only
console.log(balance.addressBalance); // from address balance only

// List all coin balances for an owner
const { balances } = await client.core.listBalances({ owner: '0xabc...' });
for (const b of balances) {
  console.log(b.coinType, b.balance);
}

// List specific coin objects
const result = await client.core.listCoins({
  owner: '0xabc...',
  coinType: '0x2::sui::SUI',
  limit: 10,
});
for (const coin of result.objects) {
  console.log(coin.objectId, coin.balance);
}

// Get coin metadata (name, symbol, decimals)
const { coinMetadata } = await client.core.getCoinMetadata({
  coinType: '0x2::sui::SUI',
});
if (coinMetadata) {
  console.log(coinMetadata.name, coinMetadata.symbol, coinMetadata.decimals);
}
```

All balance values are returned as strings. Use `BigInt(balance.balance)` for arithmetic.

### Direct Address-Balance Withdrawals

Use `tx.withdrawal()` only when you deliberately want a direct `FundsWithdrawal` input. It is the offline-friendly primitive behind address-balance redemption; `tx.coin()` / `tx.balance()` are still preferred for normal online builds because they resolve from both coin objects and address balances.

```ts
const [coin] = tx.moveCall({
  target: '0x2::coin::redeem_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [tx.withdrawal({ amount: 1_000_000_000n })],
});

tx.transferObjects([coin], '0xRecipientAddress');

const [balance] = tx.moveCall({
  target: '0x2::balance::redeem_funds',
  typeArguments: ['0xPackageId::module::USDC'],
  arguments: [tx.withdrawal({ amount: 1_000_000n, type: '0xPackageId::module::USDC' })],
});
```

### Manual Coin Operations

```ts
// Split coins
const [coin1, coin2] = tx.splitCoins('0xMyCoinId', [1_000_000, 2_000_000]);

// Split gas coin for SUI
const [coin] = tx.splitCoins(tx.gas, [1_000_000_000]);

// Merge coins
tx.mergeCoins('0xCoin1', ['0xCoin2', '0xCoin3']);
```

### Gasless Transactions

Transactions built entirely from `tx.balance()` and `balance::send_funds` with `gasPrice = 0` and `gasBudget = 0` can execute without SUI gas fees (allowlisted stablecoins only).

```ts
const USDC = '0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC';

const tx = new Transaction();
tx.setSender(keypair.toSuiAddress());

tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: [USDC],
  arguments: [tx.balance({ type: USDC, balance: 1_000_000 }), tx.pure.address(recipient)],
});

// gRPC/GraphQL auto-detect gasless eligibility and set gas price
const result = await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

## Query Patterns

### Objects

```ts
// Get single object
const { object } = await client.core.getObject({
  objectId,
  include: { content: true, display: true, owner: true },
});

// Get multiple objects
const { objects } = await client.core.getObjects({
  objectIds: ['0x123...', '0x456...'],
  include: { content: true },
});
for (const obj of objects) {
  if (obj instanceof Error) {
    console.log('Object not found:', obj.message);
  } else {
    console.log(obj.objectId, obj.type);
  }
}

// List owned objects
const result = await client.core.listOwnedObjects({
  owner: '0xabc...',
  filter: { StructType: '0x2::coin::Coin<0x2::sui::SUI>' },
  limit: 10,
});
// Paginate
if (result.cursor) {
  const nextPage = await client.core.listOwnedObjects({
    owner: '0xabc...',
    cursor: result.cursor,
  });
}
```

Object `include` options: `content`, `previousTransaction`, `json`, `objectBcs`, `display`.

Always request only the include fields needed.

### Dynamic Fields

```ts
// List dynamic fields
const result = await client.core.listDynamicFields({ parentId: '0x123...', limit: 10 });

// Get specific dynamic field
import { bcs } from '@mysten/sui/bcs';
const { dynamicField } = await client.core.getDynamicField({
  parentId: '0x123...',
  name: { type: 'u64', bcs: bcs.u64().serialize(42).toBytes() },
});

// Get dynamic object field (supports object include options)
const { object } = await client.core.getDynamicObjectField({
  parentId: '0x123...',
  name: { type: '0x2::object::ID', bcs: bcs.Address.serialize('0x456...').toBytes() },
  include: { content: true },
});
```

### Transactions

```ts
// Execute signed transaction
const result = await client.core.executeTransaction({
  transaction: transactionBytes,
  signatures: [signature],
  include: { effects: true, events: true },
});
if (result.Transaction) {
  console.log('Success:', result.Transaction.digest);
} else {
  console.log('Failed:', result.FailedTransaction?.status.error);
}

// Simulate (dry-run)
const simResult = await client.core.simulateTransaction({
  transaction: tx,
  include: { effects: true, balanceChanges: true, commandResults: true },
});

// Disable full validation only for inspection workflows such as non-entry Move functions
const uncheckedSim = await client.core.simulateTransaction({
  transaction: tx,
  checksEnabled: false,
  include: { commandResults: true },
});

// Get transaction by digest
const txResult = await client.core.getTransaction({
  digest: 'ABC123...',
  include: { effects: true, events: true, transaction: true },
});

// Wait for indexing by digest or by an execution result
await client.core.waitForTransaction({ digest: 'ABC123...', timeout: 60_000 });
await client.core.waitForTransaction({ result: executeResult, include: { effects: true } });
```

Transaction `include` options: `effects`, `events`, `transaction`, `balanceChanges`, `objectTypes`, `bcs`. Simulation also supports `commandResults`.

### System

```ts
const { referenceGasPrice } = await client.core.getReferenceGasPrice();
const { systemState } = await client.core.getCurrentSystemState();
const { chainIdentifier } = await client.core.getChainIdentifier();
```

### Move Metadata

```ts
const { function: fn } = await client.core.getMoveFunction({
  packageId: '0x2',
  moduleName: 'coin',
  name: 'value',
});
```

### Name Service

```ts
const { name } = await client.core.defaultNameServiceName({ address: '0xabc...' });

// MVR (Move Registry)
const { type } = await client.core.mvr.resolveType({
  type: '@mysten/sui::coin::Coin<@mysten/sui::sui::SUI>',
});
```

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

## Gas

The SDK handles gas automatically in most cases:
1. **Gas price** — uses network's reference gas price
2. **Gas budget** — simulates and estimates
3. **Gas payment** — uses address balances, falls back to coin objects

Override only when needed:

```ts
tx.setGasPrice(1500);
tx.setGasBudget(50_000_000);

// Specific coin objects for gas
tx.setGasPayment([
  { objectId: '0xCoin1', version: '1', digest: 'abc...' },
]);

// Use address balance for gas (no coin objects)
tx.setGasPayment([]);
```

`tx.gas` references the gas coin. Only works when gas is paid from coin objects. When using `setGasPayment([])`, use `tx.coin()` instead.

## Offline and Sponsored Transactions

### Offline Building

```ts
import { Transaction } from '@mysten/sui/transactions';

const tx = new Transaction();
tx.setSender(sender);
tx.setGasPrice(referenceGasPrice);
tx.setGasBudget(50_000_000);
tx.setGasPayment([{ objectId, version, digest }]);
tx.objectRef({ objectId, version, digest });

const bytes = await tx.build();
```

For offline transactions with no owned object inputs (only shared/party objects and address-balance withdrawals), use `tx.withdrawal()`, `tx.sharedObjectRef()` for shared or party objects, `tx.setGasPayment([])`, and set an expiration (`tx.setExpiration({ ValidDuring: ... })`) because no gas coin/object version anchors the transaction.

### Sponsored Transactions

Coin-based sponsorship:

```ts
// 1. User builds transaction kind bytes (no gas info)
const tx = new Transaction();
// ... add commands ...
const kindBytes = await tx.build({ client: grpcClient, onlyTransactionKind: true });

// 2. Sponsor wraps with gas info
const sponsoredTx = Transaction.fromKind(kindBytes);
sponsoredTx.setSender(userAddress);
sponsoredTx.setGasOwner(sponsorAddress);
sponsoredTx.setGasPayment(sponsorGasCoins);

// 3. Build, both sign, execute
const fullBytes = await sponsoredTx.build({ client: grpcClient });
const { signature: userSig } = await userKeypair.signTransaction(fullBytes);
const { signature: sponsorSig } = await sponsorKeypair.signTransaction(fullBytes);

const result = await grpcClient.executeTransaction({
  transaction: fullBytes,
  signatures: [userSig, sponsorSig],
});
```

Address balance sponsorship (simpler — sender can sign before sponsor):

```ts
const tx = new Transaction();
tx.setSender(userAddress);
tx.setGasOwner(sponsorAddress);
tx.setGasPayment([]); // address balance for gas
// ... add commands ...

const bytes = await tx.build({ client: grpcClient });
const { signature: userSig } = await userKeypair.signTransaction(bytes);
const { signature: sponsorSig } = await sponsorKeypair.signTransaction(bytes);

const result = await grpcClient.executeTransaction({
  transaction: bytes,
  signatures: [userSig, sponsorSig],
});
```

For sponsored transactions, set `useGasCoin: false` in `tx.coin()` / `tx.balance()`:

```ts
tx.transferObjects([tx.coin({ balance: 100n, useGasCoin: false })], recipient);
```

## BCS

```ts
import { bcs } from '@mysten/sui/bcs';

bcs.U8.serialize(1);
bcs.Address.serialize('0x1');
const effects = bcs.TransactionEffects.parse(bytes);
```

Do not pass full `objectBcs` envelope bytes to a Move struct parser. Use the object's `content` bytes when parsing Move struct fields.

### Parsing Object Content

```ts
import { MyStruct } from './generated/my-module';

const { object } = await client.core.getObject({
  objectId: '0x123...',
  include: { content: true },
});

const parsed = MyStruct.parse(object.content);
```

### Transaction Effects

```ts
const effects = bcs.TransactionEffects.parse(effectsBytes);
if (effects.V2.status.$kind === 'Success') {
  console.log('Transaction succeeded');
}
```

## Utils

```ts
import {
  MIST_PER_SUI,
  formatAddress,
  fromBase64,
  isValidSuiAddress,
  normalizeSuiAddress,
  parseToMist,
  toBase64,
  SUI_DECIMALS,
  SUI_ADDRESS_LENGTH,
  MOVE_STDLIB_ADDRESS,
  SUI_FRAMEWORK_ADDRESS,
  SUI_SYSTEM_ADDRESS,
  SUI_CLOCK_OBJECT_ID,
  SUI_SYSTEM_STATE_OBJECT_ID,
  SUI_RANDOM_OBJECT_ID,
  formatDigest,
  normalizeStructTag,
  normalizeSuiObjectId,
  normalizeSuiNSName,
  parseToUnits,
  isValidSuiObjectId,
  isValidTransactionDigest,
  isValidSuiNSName,
  fromHex,
  toHex,
} from '@mysten/sui/utils';
```

Validate address, object ID, digest, and SuiNS shapes at boundaries — validators do not prove on-chain existence.

## Faucet

```ts
import { getFaucetHost, requestSuiFromFaucetV2 } from '@mysten/sui/faucet';

await requestSuiFromFaucetV2({
  host: getFaucetHost('testnet'),
  recipient: '0xYourAddress',
});
```

Faucets are rate-limited. Mainnet has no faucet.

## zkLogin and Multisig

Use `@mysten/sui/zklogin` for zkLogin signatures and address computation. Preserve `legacyAddress` handling when maintaining existing accounts.

Use `@mysten/sui/multisig` for `MultiSigPublicKey` and multisig signing flows.

Treat zkLogin, passkey, and multisig flows as security-sensitive: verify exact docs and existing project conventions before changing production code.

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
- **No `SuiJsonRpcClient` or `@mysten/sui/jsonRpc` imports exist. JSON-RPC is deprecated.**
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
