---
name: sui-kiosk-sdk-js
description: Sui Kiosk TypeScript SDK conventions for JavaScript and TypeScript. Use when adding, reviewing, or debugging @mysten/kiosk clients, KioskTransaction flows, listings, purchases, owned kiosks, transfer policies, royalties, rules, personal kiosks, or Kiosk SDK migration work.
---

# Sui Kiosk TypeScript SDK

Use this skill for JavaScript and TypeScript projects that interact with Sui Kiosk through `@mysten/kiosk`.

Primary source: Mysten Labs Kiosk SDK docs at `https://sdk.mystenlabs.com/kiosk#about`.

## Current Defaults

- Install `@mysten/kiosk` alongside `@mysten/sui`.
- Use the current client-extension and builder-pattern API.
- The Mysten SDK packages are ESM-only. Ensure `package.json` has `"type": "module"` and TypeScript uses `moduleResolution` compatible with ESM, such as `NodeNext`, `Node16`, or `Bundler`.
- The Kiosk extension requires `SuiJsonRpcClient` or `SuiGraphQLClient`. Do not use `SuiGrpcClient` for Kiosk SDK work because Kiosk uses event queries that are not available in gRPC.
- Keep one client instance per app/script and add the Kiosk extension with `$extend(kiosk())`.
- Mainnet and Testnet are supported by default. For Devnet or Localnet, pass package IDs for the rules/extensions you use.
- Mysten Kiosk rules and extensions are not supported on Devnet by default because network wipes would constantly change package IDs.

## Install

```bash
pnpm add @mysten/kiosk @mysten/sui
```

Use the repo's actual package manager.

## Client Setup

JSON-RPC setup:

```ts
import { kiosk } from '@mysten/kiosk';
import { getJsonRpcFullnodeUrl, SuiJsonRpcClient } from '@mysten/sui/jsonRpc';

export const client = new SuiJsonRpcClient({
  url: getJsonRpcFullnodeUrl('mainnet'),
  network: 'mainnet',
}).$extend(kiosk());
```

GraphQL is also supported. Prefer JSON-RPC when maintaining existing Kiosk code that already uses it. Prefer GraphQL if the app is already using GraphQL query patterns.

For Devnet or Localnet, configure explicit package IDs for the Kiosk rules and extensions required by the app:

```ts
const client = new SuiJsonRpcClient({
  url,
  network,
}).$extend(kiosk({ packageIds }));
```

Verify the exact `packageIds` shape against the current docs or existing project code before adding this configuration.

## Querying

Use `client.kiosk` for kiosk queries:

```ts
const { kioskOwnerCaps, kioskIds } = await client.kiosk.getOwnedKiosks({
  address,
});

const kiosk = await client.kiosk.getKiosk({
  id: kioskIds[0],
  options: {
    withKioskFields: true,
    withListingPrices: true,
  },
});
```

Important query concepts:

- `kioskOwnerCaps` are required for managing owned kiosks and for purchase flows.
- Save `KioskItem` data from kiosk-content queries when building purchase flows; fields such as `itemId`, `itemType`, `price`, and `sellerKiosk` are needed.
- The `listing` field applies only to items listed for sale.
- Query transfer policies with `client.kiosk` before resolving purchases or managing rules.
- Use owned transfer policy queries with `TransferPolicyTransaction` to add/remove rules and withdraw profits.

Do not assume a user has exactly one kiosk unless the product explicitly enforces that. Present a selector or choose by app-specific policy when multiple kiosks exist.

## KioskTransaction

Use `KioskTransaction` once per PTB that interacts with a kiosk:

```ts
import { KioskTransaction } from '@mysten/kiosk';
import { Transaction } from '@mysten/sui/transactions';

const tx = new Transaction();
const kioskTx = new KioskTransaction({
  transaction: tx,
  kioskClient: client.kiosk,
  cap,
});

kioskTx
  .placeAndList({
    item,
    itemType,
    price: 100_000n,
  })
  .finalize();
```

