---
name: sui-local-dev-usdc
description: Spin up a local Sui dev network, deploy a USDC-pegged coin, and top up dev balances with SUI and USDC. Trigger phrases: "local sui node", "sui local dev", "usdc on local sui", "mint usdc sui dev", "sui devnet setup".
---

# Sui Local Dev Network with USDC

Set up a local Sui validator network, deploy a mock USDC coin (6 decimals, matching Circle's native USDC on Sui), and fund developer addresses with both SUI and USDC for local testing.

## Prerequisites

- Sui CLI installed (`sui --version`). Install or manage versions with `suiup` (<https://github.com/MystenLabs/suiup>).
- No existing `~/.sui/sui_config` conflicts — `--force-regenesis` wipes state between runs.

## How It Works

1. **Start local network** — `sui start --with-faucet --force-regenesis` spins up a local validator, fullnode, and faucet.
2. **Create Move package** — `sui move new usdc` scaffolds a coin package with a `USDC` one-time witness.
3. **Publish USDC coin** — `sui client publish` deploys the package; the `init` function creates `TreasuryCap<USDC>` and `CoinMetadata<USDC>`, then mints an initial supply to the publisher.
4. **Request faucet SUI** — `sui client faucet` funds the active address with free SUI for gas.
5. **Mint more USDC** — `sui client call --function mint` uses the `TreasuryCap` to mint additional USDC to any address.

## Usage

```bash
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh start
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh publish-usdc
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh faucet
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh mint-usdc
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh balance
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh clean
```

The script prints JSON with `scenario`, `description`, and `commands` fields.

## Step-by-Step Guide

### 1. Start Local Network

```sh
# Fresh start — destroys any previous local state
RUST_LOG="off,sui_node=info" sui start --with-faucet --force-regenesis
```

- `--with-faucet` starts a local faucet on `http://127.0.0.1:9123/v2/gas`.
- `--force-regenesis` creates a new genesis each time; removes persisted state.
- To preserve state across restarts, omit `--force-regenesis` and run `sui genesis -f --with-faucet` once first.
- The local RPC defaults to `http://127.0.0.1:9000`.

After start, switch the CLI to the local network:

```sh
sui client new-env --alias local --rpc http://127.0.0.1:9000
sui client switch --env local
```

### 2. Fund Address with SUI (Faucet)

```sh
# Request test SUI from the local faucet (wait ~5s)
sui client faucet

# Request for a specific address
sui client faucet --address <ADDRESS>

# Verify gas coins
sui client gas
```

The faucet grants ~200 SUI per request. Multiple calls accumulate.

### 3. Create and Publish the USDC Coin Package

Create a Move package in a temp directory:

```sh
mkdir -p /tmp/usdc-coin && cd /tmp/usdc-coin
sui move new usdc
```

Write `sources/usdc.move`:

```move
module usdc::usdc;

use sui::coin::{Self, TreasuryCap};

/// One-time witness for USDC
public struct USDC has drop {}

/// Create the coin, mint initial supply to publisher,
/// freeze metadata (matching Circle native USDC: 6 decimals).
fun init(witness: USDC, ctx: &mut TxContext) {
    let (mut treasury, metadata) = coin::create_currency(
        witness,
        6,                                  // decimals — matches native USDC
        b"USDC",                             // symbol
        b"USD Coin",                         // name
        b"Mock USDC for local dev testing",  // description
        option::none(),                      // icon_url
        ctx,
    );
    transfer::public_freeze_object(metadata);

    // Mint 1 000 000 USDC (1_000_000 * 10^6 = 1_000_000_000_000 in micro-units)
    // to the publisher address as initial supply.
    coin::mint_and_transfer(
        &mut treasury,
        1_000_000_000_000,  // 1M USDC with 6 decimals
        ctx.sender(),
        ctx,
    );

    // Transfer TreasuryCap to publisher so they can mint more later
    transfer::public_transfer(treasury, ctx.sender());
}

/// Mint additional USDC. Only the TreasuryCap holder can call this.
public fun mint(
    treasury_cap: &mut TreasuryCap<USDC>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::mint(treasury_cap, amount, ctx);
    transfer::public_transfer(coin, recipient);
}
```

The `sui move new` scaffold already sets `edition = "2024.beta"` in `Move.toml`, which this statement-style module requires. `sui::transfer` and `sui::tx_context::TxContext` are implicit imports in Move 2024 and need no `use` statements.

Publish the package:

```sh
cd /tmp/usdc-coin
sui move build
sui client publish --gas-budget 100000000 .
```

From the publish output, note:
- **Package ID** — printed as `PackageID` under "Published Objects".
- **TreasuryCap ID** — the `TreasuryCap` object owned by your address.
- **Coin type** — `<PACKAGE_ID>::usdc::USDC`.

### 4. Verify USDC Balance

```sh
# Check all balances (SUI + USDC)
sui client balance

# Check only USDC
sui client balance --coin-type <PACKAGE_ID>::usdc::USDC
```

### 5. Mint Additional USDC

```sh
# Mint 10 000 USDC to an address (10_000 * 10^6 = 10_000_000_000 micro-units)
sui client call \
  --package <PACKAGE_ID> \
  --module usdc \
  --function mint \
  --args <TREASURY_CAP_ID> 10000000000 <RECIPIENT_ADDRESS> \
  --gas-budget 10000000
```

Or equivalently via PTB:

```sh
sui client ptb \
  --move-call <PACKAGE_ID>::usdc::mint \
  @<TREASURY_CAP_ID> 10000000000 <RECIPIENT_ADDRESS> \
  --gas-budget 10000000
```

### 6. Transfer USDC to Another Address

```sh
# Find USDC coin objects
sui client objects --json | jq '.[] | select(.type | endswith("::usdc::USDC"))'

# Transfer a specific USDC coin object
sui client ptb \
  --transfer-objects "[@<COIN_OBJECT_ID>]" <RECIPIENT_ALIAS_OR_ADDRESS> \
  --gas-budget 5000000
```

### 7. Stop and Clean Up

Press `Ctrl+C` in the terminal running `sui start`.

To completely reset (remove local state, keystore, and config):

```sh
rm -rf ~/.sui/sui_config
```

## Helper Script

The bootstrap script prints starter snippets without loading additional context. Each scenario is independent.

```bash
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh start
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh publish-usdc
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh faucet
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh mint-usdc
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh balance
bash /mnt/skills/user/sui-local-dev-usdc/scripts/sui-local-dev-usdc-bootstrap.sh clean
```

The script prints JSON with `scenario`, `description`, and `commands` fields.

## USDC Coin Details

| Property | Value |
| --- | --- |
| Symbol | USDC |
| Name | USD Coin |
| Decimals | 6 (matches native Circle USDC on Sui) |
| Description | Mock USDC for local dev testing |
| Initial supply | 1 000 000 USDC (1M × 10⁶ = 1 000 000 000 000 micro-units) |
| TreasuryCap | Transferred to publisher — allows unlimited minting |

**Important:** This is a *mock* USDC for local development only. The `TreasuryCap` is held by the deployer, meaning anyone with access to that key can mint unlimited USDC. Never deploy this init pattern to mainnet.

## Key Differences from Native Circle USDC

- **No RegulatedCoin standard** — Circle's native USDC uses Sui's `RegulatedCoin` which adds freeze/deny-list capabilities. This mock uses plain `coin::create_currency`.
- **No bridged wUSDC** — On mainnet/testnet there is also bridged wUSDC from Wormhole. This mock only creates the native-style mock.
- **Package address** — On mainnet, Circle's USDC lives at a fixed package address. On your local network it will be at a random address assigned at publish time.

## Common Patterns

### Mint USDC with PTB (preferred over `sui client call`)

```sh
sui client ptb \
  --move-call <PKG>::usdc::mint @<TREASURY_CAP_ID> <AMOUNT_MICRO_UNITS> <RECIPIENT> \
  --gas-budget 10000000
```

### Split a USDC coin and transfer part

```sh
# Split 100 USDC (100_000_000 micro-units) from a larger USDC coin and transfer
sui client ptb \
  --split-coins @<USDC_COIN_ID> "[100000000]" \
  --assign split_coin \
  --transfer-objects "[split_coin]" <RECIPIENT> \
  --gas-budget 5000000
```

### Check USDC coin type format

```sh
# The full coin type is <PACKAGE_ID>::usdc::USDC
# Always use the full type including the package ID
sui client balance --coin-type <PACKAGE_ID>::usdc::USDC
```

## Troubleshooting

- **`sui start` fails with "address already in use"** — A previous `sui start` is still running. Kill it, or use a different `--network.config` directory.
- **`sui client faucet` returns error** — The faucet may not be ready yet. Wait 5–10 seconds after `sui start` before requesting. Use `--url http://127.0.0.1:9123/v2/gas` to specify the local faucet explicitly.
- **Publish fails with "insufficient gas"** — Run `sui client faucet` first to get SUI. Check with `sui client gas`.
- **`coin::create_currency` panics at publish** — Ensure the `USDC` witness struct is `public struct USDC has drop {}` (Move 2024) and the module is named `usdc` (must match the struct name in lowercase).
- **Mint returns "Type not found"** — Use the full `<PACKAGE_ID>::usdc::USDC` type, not just `USDC`. On localnet, the package ID changes every re-genesis.
- **`--force-regenesis` lost my state** — That's intentional. Remove the flag for persistent local state, or use `sui genesis -f --with-faucet` once before `sui start`.

## Review Checklist

- Is the local network running before any publish/mint commands? (`sui start --with-faucet`)
- Does the Move module name `usdc` match the lowercase struct name `USDC`?
- Are USDC amounts expressed in micro-units (6 decimal places)? 1 USDC = 1_000_000 micro-units.
- Is the `TreasuryCap` stored securely? On local dev it's fine to hold it, but never transfer it to a shared address on testnet/mainnet.
- After `sui client publish`, did you capture the Package ID and TreasuryCap ID from the output?
- Is `sui client switch --env local` set before running any commands?
- Are you using `sui client ptb` for composed operations instead of legacy `sui client call`/`transfer`?

## Sources

- `https://docs.sui.io/getting-started/onboarding/local-network`
- `https://docs.sui.io/references/cli/client`
- `https://docs.sui.io/references/cli/ptb`
- `https://docs.sui.io/standards/coins`
- `https://suibyexamples.com/development-projects/launch-coin`