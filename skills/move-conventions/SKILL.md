---
name: move-conventions
description: Move language conventions for Aptos and Sui, with Sui 2024.beta guidance for modules, naming, object ownership, capabilities, events, display objects, init, upgrades, collections, strings, options, loop macros, and tests. Use when writing or modifying .move files or Move.toml.
---

# Move Conventions

Apply these conventions in Move projects. Detect the dialect first by inspecting `Move.toml` and existing source files. These rules are written for any coding agent, including Claude Code, Codex, Cursor, and Copilot.

## Dialect Detection

- Detect whether the project uses Aptos Move or Sui Move before generating code.
- Sui projects often use `edition = "2024.beta"` in `Move.toml`.
- Do not add a Sui framework dependency to `Move.toml` when the project uses Sui 2024.beta or later; Sui, Bridge, MoveStdlib, and SuiSystem are implicit.
- Do not use Aptos-specific patterns in Sui code: `acquires`, `move_to`, `move_from`, `borrow_global`, or the `signer` type.

## Naming

- Modules: `snake_case`, one module per file, filename matches module name.
- Prefix generic module names to avoid conflicts.
- Structs: `PascalCase`.
- Capability structs use the `Cap` suffix.
- Event structs use past tense names.
- Dynamic field key structs use the `Key` suffix.
- One-Time Witness structs use `ALL_UPPERCASE` matching the module name.
- Functions: `snake_case`.
- Getters are named after the field, not `get_*`.
- Mutable getters use `_mut`.
- Boolean checkers use `is_` or `has_`.
- Constants use `ALL_CAPS`.
- Error constants are `u64` values named `EPascalCase`.
- Type parameters are single uppercase letters in alphabetical order.
- Fields use `snake_case`.

## Module Organization in Sui

- Use Move 2024 statement-style module declarations: `module package::module_name;`.
- Prefer struct methods over older module-level function calls when the project uses Sui 2024 style.
- Do not import or call deprecated functions.
- Group related imports together.

## Function Design

- Do not use `public entry`. Functions should be either `public` or `entry`, not both.
- Prefer `public` for composability.
- Reserve `entry` for intentionally non-composable transaction entry points.
- Do not use deprecated `public(friend)` or `friend`; use `public(package)` for package-internal visibility.
- Parameter order: mutable objects, capabilities, immutable references and primitives, `Clock`, then `TxContext`.
- `TxContext` is always last.
- Use `&TxContext` when only reading and `&mut TxContext` when creating objects.
- Prefer functions that return values for Programmable Transaction Blocks rather than transferring internally.

## Struct Design

- Declare structs `public`.
- Keep fields private and provide getters.
- Object structs with `key` ability must have `id: UID` as the first field.
- Use Sui `Coin<T>` and `Balance<T>` for token or coin types.
- Use `let mut` for variables that are reassigned or mutably borrowed.
- Use `Option<T>` for optional fields.
- Use spread syntax for ignored fields when unpacking.

## Abilities

- No abilities: hot potato values that must be consumed by a specific function.
- `drop`: droppable witness types and temporary proofs.
- `copy, drop`: freely copyable simple data and event structs.
- `copy, drop, store`: storable copyable data embedded in objects.
- `key`: restricted objects with module-controlled transfer.
- `key, store`: publicly transferable objects.
- `key` types cannot have `copy` or `drop`.
- Omit `store` when custom transfer logic must remain inside the defining module.

## Error Handling

- Define error constants as `u64`, usually sequential from 0.
- Prefer returning `bool` from public check functions and let callers decide.
- Provide `has_*` or `is_*` checks before operations that might fail.
- Private helpers can use `assert!` internally.
- In tests, use `assert_eq!` instead of `assert!()` with abort codes.

## Object Ownership and Transfer in Sui

- Account-owned objects are the default.
- Shared objects use `share_object`.
- Immutable objects use `freeze_object`.
- Object-owned objects are owned by another object.
- Use `transfer::transfer<T: key>` internally.
- Use `transfer::public_transfer<T: key + store>` for objects transferable by any module.
- State transitions are one-way from owned to frozen or shared.
- On-chain objects are publicly readable. Do not store unencrypted secrets.

