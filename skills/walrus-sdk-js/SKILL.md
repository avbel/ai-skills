---
name: walrus-sdk-js
description: Walrus TypeScript SDK conventions for JavaScript and TypeScript. Use when adding, reviewing, or debugging @mysten/walrus client extension setup, WalrusFile reads/writes, blob reads/writes, upload relay, resumable uploads, storage epochs, WASM/browser setup, or Walrus SDK migration work.
---

# Walrus TypeScript SDK

Use this skill for JavaScript and TypeScript projects that interact with Walrus through `@mysten/walrus`.

Primary source: Mysten Labs Walrus SDK docs at `https://sdk.mystenlabs.com/walrus`.

## Current Defaults

- Install `@mysten/walrus` with `@mysten/sui`.
- Use the current Sui client extension pattern: create a Sui client, then call `$extend(walrus())`.
- The Mysten SDK packages are ESM-only. Ensure `package.json` has `"type": "module"` and TypeScript uses `moduleResolution` compatible with ESM, such as `NodeNext`, `Node16`, or `Bundler`.
- For new code, prefer `SuiGrpcClient` unless the surrounding project already uses GraphQL or JSON-RPC.
- The Walrus extension infers network from the Sui client. Do not pass `network` to `walrus()`.
- The SDK includes the package/object IDs needed for Testnet. Configure IDs manually only when targeting another Walrus deployment or updated contracts.

## Operational Fit

The Walrus TypeScript SDK can talk directly to Walrus storage nodes or use a Walrus upload relay. Direct storage-node reads and writes are request-heavy: the docs cite about 2200 requests to write a blob and about 335 requests to read a blob. The upload relay reduces write complexity, but SDK reads still require many requests.

For many production apps, prefer publishers and aggregators. Use this SDK directly when the app must interact with Walrus itself or the user must directly pay for storage.

## Install

```bash
pnpm add @mysten/walrus @mysten/sui
```

Use the repo's actual package manager.

## Client Setup

```ts
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { walrus } from '@mysten/walrus';

export const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',
}).$extend(walrus());
```

Migration note: old code that creates `new WalrusClient({ suiRpcUrl, network })` should be migrated to the extension pattern. `WalrusClient.experimental_asClientExtension()` was removed.

## WalrusFile Reads

Prefer the high-level `WalrusFile` API when the caller is dealing with files. `getFiles` accepts blob IDs and quilt IDs, and returns `WalrusFile` values:

```ts
const [file] = await client.walrus.getFiles({
  ids: [blobIdOrQuiltId],
});

const bytes = await file.bytes();
const text = await file.text();
const json = await file.json();

const identifier = await file.getIdentifier();
const tags = await file.getTags();
```

Read files in batches when possible. This lets the client be more efficient when multiple files come from the same quilt.

## WalrusBlob Reads

Use `getBlob` when you have a blob ID and need blob/quilt-level operations:

```ts
const blob = await client.walrus.getBlob({ blobId });

const allFiles = await blob.files();
const [readme] = await blob.files({ identifiers: ['README.md'] });
const textFiles = await blob.files({
  tags: [{ 'content-type': 'text/plain' }],
});
const filesById = await blob.files({ ids: [quiltId] });
```

Use `readBlob` for raw bytes:

```ts
const bytes = await client.walrus.readBlob({ blobId });
```

## Creating WalrusFile Values

Use `WalrusFile.from` for `Uint8Array`, `Blob`, or encoded strings:

```ts
import { WalrusFile } from '@mysten/walrus';

const binaryFile = WalrusFile.from({
  contents: new Uint8Array([1, 2, 3]),
  identifier: 'file.bin',
});

const textFile = WalrusFile.from({
  contents: new TextEncoder().encode('Hello from Walrus\n'),
  identifier: 'README.md',
  tags: {
    'content-type': 'text/plain',
  },
});
```

The current quilt encoding is less efficient for a single file, so write multiple files together when that matches the product model. For single raw payloads, consider `writeBlob`.

## Writing Files

`writeFiles` stores files, signs/registers/certifies the blob, and uploads data:

```ts
const results = await client.walrus.writeFiles({
  files: [binaryFile, textFile],
  epochs: 3,
  deletable: true,
  signer: keypair,
});
```

The signer pays transaction and storage fees. It needs enough SUI for registration/certification transactions and enough WAL for storage across the requested epochs plus write fees. Costs depend on blob size and current gas/storage prices.

Useful options include:

- `files`: `WalrusFile[]`.
- `epochs`: number of epochs to store the blob.
- `deletable`: whether the blob can be deleted.
- `signer`: signer that pays fees.
- `owner`: optional owner address; defaults to signer address.
- `attributes`: optional blob attributes.
- `signal`: optional `AbortSignal`.
- `onStep`: persist upload progress.
- `resume`: previously persisted step for crash recovery.

## Browser Upload Flow

Browser wallets may open signature popups. If registration/certification transactions are not triggered by direct user gestures, browsers can block those popups. For browser UX, split the flow into explicit user actions with `writeFilesFlow`:

