#!/bin/bash
set -e

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

scenario="${1:-start}"

case "$scenario" in
  start)
    description='Start a local Sui network with faucet (fresh genesis).'
    commands='# Start local network (destroys previous state)
RUST_LOG="off,sui_node=info" sui start --with-faucet --force-regenesis

# In a new terminal, switch CLI to local network
sui client new-env --alias local --rpc http://127.0.0.1:9000
sui client switch --env local

# Verify connection
sui client active-env
sui client active-address'
    ;;
  publish-usdc)
    description='Create and publish a mock USDC coin (6 decimals) to the local network.'
    commands='# Scaffold the Move package
mkdir -p /tmp/usdc-coin && cd /tmp/usdc-coin
sui move new usdc

# Write the USDC coin module (kept identical to SKILL.md)
cat > sources/usdc.move << '\''MOVE'\''
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
MOVE

# Build and publish
cd /tmp/usdc-coin
sui move build
sui client publish --gas-budget 100000000 .

# NOTE: Capture PACKAGE_ID and TREASURY_CAP_ID from the publish output!'
    ;;
  faucet)
    description='Request SUI from the local faucet to pay for gas.'
    commands='# Request SUI from the local faucet
sui client faucet

# Request for a specific address or alias
sui client faucet --address <ADDRESS>

# Check gas coins received
sui client gas

# Check total SUI balance
sui client balance'
    ;;
  mint-usdc)
    description='Mint additional USDC to any address using the TreasuryCap.'
    commands='# Mint 10 000 USDC (10_000 * 10^6 = 10_000_000_000 micro-units)
# Replace <PACKAGE_ID> and <TREASURY_CAP_ID> with values from publish output
sui client call \\
  --package <PACKAGE_ID> \\
  --module usdc \\
  --function mint \\
  --args <TREASURY_CAP_ID> 10000000000 <RECIPIENT_ADDRESS> \\
  --gas-budget 10000000

# Alternative: using PTB syntax
sui client ptb \\
  --move-call <PACKAGE_ID>::usdc::mint \\
  @<TREASURY_CAP_ID> 10000000000 <RECIPIENT> \\
  --gas-budget 10000000'
    ;;
  balance)
    description='Check SUI and USDC balances.'
    commands='# Check all balances
sui client balance

# Check USDC balance specifically (replace with your package ID)
sui client balance --coin-type <PACKAGE_ID>::usdc::USDC

# List all objects owned by active address
sui client objects'
    ;;
  clean)
    description='Stop local network and remove all local state.'
    commands='# Stop the local network (Ctrl+C in the sui start terminal)

# Remove all local Sui config, keystore, and genesis data
rm -rf ~/.sui/sui_config

# Remove the temporary USDC coin package
rm -rf /tmp/usdc-coin'
    ;;
  *)
    echo "Usage: $0 [start|publish-usdc|faucet,mint-usdc,balance|clean]" >&2
    exit 2
    ;;
esac

cat > "$tmp_dir/emit-json.py" <<'PY'
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "description": os.environ["DESCRIPTION"],
    "commands": os.environ["COMMANDS"],
}, indent=2))
PY

SCENARIO="$scenario" DESCRIPTION="$description" COMMANDS="$commands" python3 "$tmp_dir/emit-json.py"