Always call `kioskTx.finalize()` as the final KioskTransaction interaction before signing/executing. `finalize()` returns kiosk caps for personal kiosks, shares newly created kiosks when needed, and completes pending personal-cap transfers.

## Owned Kiosk Management

Common builder methods:

- `create()` creates a kiosk.
- `createPersonal(true)` creates a personal kiosk and allows reuse in the same PTB.
- `shareAndTransferCap(address)` shares a created kiosk and transfers the cap.
- `place({ item, itemType })` places an item in the kiosk.
- `list({ itemId, itemType, price })` lists an already placed item.
- `placeAndList({ item, itemType, price })` places and lists in one transaction.
- `delist({ itemId, itemType })` removes a listing but leaves the item placed.
- `withdraw(address, amount?)` withdraws some or all profits.
- `lock({ itemId, itemType })` locks an item according to transfer-policy rules.
- `take(...)` removes an item when the flow allows it.

Example:

```ts
const tx = new Transaction();
const kioskTx = new KioskTransaction({
  transaction: tx,
  kioskClient: client.kiosk,
  cap,
});

kioskTx
  .place({
    item,
    itemType,
  })
  .list({
    itemId: item,
    itemType,
    price: 100_000n,
  })
  .finalize();
```

Use `bigint` for MIST amounts and prices.

## Borrow and Return

Use `borrowTx` for simple "borrow, run a PTB action, return" flows:

```ts
new KioskTransaction({
  kioskClient: client.kiosk,
  transaction: tx,
  cap,
})
  .borrowTx({ itemId, itemType }, (item) => {
    tx.moveCall({
      target: `${packageId}::hero::level_up`,
      arguments: [item],
    });
  })
  .finalize();
```

Use `borrow()` only when you need manual control, and always pair it with `return()`:

```ts
const [itemArg, promise] = kioskTx.borrow({ itemId, itemType });

tx.moveCall({
  target,
  arguments: [itemArg],
});

kioskTx
  .return({
    itemType,
    item: itemArg,
    promise,
  })
  .finalize();
```

Borrowing fails for items listed for sale.

## Purchasing

Use `purchaseAndResolve()` for standard purchases because it queries the transfer policy and resolves supported rules automatically:

```ts
const tx = new Transaction();
const kioskTx = new KioskTransaction({
  transaction: tx,
  kioskClient: client.kiosk,
  cap,
});

await kioskTx.purchaseAndResolve({
  itemType: item.itemType,
  itemId: item.itemId,
  price: item.price,
  sellerKiosk: item.sellerKiosk,
});

kioskTx.finalize();
```

For custom transfer-policy rules, add a custom rule resolver to the Kiosk extension and pass `extraArgs` when needed. Do not manually confirm transfer requests when `purchaseAndResolve()` can handle the policy.

`purchase()` is lower level: it returns `[item, transferRequest]`. Use it only when implementing custom resolution logic.

## TransferPolicyTransaction

Use `TransferPolicyTransaction` once per PTB that manages transfer policies:

```ts
import {
  TransferPolicyTransaction,
  percentageToBasisPoints,
} from '@mysten/kiosk';
import { Transaction } from '@mysten/sui/transactions';

const tx = new Transaction();
const tpTx = new TransferPolicyTransaction({
  kioskClient: client.kiosk,
  transaction: tx,
  cap: transferPolicyCap,
});

tpTx
  .addFloorPriceRule(1000n)
  .addRoyaltyRule(percentageToBasisPoints(10), 0)
  .addLockRule()
  .addPersonalKioskRule();
```

Creating a new policy:

```ts
const tpTx = new TransferPolicyTransaction({
  kioskClient: client.kiosk,
  transaction: tx,
});

await tpTx.create({
  type: `${packageId}::hero::Hero`,
  publisher,
});

tpTx
  .addLockRule()
  .addFloorPriceRule(1000n)
  .addRoyaltyRule(percentageToBasisPoints(10), 100)
  .addPersonalKioskRule()
  .shareAndTransferCap(recipient);
```