```ts
const flow = client.walrus.writeFilesFlow({
  files: [textFile],
});

await flow.encode();

const registerTx = flow.register({
  epochs: 3,
  owner: currentAccount.address,
  deletable: true,
});

const registerResult = await signAndExecuteTransaction({
  transaction: registerTx,
});

if (registerResult.$kind === 'FailedTransaction') {
  throw new Error(`Registration failed: ${registerResult.FailedTransaction.status.error?.message}`);
}
```

Continue with the flow's upload and certify steps according to the current project wallet API. Always check transaction status after wallet signing.

## Resumable Uploads

`writeBlob` and `writeFiles` support `onStep` and `resume` for crash recovery:

```ts
const result = await client.walrus.writeBlob({
  blob: bytes,
  deletable: true,
  epochs: 3,
  signer: keypair,
  onStep: (step) => db.save(fileId, step),
  resume: await db.load(fileId),
});
```

Persist each step from `onStep`. On restart, pass the saved step as `resume`; the flow skips completed steps, validates the blob ID, and uploads only missing slivers.

For advanced control, `writeFilesFlow` also supports `run()` as an async iterator:

```ts
const flow = client.walrus.writeFilesFlow({ files });

for await (const step of flow.run({
  signer: keypair,
  epochs: 3,
  deletable: true,
})) {
  await db.save(fileId, step);
}

const fileRefs = await flow.listFiles();
```

## Writing Raw Blobs

Use `writeBlob` when the caller wants raw bytes rather than file/quilt semantics:

```ts
const { blobId } = await client.walrus.writeBlob({
  blob: new TextEncoder().encode('Hello from Walrus\n'),
  deletable: false,
  epochs: 3,
  signer: keypair,
});
```

Use `WalrusFile` for file-like data with identifiers/tags, and `writeBlob` for a single raw `Uint8Array`.

## Upload Relay

Use an upload relay to reduce client-side write complexity:

```ts
const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',
}).$extend(
  walrus({
    uploadRelay: {
      host: 'https://relay.example.com',
      sendTip: {
        max: 1_000,
      },
    },
  }),
);
```

`sendTip` can be a capped amount or a linear tip with a fixed base plus size multiplier. Validate relay host, tip policy, and trust model before adding this to production.

## Error and Network Handling

Pass `storageNodeClientOptions.onError` to observe individual storage-node request failures:

```ts
const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',
}).$extend(
  walrus({
    storageNodeClientOptions: {
      onError: (error) => {
        logger.warn({ err: error }, 'walrus storage-node request failed');
      },
    },
  }),
);
```

For production, provide a custom `fetch` when you need timeouts, rate limits, retries, request tracing, or runtime-specific behavior:

```ts
walrus({
  storageNodeClientOptions: {
    fetch: async (input, init) => fetch(input, {
      ...init,
      signal: init?.signal,
    }),
  },
});
```

The SDK uses global `fetch` by default and does not impose concurrency limits.

## Browser and Vite Notes

The SDK includes WASM paths. For Vite/client-side apps, verify the current docs for loading the WASM module. If fetch behavior differs in the target runtime, configure custom fetch instead of relying on runtime defaults.

Browser limitations to check:

- wallet popups must be tied to user gestures;
- direct storage-node operations are request-heavy;
- CORS, timeout, and connection limits depend on runtime and storage endpoints;
- large uploads need progress persistence and abort handling.

## Migration Notes

For `@mysten/walrus` v2:

- Replace direct `new WalrusClient({ suiRpcUrl, network })` setup with a Sui client plus `$extend(walrus())`.
- Remove `network` from `walrus({ network })`; network is inferred from the Sui client.
- Replace `WalrusClient.experimental_asClientExtension()` with `walrus()`.
- Update method calls from `walrusClient.*` to `client.walrus.*`.

## Review Checklist

- Client uses `$extend(walrus())`.
- `walrus()` does not receive a `network` option.
- Direct storage-node use is intentional despite high request counts.
- Production apps considered publisher/aggregator or upload relay alternatives.
- Writes specify `epochs`, `deletable`, and a signer with enough SUI and WAL.
- Browser uploads split wallet-signing steps into user-triggered actions.
- Uploads that can be interrupted use `onStep` and `resume`.
- File-like data uses `WalrusFile`; raw byte blobs use `writeBlob`.
- Batch reads/writes are used when possible.
- Network errors are observable through `onError` or project logging.
- Custom fetch is used when the runtime needs timeouts, retries, limits, or tracing.

## Helper Script

Use `scripts/walrus-sdk-js-bootstrap.sh` when an agent needs a quick machine-readable scaffold:

```bash
bash /mnt/skills/user/walrus-sdk-js/scripts/walrus-sdk-js-bootstrap.sh grpc testnet
bash /mnt/skills/user/walrus-sdk-js/scripts/walrus-sdk-js-bootstrap.sh relay testnet
bash /mnt/skills/user/walrus-sdk-js/scripts/walrus-sdk-js-bootstrap.sh graphql mainnet
```

The script prints JSON to stdout and status messages to stderr.
