# Sui Address-Balance Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make address balances the default fungible-token payment and gas pattern in the Move and TypeScript Sui skills.

**Architecture:** Keep the language-level rule in `move-conventions`, retain the default SDK rules in `sui-sdk-js`, and place detailed SDK examples in a directly linked reference so `SKILL.md` stays below the repository's 500-line limit.

**Tech Stack:** Sui Move 2024, `@mysten/sui` v2 TypeScript SDK, Markdown skills.

## Global Constraints

- Prefer address-balance payments; use `Coin<T>` transfers only when an API requires a coin object or object identity.
- Preserve the existing untracked `.claude/` directory.
- Validate APIs against current Mysten Labs SDK documentation and Sui framework source.

---

### Task 1: Add Sui Move address-balance conventions

**Files:**
- Modify: `skills/move-conventions/SKILL.md`

**Interfaces:**
- Consumes: Sui framework `Balance<T>`, `Coin<T>`, `balance::send_funds`, and `coin::send_funds`.
- Produces: Prescriptive Move guidance and complete payout examples.

- [ ] **Step 1: Record the baseline failure**

Review the baseline agent response and confirm whether it defaults to `transfer::public_transfer(Coin<T>, recipient)`, omits `Balance<T>`, or lacks a rule for when coin objects are required.

- [ ] **Step 2: Add the minimal conventions**

Add an “Address Balances and Fungible Payments” section that:

```move
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};

public fun pay<T>(payment: Balance<T>, recipient: address) {
    balance::send_funds(payment, recipient);
}

public fun deposit_coin<T>(coin: Coin<T>, recipient: address) {
    coin::send_funds(coin, recipient);
}
```

State that APIs should accept/return `Balance<T>` unless object identity is required, and that `Coin<T>` creation or transfer is the compatibility path.

- [ ] **Step 3: Validate the Move skill**

Run:

```bash
python3 /Users/avbel/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/move-conventions
```

Expected: validator exits successfully.

### Task 2: Make address balances the TypeScript SDK default

**Files:**
- Modify: `skills/sui-sdk-js/SKILL.md`
- Modify: `skills/sui-sdk-js/references/advanced.md`
- Create: `skills/sui-sdk-js/references/coins-and-balances.md`

**Interfaces:**
- Consumes: `Transaction.balance`, `Transaction.coin`, `Transaction.setGasPayment`, `Transaction.setGasOwner`, `balance::send_funds`, and `coin::send_funds`.
- Produces: SDK examples for SUI, custom tokens, multiple recipients, explicit address-balance gas, and sponsored address-balance gas.

- [ ] **Step 1: Reorder and expand payment examples**

Lead with:

```ts
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [tx.balance({ balance: 1n * MIST_PER_SUI }), tx.pure.address(recipient)],
});
```

Add a custom-token version, a loop for multiple recipients, and an existing-coin deposit using `0x2::coin::send_funds`. Present `tx.coin()` with `transferObjects` only under an explicit “recipient requires `Coin<T>`” condition.

- [ ] **Step 2: Add address-balance gas guidance**

Document automatic selection and the explicit form:

```ts
const tx = new Transaction();
tx.setSender(senderAddress);
tx.setGasPayment([]);
```

Document sponsored gas:

```ts
const tx = new Transaction();
tx.setSender(userAddress);
tx.setGasOwner(sponsorAddress);
tx.setGasPayment([]);
```

State that `tx.gas` is unavailable with address-balance gas and portable transaction code should use `tx.balance()` or `tx.coin()`. Keep `useGasCoin: false` for sender-funded SUI in sponsored transactions.

- [ ] **Step 3: Validate the SDK skill**

Run:

```bash
python3 /Users/avbel/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/sui-sdk-js
```

Expected: validator exits successfully.

### Task 3: Verify the complete change

**Files:**
- Verify: `skills/move-conventions/SKILL.md`
- Verify: `skills/sui-sdk-js/SKILL.md`
- Verify: `skills/sui-sdk-js/references/advanced.md`

**Interfaces:**
- Consumes: The completed documentation changes.
- Produces: A clean, source-backed final diff.

- [ ] **Step 1: Run repository checks**

Run:

```bash
git diff --check
```

Expected: no output and exit status 0.

- [ ] **Step 2: Inspect scope**

Run:

```bash
git status --short
git diff -- skills/move-conventions/SKILL.md skills/sui-sdk-js/SKILL.md skills/sui-sdk-js/references/advanced.md
```

Expected: only the intended skill files, address-balance reference, and plan are new or modified; `.claude/` remains untouched.

- [ ] **Step 3: Forward-test the updated skills**

Ask a fresh agent to answer the same Sui payment and gas prompt while using both updated skills. Confirm its answer defaults to address-balance transfers, explains the `Coin<T>` exception, and uses `setGasPayment([])` for explicit or sponsored address-balance gas.
