# Sui SDK Coins and Address Balances

Use this reference for fungible-token payments, balance queries, coin-object compatibility, address-balance gas, and gasless transfers.

## Balance Systems

Sui has two systems for holding fungible tokens:

1. **Coin objects** have object IDs, versions, and balances.
2. **Address balances** accumulate per address and coin type without coin objects.

An address's total balance is its coin-object balance plus its address balance.

## Default: Send to an Address Balance

Use `tx.balance()` with `0x2::balance::send_funds` for ordinary payments. This deposits value without creating a coin object, and the resolver can source the payment from address balances and coin objects.

```ts
import { Transaction } from '@mysten/sui/transactions';
import { MIST_PER_SUI } from '@mysten/sui/utils';

const tx = new Transaction();
const recipient = '0xRecipientAddress';

// SUI
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [tx.balance({ balance: 1n * MIST_PER_SUI }), tx.pure.address(recipient)],
});

// Custom token
const TOKEN = '0xPackageId::module::TOKEN';
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: [TOKEN],
  arguments: [tx.balance({ type: TOKEN, balance: 1_000_000n }), tx.pure.address(recipient)],
});

// Multiple recipients and coin types in one PTB
const payments = [
  { coinType: '0x2::sui::SUI', amount: 100_000_000n, recipient: '0xAlice' },
  { coinType: TOKEN, amount: 2_000_000n, recipient: '0xBob' },
];

for (const payment of payments) {
  tx.moveCall({
    target: '0x2::balance::send_funds',
    typeArguments: [payment.coinType],
    arguments: [
      tx.balance({ type: payment.coinType, balance: payment.amount }),
      tx.pure.address(payment.recipient),
    ],
  });
}

// Deposit an existing Coin<T> object into an address balance
tx.moveCall({
  target: '0x2::coin::send_funds',
  typeArguments: [TOKEN],
  arguments: [tx.object(existingCoinObjectId), tx.pure.address(recipient)],
});
```

## When the Recipient Requires `Coin<T>`

Use `tx.coin()` with `transferObjects` only when a Move API requires `Coin<T>` or object identity matters:

```ts
tx.transferObjects(
  [tx.coin({ balance: 1n * MIST_PER_SUI })],
  recipient,
);

tx.transferObjects(
  [tx.coin({ type: TOKEN, balance: 1_000_000n })],
  recipient,
);
```

Both `tx.balance()` and `tx.coin()` resolve from address balances and coin objects.

| Option | Type | Default | Description |
|---|---|---|---|
| `balance` | `bigint \| number` | required | Amount in base units |
| `type` | `string` | `0x2::sui::SUI` | Coin type |
| `useGasCoin` | `boolean` | `true` | For SUI, use the gas coin when available; set `false` for sponsorship |

Resolution behavior:

- `tx.balance()` with sufficient address balance uses a direct `FundsWithdrawal` and avoids versioned coin inputs.
- Otherwise, the resolver fetches and combines available address balance and coin objects.
- Zero-value requests resolve without network lookups.

## Check Balances

```ts
const { balance } = await client.core.getBalance({
  owner,
  coinType: '0x2::sui::SUI',
});

console.log(balance.balance);        // total
console.log(balance.coinBalance);    // coin objects
console.log(balance.addressBalance); // address balance

const { balances } = await client.core.listBalances({ owner });
for (const item of balances) {
  console.log(item.coinType, item.balance);
}

const { objects } = await client.core.listCoins({
  owner,
  coinType: '0x2::sui::SUI',
  limit: 10,
});
for (const coin of objects) {
  console.log(coin.objectId, coin.balance);
}
```

Balance values are strings. Use `BigInt(balance.balance)` for arithmetic.

## Direct Address-Balance Withdrawals

Use `tx.withdrawal()` only when deliberately creating a direct `FundsWithdrawal` input. Prefer `tx.balance()` or `tx.coin()` for normal online builds.

```ts
const [coin] = tx.moveCall({
  target: '0x2::coin::redeem_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [tx.withdrawal({ amount: 1_000_000_000n })],
});

const [balance] = tx.moveCall({
  target: '0x2::balance::redeem_funds',
  typeArguments: [TOKEN],
  arguments: [tx.withdrawal({ amount: 1_000_000n, type: TOKEN })],
});
```

## Manual Coin Operations

Use split and merge only when coin-object identity or exact object selection matters:

```ts
const [coin1, coin2] = tx.splitCoins('0xMyCoinId', [1_000_000, 2_000_000]);
const [suiCoin] = tx.splitCoins(tx.gas, [1_000_000_000]);
tx.mergeCoins('0xCoin1', ['0xCoin2', '0xCoin3']);
```

## Address-Balance Gas

By default, the SDK uses the sender's SUI address balance for gas and falls back to SUI coin objects. Leave gas payment unset for automatic selection.

To require address-balance gas:

```ts
const tx = new Transaction();
tx.setSender(senderAddress);
tx.setGasPayment([]);
// ... add commands ...

const bytes = await tx.build({ client: grpcClient });
```

`tx.gas` is unavailable in this mode. Use `tx.balance()` or `tx.coin()` for transaction inputs that must work with either gas source.

For sponsorship from the sponsor's SUI address balance:

```ts
const tx = new Transaction();
tx.setSender(userAddress);
tx.setGasOwner(sponsorAddress);
tx.setGasPayment([]);

// The user sends their own SUI; the sponsor only supplies gas.
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [
    tx.balance({ balance: amountMist, useGasCoin: false }),
    tx.pure.address(recipient),
  ],
});

const bytes = await tx.build({ client: grpcClient });
```

Both parties sign the same built bytes. Fund the sponsor's SUI address balance before building or executing. Read [advanced.md](advanced.md) for the complete signing flow and offline expiration requirements.

## Gasless Stablecoin Transfers

Transactions built entirely from `tx.balance()` and eligible calls such as `balance::send_funds` can qualify for zero-SUI gas when the token is allowlisted:

```ts
const USDC =
  '0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC';

const tx = new Transaction();
tx.setSender(keypair.toSuiAddress());
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: [USDC],
  arguments: [
    tx.balance({ type: USDC, balance: 1_000_000n }),
    tx.pure.address(recipient),
  ],
});

const result = await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

With gRPC or GraphQL, the SDK detects an eligible transaction during building and sets the gas configuration. Do not assume arbitrary tokens or PTB shapes are gasless.