## Address Balances and Fungible Payments

- Prefer `Balance<T>` parameters and return values for fungible value that does not need object identity.
- For a payout whose destination is an address, deposit into the recipient's address balance with `balance::send_funds`.
- If the input is already a `Coin<T>`, deposit it with `coin::send_funds` instead of transferring the coin object.
- Create or transfer a `Coin<T>` only when the receiving API explicitly requires `Coin<T>` or the coin object's identity matters.
- Keep composable business logic returning `Balance<T>`; call `send_funds` only at an intentional payment boundary.

```move
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};

/// Default payout: no coin object is created for the recipient.
public fun pay<T>(payment: Balance<T>, recipient: address) {
    balance::send_funds(payment, recipient);
}

/// Compatibility boundary for an existing coin object.
public fun deposit_coin<T>(coin: Coin<T>, recipient: address) {
    coin::send_funds(coin, recipient);
}
```

## Sui Design Patterns

- Capabilities: use `Cap` suffix, gate privileged functions by requiring the capability parameter, and create capabilities in `init`.
- Witness: use a minimal struct as proof of module authority and consume it by value.
- One-Time Witness: use only `drop`, no fields, no generics, and an `ALL_UPPERCASE` name matching the module name.
- Publisher: claim with `sui::package::claim(otw, ctx)` in `init`.
- Prefer custom capability types over Publisher for admin roles.
- Hot potato: use a struct with no abilities, but do not include "Potato" in the type name.
- Config: wrap constants in public getter functions for cross-module access.
- Anchor: use a versioned base object with configuration in dynamic fields for upgradeable state.

## Collections

- Use `vector` for ordered lists.
- Use `VecSet` when uniqueness is required; do not compare `VecSet` instances.
- Use `VecMap` for key-value associations; do not compare `VecMap` instances.
- Use dynamic fields for large or heterogeneous data exceeding object size limits.
- Key types for dynamic fields need `copy, drop, store`.
- Deleting a parent UID orphans dynamic fields permanently. Use Bag or Table when appropriate.
- Do not expose mutable UID values publicly.

## Events and Display Objects

- Sui event structs must have `copy` and `drop`.
- Event structs should be internal to the emitting module.
- Name events in past tense and include identifiable object IDs for indexing.
- Do not include sender or timestamps in events; they are already in transaction metadata.
- Standard Display fields include `name`, `description`, `image_url`, `thumbnail_url`, `link`, `project_url`, and `creator`.
- Create Display objects in `init` alongside Publisher when needed.
- Call `update_version()` after Display modifications.

## Module Initializer

- The initializer must be named `init`.
- It is private and returns no values.
- Optional One-Time Witness parameter comes first.
- `TxContext` comes last.
- It runs once on publication, not on upgrades.
- Do not treat `init` as the only security boundary.

## Upgradeability

- Do not remove modules, public structs, or public function signatures in upgrades.
- You may change function implementations, `public(package)` functions, non-public `entry` functions, and private functions.
- Include version fields in shared objects and assert expected versions in mutation functions.
- Use dynamic fields for extensible configuration.

## Strings, Options, and Loops

- Default to `std::string::String`.
- Use `b"hello".to_string()` for string creation in Sui 2024 style.
- `length()` returns byte count, not character count.
- Use `Option<T>` instead of sentinel values.
- Use Sui loop macros such as `N.do!`, `vector::tabulate!`, `vec.do_ref!`, `vec.destroy!`, `fold!`, and `filter!` when they improve clarity and match project style.

## Testing and Documentation

- In `_tests` modules, do not prefix test functions with `test_`; use descriptive names.
- Use `tx_context::dummy()` for simple tests.
- Use `destroy(obj)` from `sui::test_utils` for cleanup.
- Do not clean up in expected-failure tests after the expected abort.
- Combine decorators as `#[test, expected_failure]`.
- Use `///` for doc comments and `//` for implementation comments.
