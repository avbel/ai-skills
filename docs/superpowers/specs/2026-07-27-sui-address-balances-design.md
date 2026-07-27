# Sui Address-Balance Guidance

## Goal

Update `move-conventions` and `sui-sdk-js` so agents use address balances for ordinary fungible-token payments and gas, while retaining coin-object guidance for APIs that require `Coin<T>`.

## `move-conventions`

Add concise Sui Move guidance that:

- Prefers `Balance<T>` parameters and return values for fungible value that does not need object identity.
- Sends payments with `balance::send_funds(balance, recipient)`.
- Deposits an existing `Coin<T>` into an address balance with `coin::send_funds(coin, recipient)`.
- Creates or transfers `Coin<T>` only when the receiving API requires a coin object or object identity.
- Shows a complete Move example for a generic balance payout and a coin-to-address-balance boundary.

## `sui-sdk-js`

Revise the coins and balances guidance so:

- `tx.balance()` with `0x2::balance::send_funds` is the default SUI and custom-token payment pattern.
- `tx.coin()` with `transferObjects` is presented as the fallback when the recipient needs `Coin<T>`.
- Examples cover SUI, custom tokens, multiple recipients, and depositing an existing coin object with `0x2::coin::send_funds`.
- Manual split and merge operations remain available but are explicitly non-default.

Add gas guidance that:

- Explains the SDK default: use the sender's SUI address balance first and fall back to coin objects when necessary.
- Uses `tx.setGasPayment([])` to require address-balance gas explicitly.
- Warns that `tx.gas` is unavailable with address-balance gas; portable transaction code should use `tx.balance()` or `tx.coin()`.
- Shows sponsored address-balance gas with `setGasOwner(sponsorAddress)` and `setGasPayment([])`.
- Keeps `useGasCoin: false` for sender-funded SUI in sponsored transactions.

## Validation

- Run the repository skill validator for both skill directories.
- Check Markdown and patch whitespace with `git diff --check`.
- Compare all API names and behavioral claims with the current Mysten Labs SDK documentation and Sui framework source.
- Inspect the final diff to ensure unrelated files, including the existing untracked `.claude/` directory, remain untouched.
