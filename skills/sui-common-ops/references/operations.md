# Operation Recipes

Detailed recipes for the `sui-common-ops` skill. All snippets assume the Node 26 gRPC skeleton, the minimal argument parser, and the Hard Rules from `SKILL.md`.

### 1. Balance for Address and Coin

Default coin type is SUI:

```js
const client = makeClient();
const [owner, coinType = '0x2::sui::SUI'] = process.argv.slice(2);

const { balance } = await client.core.getBalance({ owner, coinType });
printJson({
  owner,
  coinType,
  total: balance.balance,
  coinObjects: balance.coinBalance,
  addressBalance: balance.addressBalance,
});
```

For all balances:

```js
const { balances } = await client.core.listBalances({ owner });
printJson({ owner, balances });
```

### 2. Object by Object ID, Including Batch Mode

Single object:

```js
const { object } = await client.core.getObject({
  objectId,
  include: { content: true, display: true, owner: true, previousTransaction: true },
});
printJson(object);
```

Batch:

```js
const objectIds = process.argv.slice(2);
const { objects } = await client.core.getObjects({
  objectIds,
  include: { content: true, display: true, owner: true, previousTransaction: true },
});

printJson({
  requested: objectIds,
  objects: objects.map((object, index) => (object instanceof Error ? { objectId: objectIds[index], error: object.message } : object)),
});
```

### 3. Transaction Data by Digest

Fetch status, effects, balance changes, object changes/object types, and events:

```js
const { digest } = parseArgs();
const result = await client.core.getTransaction({
  digest,
  include: {
    transaction: true,
    effects: true,
    events: true,
    balanceChanges: true,
    objectTypes: true,
  },
});

const transaction = result.Transaction ?? result.FailedTransaction ?? result;
printJson({
  digest,
  status: transaction.status,
  effects: transaction.effects,
  balanceChanges: transaction.balanceChanges,
  objectChanges: {
    created: transaction.effects?.created,
    mutated: transaction.effects?.mutated,
    deleted: transaction.effects?.deleted,
    wrapped: transaction.effects?.wrapped,
    unwrapped: transaction.effects?.unwrapped,
  },
  events: transaction.events,
  raw: result,
});
```

After submitting a transaction, wait for availability before reading:

```js
await client.core.waitForTransaction({ digest, timeout: 60_000 });
```

### 4. Dynamic Object Field by Key

Serialize the field name with BCS. The field name type must match the Move dynamic field key exactly:

```js
import { bcs } from '@mysten/sui/bcs';

function dynamicFieldName(type, value) {
  switch (type) {
    case 'address':
    case '0x2::object::ID':
      return { type, bcs: bcs.Address.serialize(value).toBytes() };
    case 'u64':
      return { type, bcs: bcs.u64().serialize(BigInt(value)).toBytes() };
    case 'string':
      return { type: '0x1::string::String', bcs: bcs.string().serialize(value).toBytes() };
    default:
      throw new Error(`Unsupported dynamic field key type: ${type}. Add the exact BCS serializer for this key.`);
  }
}

const { parentId, keyType, keyValue } = parseArgs();
const { object } = await client.core.getDynamicObjectField({
  parentId,
  name: dynamicFieldName(keyType, keyValue),
  include: { content: true, owner: true, previousTransaction: true },
});
printJson(object);
```

Use `client.core.getDynamicField(...)` instead when the field value is not an object.

### 5. List Dynamic Object Fields

Paginate until `cursor` is empty:

```js
const fields = [];
let cursor;

do {
  const page = await client.core.listDynamicFields({
    parentId,
    cursor,
    limit: 50,
  });
  fields.push(...page.dynamicFields);
  cursor = page.cursor;
} while (cursor);

printJson({ parentId, fields });
```

### 6. Build PTB and Prepare Base64 Transaction Data

Use the `sui-sdk-js` skill when translating the user's request into `Transaction` commands. The common handoff shape is:

```js
import { Transaction } from '@mysten/sui/transactions';
import { MIST_PER_SUI, toBase64 } from '@mysten/sui/utils';

const client = makeClient();
const tx = new Transaction();
tx.setSender(senderAddress);
const amount = amountMist === undefined ? 1n * MIST_PER_SUI : BigInt(amountMist);

// Example: send SUI to an address balance.
tx.moveCall({
  target: '0x2::balance::send_funds',
  typeArguments: ['0x2::sui::SUI'],
  arguments: [tx.balance({ balance: amount }), tx.pure.address(recipient)],
});

const bytes = await tx.build({ client });
const txBytes = toBase64(bytes);

printJson({
  sender: senderAddress,
  txBytes,
  inspectCommand: `sui keytool decode-or-verify-tx --tx-bytes '${txBytes}' --json`,
  executeCommand: `sui client serialized-tx '${txBytes}' --sender <ALIAS_OR_ADDRESS> --json`,
});
```

When presenting PTB bytes to the user, explain:

- The bytes are unsigned transaction data.
- The user should inspect before signing.
- The user can execute with an address already present in their Sui CLI keystore using `sui client serialized-tx`.
- The agent should not receive the private key.

For transaction kind bytes, use:

```js
const kindBytes = toBase64(await tx.build({ client, onlyTransactionKind: true }));
```

Then tell the user to let CLI fill gas/sender:

```sh
sui client serialized-tx-kind '<KIND_BYTES>' --sender <ALIAS_OR_ADDRESS> --gas-budget <MIST> --serialize-unsigned-transaction --json
```

