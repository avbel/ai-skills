# Sui TypeScript SDK v2 — Gas, Offline/Sponsored Transactions, BCS, Utils, Faucet, zkLogin/Multisig

Reference for the `sui-sdk-js` skill. Read this when configuring gas, building offline or sponsored transactions, working with BCS, utils, the faucet, or zkLogin/multisig.

## Gas

The SDK handles gas automatically in most cases:
1. **Gas price** — uses network's reference gas price
2. **Gas budget** — simulates and estimates
3. **Gas payment** — uses the sender's SUI address balance, then falls back to SUI coin objects when needed

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

`tx.setGasPayment([])` explicitly requires address-balance gas. `tx.gas` references a gas coin and is unavailable in this mode. Use `tx.balance()` or `tx.coin()` for portable transaction inputs that must work with either gas source.

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
tx.setGasPayment([]); // sponsor's SUI address balance pays gas
// ... add commands ...

const bytes = await tx.build({ client: grpcClient });
const { signature: userSig } = await userKeypair.signTransaction(bytes);
const { signature: sponsorSig } = await sponsorKeypair.signTransaction(bytes);

const result = await grpcClient.executeTransaction({
  transaction: bytes,
  signatures: [userSig, sponsorSig],
});
```

Fund the sponsor's SUI address balance before building or executing the transaction. For sponsored transactions, set `useGasCoin: false` in `tx.coin()` / `tx.balance()` so sender-funded SUI never resolves from the sponsor's gas source:

```ts
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.balance({ balance: 100n, useGasCoin: false }),
    tx.pure.address(recipient),
  ],
});
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