`create()` is async because the SDK protects against accidentally creating a second transfer policy. Use `skipCheck: true` only when the caller deliberately wants to bypass that check.

## Transfer Policy Rules

Supported manager actions include:

- `withdraw(address, amount?)`; omit `amount` to withdraw all profits.
- `addRoyaltyRule(percentageBps, minAmount)`.
- `removeRoyaltyRule()`.
- `addLockRule()` / `removeLockRule()`.
- `addPersonalKioskRule()` / `removePersonalKioskRule()`.
- `addFloorPriceRule(minPrice)` / `removeFloorPriceRule()`.

To update a rule, remove it and add it again with the new settings.

For royalties, `percentageToBasisPoints(10)` converts 10% to basis points. `minAmount` is the minimum royalty paid per transaction; use `0` for no minimum.

## Migration Notes

Kiosk SDK v0.7+ uses builder classes. Do not reintroduce removed low-level helpers.

Mappings from newer migration docs:

- `createKiosk` -> `kioskTx.create()`.
- `shareKiosk` -> `kioskTx.share()`.
- `place` -> `kioskTx.place()`.
- `lock` -> `kioskTx.lock()`.
- `take` -> `kioskTx.take()`.
- `list` -> `kioskTx.list()`.
- `delist` -> `kioskTx.delist()`.
- `placeAndList` -> `kioskTx.placeAndList()`.
- `purchase` -> `kioskTx.purchase()`.
- `withdrawFromKiosk` -> `kioskTx.withdraw()`.
- `borrowValue` -> `kioskTx.borrow()`.
- `returnValue` -> `kioskTx.return()`.
- `createTransferPolicyWithoutSharing` -> `tpTx.create()`.
- `shareTransferPolicy` -> `tpTx.shareAndTransferCap()`.
- `confirmRequest` -> handled by `kioskTx.purchaseAndResolve()`.
- `removeTransferPolicyRule` -> `tpTx.removeRule()`.
- `transactionBlock` constructor parameter -> `transaction`.

The current SDK works with Personal Kiosk directly; do not manually wrap calls with `borrow_cap` / `return_cap` unless you have verified the low-level Move flow requires it.

## Review Checklist

- Kiosk client is created with `$extend(kiosk())`.
- Code uses `SuiJsonRpcClient` or `SuiGraphQLClient`, not `SuiGrpcClient`.
- Mainnet/Testnet use default extension config; Devnet/Localnet explicitly configure package IDs if rules/extensions are used.
- Only one client instance is created for the app/script unless there is a clear reason.
- `KioskTransaction` and `TransferPolicyTransaction` use `transaction`, not old `transactionBlock`.
- Every `KioskTransaction` chain ends with `finalize()` as the last KioskTransaction call.
- Purchases prefer `purchaseAndResolve()` unless custom policy resolution is needed.
- Borrow flows pair `borrow()` with `return()`, or use `borrowTx()`.
- Prices and amounts use `bigint` or strings, not unsafe JavaScript number math.
- Transfer policy creation does not bypass the duplicate-policy check unless deliberate.

## Helper Script

Use `scripts/sui-kiosk-sdk-js-bootstrap.sh` when an agent needs a quick machine-readable scaffold:

```bash
bash /mnt/skills/user/sui-kiosk-sdk-js/scripts/sui-kiosk-sdk-js-bootstrap.sh json-rpc mainnet
bash /mnt/skills/user/sui-kiosk-sdk-js/scripts/sui-kiosk-sdk-js-bootstrap.sh graphql testnet
bash /mnt/skills/user/sui-kiosk-sdk-js/scripts/sui-kiosk-sdk-js-bootstrap.sh localnet localnet
```

The script prints JSON to stdout and status messages to stderr.
