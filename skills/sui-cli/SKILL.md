---
name: sui-cli
description: Use when working with the Sui CLI from a terminal: managing network environments and addresses, querying coins/objects/balances, calling Move functions and building Programmable Transaction Blocks (`sui client ptb`), publishing and upgrading Move packages, managing keys with `sui keytool`, building/testing Move code with `sui move`, replaying transactions with `sui replay`, and validator operations with `sui validator`.
---

# Sui CLI

Use these conventions for the Sui command line tools published by Mysten Labs.

## Source Baseline

- Authoritative reference: <https://docs.sui.io/references/cli> and the per-command pages it links (`/references/cli/client`, `/client/ptb`, `/keytool`, `/move`, `/replay`, `/validator`, `/external-signers`, `/trace-analysis`).
- Verify a local install before using examples: `sui --version`. Manage versions with `suiup` (<https://github.com/MystenLabs/suiup>) rather than ad-hoc binary swaps.
- Enable the `tracing` feature when building the CLI from source if you need Move test coverage or the Move debugger; without it `sui move coverage` and trace-based debugging are unavailable.
- Append `--json` to most commands to get machine-readable output (useful for scripts and large result sets).

## Command Groups

The Sui CLI is grouped by feature; the seven groups documented upstream are:

- `sui client` — interact with a Sui network (addresses, envs, coins, objects, Move calls, publish/upgrade).
- `sui client ptb` — build and execute Programmable Transaction Blocks directly from the shell.
- `sui external-keys` — drive external signers (Ledger, YubiKey, AWS KMS) via the rust-signers integration; introduced in CLI 1.66.2.
- `sui keytool` — cryptographic utilities: generate/import/export keys, sign data, manage MultiSig, work with zkLogin.
- `sui move` — work with Move source: `new`, `build`, `test`, `coverage`, `migrate`, `summary`, `update-deps`, `disassemble`.
- `sui replay` — replay an on-chain transaction locally and optionally produce a trace for the debugger/profiler.
- `sui validator` — validator-only operations (candidacy, committee, gas price, metadata, bridge committee).

Use `sui <group> --help` for the authoritative subcommand list — the CLI evolves faster than reference pages.

## Environments and Addresses

```sh
sui client envs                                       # list configured RPC envs
sui client new-env --alias mainnet \
  --rpc https://fullnode.mainnet.sui.io:443           # add an env
sui client switch --env mainnet                       # set active env
sui client active-env                                 # show active env
sui client active-address                             # show address used by default
sui client addresses                                  # list keystore addresses + aliases
sui client new-address ed25519                        # generate new key in keystore
sui client switch --address <alias-or-0x...>          # change active address
```

- Config files live in `~/.sui/sui_config/` (`client.yaml`, `sui.keystore`, aliases).
- Use aliases instead of raw `0x` addresses when scripting against your own wallet; aliases survive re-imports and are easier to audit.
- For production-targeting commands, switch env explicitly (`--client.env`) instead of relying on the active env.

## Gas, Coins, and Balances

```sh
sui client faucet                                     # request gas on devnet/testnet/local
sui client faucet --url <local-faucet-url>            # custom faucet endpoint
sui client gas                                        # list gas coins for active address
sui client balance                                    # list balances for active address
sui client balance --coin-type 0x2::sui::SUI          # filter by coin type
```

- `faucet` is unavailable on Mainnet; do not script it into mainnet workflows.
- `gas` lists the gas-eligible SUI coins; `balance` aggregates by coin type and is the right command for non-SUI tokens.

## Objects and Dynamic Fields

```sh
sui client objects                                    # objects owned by active address
sui client objects <ADDRESS-OR-ALIAS>                 # objects owned by another address
sui client object <OBJECT-ID>                         # full object info
sui client object <OBJECT-ID> --json                  # JSON for tooling
sui client dynamic-field <PARENT-OBJECT-ID>           # list dynamic fields under a parent
sui client chain-identifier                           # chain id served by the current RPC
```

- Object IDs are 32-byte hex strings prefixed with `0x`. PTBs require an `@` prefix on object IDs; the standalone `object`/`objects` commands do not.
- `dynamic-field` is paginated; the JSON response carries `hasNextPage` and `nextCursor`.

## Transactions: Prefer PTBs

The legacy single-purpose commands (`pay`, `pay-sui`, `pay-all-sui`, `transfer`, `transfer-sui`, `merge-coin`, `split-coin`, `call`) still exist, but the upstream docs explicitly recommend `sui client ptb` for all new transaction work because it mirrors the SDK transaction builder and composes multiple operations atomically.

```sh
# Split 0.5 SUI from gas and transfer to an alias
sui client ptb \
  --split-coins gas "[500000000]" \
  --assign coin \
  --transfer-objects "[coin]" eloquent-amber \
  --gas-budget 5000000

# Transfer the entire gas coin
sui client ptb \
  --transfer-objects "[gas]" eloquent-amber \
  --gas-budget 5000000

# Transfer an arbitrary object by ID
sui client ptb \
  --transfer-objects "[@0xabc...]" eloquent-amber \
  --gas-budget 5000000

# Call a Move function with explicit type args
sui client ptb \
  --move-call 0x1::option::is_none "<u64>" my_var \
  --assign my_var none \
  --gas-budget 50000000
```

### PTB Syntax Rules

- `--assign <name> <value-or-result>` binds either a literal value or the previous command's result to a name. `coins.0`, `coins.1`, etc. index into a result that is a vector/array.
- Addresses and object IDs inside PTBs require an `@` prefix (`@0xabc...`); aliases may be passed without `@`.
- Strings are single-quoted on the shell to survive double-quote stripping: `'"hello"'`.
- Vectors use literal `vector[...]` syntax (or `"[...]"` for inputs that are already arrays of refs).
- Options use `none` and `some(value)` keywords.
- `gas` refers to the gas coin and may only be moved by value via `transfer-objects`.
- Name resolution shortcuts work for common packages: `sui`, `std`, `deepbook` resolve to `0x2`, `0x1`, `0xdee9`.
- Reserved words you cannot use as variable names: `address`, `bool`, `vector`, `some`, `none`, `gas`, `u8`, `u16`, `u32`, `u64`, `u128`, `u256`.
- Use `--preview` to dump the planned transaction list without executing, and `--dry-run` to simulate execution and see effects/gas without paying.
- Use `--summary` for a compact result instead of the full effects table.

### Shell Quoting Gotchas

- `zsh` requires square brackets to be quoted (`"[1,2,3]"`); `bash` accepts them unquoted. Default to quoting for portability.
- Windows shells often need an extra layer of quoting around assignment values: `--assign "forge @<FORGE-ID>"`.

## Publishing and Upgrading Packages

```sh
# Inside a Move package directory (next to Move.toml)
sui move build
sui move test
sui client verify-bytecode-meter                      # confirm bytecode fits limits
sui client publish --gas-budget 100000000 .           # legacy single-purpose form

# PTB form: publish and route UpgradeCap explicitly
sui client ptb \
  --move-call sui::tx_context::sender --assign sender \
  --publish "." --assign upgrade_cap \
  --transfer-objects "[upgrade_cap]" sender \
  --gas-budget 100000000

sui client upgrade --upgrade-capability <CAP-ID> \
  --gas-budget 100000000 .
sui client verify-source                              # diff local package vs on-chain
```

- The PTB form is the correct shape when the deploy must do more than publish (e.g. publish then call init, or burn the `UpgradeCap` with `package::make_immutable`).
- Set `--gas-budget` explicitly on older CLI versions; recent versions infer a budget when omitted.
- `verify-bytecode-meter` returns module/function metering numbers — use it before pushing big modules to mainnet.

## sui keytool

```sh
sui keytool list                                      # list keys in sui.keystore
sui keytool generate ed25519                          # generate ed25519 keypair file
sui keytool import "<mnemonic-or-suiprivkey...>" ed25519
sui keytool export --key-identity <alias-or-address>  # exports suiprivkey... Bech32 string
sui keytool show <keypair-file>                       # inspect a key file
sui keytool sign --address <addr> --data <base64-tx-bytes>
sui keytool decode-or-verify-tx --tx-bytes <base64>   # decode/verify a tx
sui keytool multi-sig-address ...                     # build a MultiSig address
sui keytool multi-sig-combine-partial-sig ...         # assemble MultiSig signature
sui keytool zk-login-sign-and-execute-tx ...          # zkLogin signing workflow
```

- Key scheme flags: `ed25519`, `secp256k1`, `secp256r1`. Default derivation paths are `m/44'/784'/0'/0'/0'` (ed25519), `m/54'/784'/0'/0/0` (secp256k1), `m/74'/784'/0'/0/0` (secp256r1).
- Hex-encoded private keys are deprecated; use Bech32 `suiprivkey...` strings for import/export. `sui keytool convert` upgrades legacy hex/base64 keys.
- For production signing, prefer hardware backed signers via `sui external-keys` (Ledger, YubiKey) or `sui keytool sign-kms` (AWS KMS) over keystore files.
- `--keystore-path` overrides the default `~/.sui/sui_config/sui.keystore` location, useful in CI.

## sui move

```sh
sui move new <name>                                   # scaffold Move.toml + sources/tests
sui move build                                        # compile
sui move build --lint                                 # extra linters
sui move build --warnings-are-errors                  # CI-strict build
sui move test                                         # run unit tests
sui move test --coverage                              # collect coverage (needs tracing feature)
sui move coverage summary --test                      # summarize after a --coverage run
sui move coverage source --module <name>              # per-module source coverage
sui move disassemble <module>                         # inspect compiled bytecode
sui move migrate                                      # auto-migrate package to Move 2024
sui move summary                                      # serialized package summary
sui move update-deps                                  # re-pin Move.toml dependencies
```

- Run `sui move` commands from a directory containing `Move.toml`, or pass `-p <path>`.
- `--default-move-edition 2024.beta` / `--default-move-flavor sui` set defaults only when the package does not specify them.
- `--no-lint` disables the standard lint passes; `--lint` opts into extra ones.
- Coverage and the Move debugger require a CLI built with the `tracing` feature.

## sui replay

```sh
sui replay --digest <TX-DIGEST>                       # replay locally, compare to chain
sui replay --digest <TX-DIGEST> --overwrite           # re-replay into existing dir
sui replay --digest <TX-DIGEST> --trace               # emit Move debugger / profiler trace
sui replay --digest <TX-DIGEST> --output-dir <path>   # custom output location
```

- Output defaults to `./.replay/<digest>/`. The directory is not overwritten on subsequent runs without `--overwrite`.
- The legacy `sui client replay-transaction|replay-batch|replay-checkpoint` commands are deprecated; use `sui replay` instead.
- Combine with `sui analyze-trace -p <trace> gas-profile` and `speedscope` to inspect gas usage per Move call.

## sui validator

```sh
sui validator make-validator-info ...
sui validator become-candidate <validator-info>
sui validator join-committee
sui validator leave-committee
sui validator display-metadata [<validator-address>]
sui validator update-metadata <field> <value>
sui validator update-gas-price <mist-per-unit>
sui validator report-validator <validator-address>
sui validator serialize-payload-pop                   # offline Proof-of-Possession signing
sui validator display-gas-price-update-raw-txn ...
sui validator register-bridge-committee ...
sui validator update-bridge-committee-node-url ...
```

- Most subcommands construct on-chain transactions signed by the validator address; treat them like normal mutating calls and budget gas accordingly.
- `serialize-payload-pop` is the right entry point when the authority protocol keypair must sign the Proof-of-Possession offline.

## External Signers (Ledger / YubiKey / KMS)

- Available from CLI 1.66.2 onwards. The CLI talks to signer binaries (`ledger-signer`, `yubikey-signer`, `aws-signer`) over a JSON-RPC pipe on stdin/stdout — see <https://github.com/MystenLabs/rust-signers>.
- Use `sui external-keys --help` to enumerate add/list/use subcommands available on your installed version; signer support and flags evolve quickly.
- Prefer external signers over `sui.keystore` for any address holding non-trivial funds or used for package upgrades.

## Common Operations Cheat Sheet

```sh
# Daily dev loop on Devnet
sui client switch --env devnet
sui client faucet
sui move build && sui move test
sui client publish --gas-budget 100000000 .

# Send 1 SUI to an alias
sui client ptb \
  --split-coins gas "[1000000000]" --assign coin \
  --transfer-objects "[coin]" <alias> \
  --gas-budget 5000000

# Move-call a function with one object input and a u64 arg
sui client ptb \
  --move-call <PKG>::module::fun "<T>" @<OBJ_ID> 42 \
  --gas-budget 10000000

# Read a single object as JSON for piping into jq
sui client object <OBJECT-ID> --json | jq '.content.fields'
```

## Helper Script

The bootstrap script prints starter snippets without loading additional context. Each scenario is independent.

```bash
bash /mnt/skills/user/sui-cli/scripts/sui-cli-bootstrap.sh envs
bash /mnt/skills/user/sui-cli/scripts/sui-cli-bootstrap.sh transfer-ptb
bash /mnt/skills/user/sui-cli/scripts/sui-cli-bootstrap.sh publish-ptb
bash /mnt/skills/user/sui-cli/scripts/sui-cli-bootstrap.sh move-call-ptb
bash /mnt/skills/user/sui-cli/scripts/sui-cli-bootstrap.sh move-new
bash /mnt/skills/user/sui-cli/scripts/sui-cli-bootstrap.sh keytool
bash /mnt/skills/user/sui-cli/scripts/sui-cli-bootstrap.sh replay
```

The script prints JSON with `scenario`, `description`, and `commands` fields.

## Review Checklist

- Is the active env (`sui client active-env`) the intended network before any mutating command?
- For transfers and Move calls, is `sui client ptb` used instead of the legacy `pay*`/`transfer*`/`call` commands?
- Are object IDs inside PTBs prefixed with `@`, and are bracketed arguments quoted for cross-shell safety?
- Does `--gas-budget` reflect realistic limits (or is it intentionally omitted on a recent CLI)?
- For publishes via PTB, is the resulting `UpgradeCap` either transferred to the sender or made immutable explicitly?
- For keystore work, are private keys handled as Bech32 `suiprivkey...` strings rather than deprecated hex?
- Is mainnet signing done through `sui external-keys` (Ledger/YubiKey/KMS) when funds or upgrades are non-trivial?
- For replay/profiling work, is the CLI built with the `tracing` feature, and is the output directory managed with `--overwrite` only when intended?
- Are `sui validator` commands run from the validator address, with the expected env and gas budget?

## Sources

- `https://docs.sui.io/references/cli`
- `https://docs.sui.io/references/cli/client`
- `https://docs.sui.io/references/cli/ptb`
- `https://docs.sui.io/references/cli/keytool`
- `https://docs.sui.io/references/cli/move`
- `https://docs.sui.io/references/cli/replay`
- `https://docs.sui.io/references/cli/validator`
- `https://docs.sui.io/references/cli/external-signers`
- `https://docs.sui.io/references/cli/trace-analysis`
- `https://github.com/MystenLabs/suiup`
- `https://github.com/MystenLabs/rust-signers`
