# Sui TypeScript SDK v2 — Query Patterns and gRPC Service Clients

Reference for the `sui-sdk-js` skill. Covers `client.core` query patterns (objects, dynamic fields, transactions, system, Move metadata, name service) and lower-level gRPC service clients.

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
  console.log('Failed:', result.FailedTransaction?.status.error?.message);
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

## gRPC Service Clients

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