### 7. Current Blockchain Data

Use stable Core calls first when an SDK helper is already available:

```js
const [{ referenceGasPrice }, { systemState }, { chainIdentifier }] = await Promise.all([
  client.core.getReferenceGasPrice(),
  client.core.getCurrentSystemState(),
  client.core.getChainIdentifier(),
]);

const latestCheckpointSequenceNumber =
  typeof client.core.getLatestCheckpointSequenceNumber === 'function'
    ? await client.core.getLatestCheckpointSequenceNumber()
    : null;

printJson({
  chainIdentifier,
  referenceGasPrice,
  epoch: systemState.epoch,
  protocolVersion: systemState.protocolVersion,
  systemState,
  latestCheckpointSequenceNumber,
});
```

If the installed SDK does not expose a latest-checkpoint helper, omit that field instead of guessing an API. The CLI can still show the active chain identifier:

```sh
sui client chain-identifier --json
```

For a no-npm Sui CLI answer on mainnet, avoid the noisy discovery route through `sui client object 0x5` and `sui client dynamic-field 0x5`. Query the parsed system-state inner dynamic-field object and clock directly:

```sh
sui client chain-identifier --json
sui client object 0x5b890eaf2abcfa2ab90b77b8e6f3d5d8609586c3e583baf3dccd5af17edf48d1 --json
sui client object 0x6 --json
```

Read current data from these JSON paths:

- `system.content.value.epoch`
- `system.content.value.epoch_start_timestamp_ms`
- `system.content.value.reference_gas_price`
- `system.content.value.protocol_version`
- `system.content.value.safe_mode`
- `system.content.value.system_state_version`
- `system.content.value.parameters.epoch_duration_ms`
- `system.content.value.parameters.min_validator_count`
- `system.content.value.parameters.max_validator_count`
- `system.content.value.validators.active_validators.length`
- `system.content.value.validators.total_stake`
- `system.content.value.storage_fund`
- `system.content.value.stake_subsidy`
- `clock.content.timestamp_ms`

The direct system object is the current mainnet `Field<u64, SuiSystemStateInnerV2>` for the system object. If it fails on another network or after a system-state layout change, fall back to:

```sh
sui client dynamic-field 0x5 --json
```

Then query the `fieldId` whose `valueType` ends with `SuiSystemStateInnerV2`.

### 8. Dry Run PTB or Base64 Transaction Bytes

For a PTB built in recipe 6, simulate before presenting execution commands:

```js
const dryRun = await client.core.simulateTransaction({
  transaction: tx,
  include: {
    effects: true,
    balanceChanges: true,
    commandResults: true,
  },
});

printJson({
  sender: senderAddress,
  dryRun,
  txBytes,
  inspectCommand: `sui keytool decode-or-verify-tx --tx-bytes '${txBytes}' --json`,
  dryRunCommand: `sui client serialized-tx '${txBytes}' --sender <ALIAS_OR_ADDRESS> --dry-run --json`,
  executeCommand: `sui client serialized-tx '${txBytes}' --sender <ALIAS_OR_ADDRESS> --json`,
});
```

For base64 transaction data provided by the user, do not decode it by hand. Use Sui CLI:

```sh
sui keytool decode-or-verify-tx --tx-bytes '<TX_BYTES>' --json
sui client serialized-tx '<TX_BYTES>' --sender <ALIAS_OR_ADDRESS> --dry-run --json
```

For transaction kind bytes, let CLI fill gas/sender for the dry run:

```sh
sui client serialized-tx-kind '<KIND_BYTES>' --sender <ALIAS_OR_ADDRESS> --gas-budget <MIST> --dry-run --json
```

### 9. Disassembled Package Code by Package ID

For a no-npm CLI answer, use the package disassembly helper. It fetches the package object, extracts each `content.Package.module_map` byte array to a `.mv` file, runs `sui move disassemble`, and prints JSON paths to the generated files:

```bash
bash /mnt/skills/user/sui-common-ops/scripts/sui-disassemble-package.sh <PACKAGE_ID> [OUTPUT_DIR]
SUI_CLIENT_ENV=testnet bash /mnt/skills/user/sui-common-ops/scripts/sui-disassemble-package.sh <PACKAGE_ID> [OUTPUT_DIR]
```

Present the module names and link or quote only the relevant disassembled files. The output is bytecode disassembly, not original author source.

Use the SDK path when a project already has an executable Sui gRPC helper. Packages are objects, but package code requires package-content include options. Use `getObject` with the package ID as `objectId` and request content explicitly:

```js
const { packageId } = parseArgs();
const { object } = await client.core.getObject({
  objectId: packageId,
  include: {
    content: true,
    json: true,
  },
});

const content = object.content ?? object;
const disassembled = content.disassembled ?? content.modules ?? content;

printJson({
  packageId,
  version: object.version,
  digest: object.digest,
  previousTransaction: object.previousTransaction,
  moduleNames: disassembled && typeof disassembled === 'object' ? Object.keys(disassembled) : [],
  disassembled,
  raw: object,
});
```

Some clients return raw module bytes instead of disassembled text. In that case, write each module byte array to `<module>.mv` and run `sui move disassemble <module>.mv`.

If the user needs raw module bytes in addition to disassembled code, add `objectBcs: true` to the include options:

```js
const { object } = await client.core.getObject({
  objectId: packageId,
  include: {
    content: true,
    json: true,
    objectBcs: true,
  },
});
```
