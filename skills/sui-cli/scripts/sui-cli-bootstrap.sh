#!/bin/bash
set -e

scenario="${1:-envs}"

case "$scenario" in
  envs)
    description='Inspect and switch network environments.'
    commands='sui --version
sui client envs
sui client new-env --alias mainnet --rpc https://fullnode.mainnet.sui.io:443
sui client switch --env mainnet
sui client active-env
sui client active-address
sui client addresses
sui client chain-identifier'
    ;;
  transfer-ptb)
    description='Transfer SUI and arbitrary objects via PTB. Replace <RECIPIENT> with an alias or @0x... address.'
    commands='# Send 0.5 SUI
sui client ptb \
  --split-coins gas "[500000000]" \
  --assign coin \
  --transfer-objects "[coin]" <RECIPIENT> \
  --gas-budget 5000000

# Transfer the whole gas coin
sui client ptb \
  --transfer-objects "[gas]" <RECIPIENT> \
  --gas-budget 5000000

# Transfer an existing object
sui client ptb \
  --transfer-objects "[@<OBJECT_ID>]" <RECIPIENT> \
  --gas-budget 5000000'
    ;;
  publish-ptb)
    description='Publish a Move package and route the UpgradeCap to the sender. Run from the package root.'
    commands='sui move build
sui move test
sui client verify-bytecode-meter

sui client ptb \
  --move-call sui::tx_context::sender \
  --assign sender \
  --publish "." \
  --assign upgrade_cap \
  --transfer-objects "[upgrade_cap]" sender \
  --gas-budget 100000000'
    ;;
  move-call-ptb)
    description='Call a Move function with type args and inputs via PTB.'
    commands='# Replace <PKG>, <MODULE>, <FUN>, <T>, <OBJ_ID>, <U64_ARG>
sui client ptb \
  --move-call <PKG>::<MODULE>::<FUN> "<<T>>" @<OBJ_ID> <U64_ARG> \
  --gas-budget 10000000 \
  --preview

# Same call, but actually execute
sui client ptb \
  --move-call <PKG>::<MODULE>::<FUN> "<<T>>" @<OBJ_ID> <U64_ARG> \
  --gas-budget 10000000'
    ;;
  move-new)
    description='Scaffold a new Move package and run the standard checks.'
    commands='sui move new my_package
cd my_package
sui move build --lint
sui move test --coverage
sui move coverage summary --test'
    ;;
  keytool)
    description='Common sui keytool operations. Treat exported private keys as secrets.'
    commands='sui keytool list
sui keytool generate ed25519
sui keytool import "<MNEMONIC-OR-SUIPRIVKEY>" ed25519 --alias dev-key
sui keytool export --key-identity dev-key
sui keytool show <PATH-TO-KEY-FILE>
sui keytool sign --address <ADDR> --data <BASE64-TX-BYTES>
sui keytool decode-or-verify-tx --tx-bytes <BASE64-TX-BYTES>'
    ;;
  replay)
    description='Replay an on-chain transaction and optionally produce a Move trace.'
    commands='sui replay --digest <TX-DIGEST>
sui replay --digest <TX-DIGEST> --overwrite
sui replay --digest <TX-DIGEST> --trace --output-dir ./replays
sui analyze-trace -p ./replays/<TX-DIGEST>/trace.json.zst gas-profile -o ./replays'
    ;;
  *)
    echo "Usage: $0 [envs|transfer-ptb|publish-ptb|move-call-ptb|move-new|keytool|replay]" >&2
    exit 2
    ;;
esac

SCENARIO="$scenario" DESCRIPTION="$description" COMMANDS="$commands" python3 <<'PY'
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "description": os.environ["DESCRIPTION"],
    "commands": os.environ["COMMANDS"],
}, indent=2))
PY
