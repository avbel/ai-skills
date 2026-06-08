---
name: google-cloud-secret-manager-js
description: Google Cloud Secret Manager conventions for JavaScript and TypeScript - @google-cloud/secret-manager setup, ADC/IAM, access/create/rotate/list/delete secrets, version pinning, and getSecret(key) modules that return undefined when unconfigured.
---

# Google Cloud Secret Manager for JavaScript and TypeScript

Use this skill when adding, reviewing, or debugging Google Cloud Secret Manager usage in Node.js JavaScript or TypeScript projects.

Primary sources to refresh when behavior matters:

- `googleapis/google-cloud-node`, package `packages/google-cloud-secretmanager`
- Google Cloud Secret Manager docs: client libraries, access secret version, best practices, API enablement
- Node.js API reference for `@google-cloud/secret-manager`

As of the 2026-06-08 source check, the Node package is `@google-cloud/secret-manager`, the API reference documents package version `5.5.0`, and the Google docs recommend Application Default Credentials (ADC).

## Current Defaults

- Install the official client:
  ```bash
  pnpm add @google-cloud/secret-manager
  ```
  Use the repository's actual package manager.
- Import the v1 client for new code:
  ```ts
  import { v1 } from '@google-cloud/secret-manager';

  const client = new v1.SecretManagerServiceClient();
  ```
- Enable the API once per project:
  ```bash
  gcloud services enable secretmanager.googleapis.com
  ```
- Use ADC. For local development:
  ```bash
  gcloud auth application-default login
  ```
- In production, prefer the runtime service account on Cloud Run, GKE Workload Identity, Compute Engine metadata credentials, or Workload Identity Federation. Avoid long-lived service account JSON keys unless the project has no better option.
- Grant runtime readers `roles/secretmanager.secretAccessor` on only the needed secrets. Use admin roles only for provisioning, rotation, or maintenance tooling.
- Never log secret values, full payloads, or `process.env`.
- Do not fallback to environment variables for secret values. If Secret Manager is not configured, return `undefined` and make the caller decide whether the secret is required.

## Configuring GCP Settings

Use one of these configuration paths. These settings identify Google Cloud resources and credentials; they must not contain secret payload values.

1. Full resource names at the call site:
   ```ts
   await getSecret('projects/my-project/secrets/DATABASE_URL/versions/42');
   await getSecret('projects/my-project/locations/us-central1/secrets/API_KEY/versions/latest');
   ```
   Use this for cross-project reads, regional secrets, or per-secret version pinning.

2. App-specific env settings:
   ```bash
   SECRET_MANAGER_PROJECT_ID=my-project
   SECRET_MANAGER_LOCATION=us-central1
   SECRET_MANAGER_VERSION=42
   ```
   `SECRET_MANAGER_LOCATION` is optional for global secrets. `SECRET_MANAGER_VERSION` defaults to `latest`.

3. Standard Google Cloud project env settings:
   ```bash
   GOOGLE_CLOUD_PROJECT=my-project
   GCP_PROJECT=my-project
   GCLOUD_PROJECT=my-project
   GOOGLE_CLOUD_LOCATION=us-central1
   GOOGLE_CLOUD_SECRET_VERSION=42
   ```
   Prefer one project variable, not all three. The extra names exist because different Google runtimes and older apps expose different project env vars.

4. Local ADC user credentials:
   ```bash
   gcloud auth application-default login
   gcloud auth application-default set-quota-project my-project
   gcloud config set project my-project
   ```
   Still set `SECRET_MANAGER_PROJECT_ID` or `GOOGLE_CLOUD_PROJECT` when the app builds resource names from short secret IDs.

5. Google Cloud runtime ADC:
   - Cloud Run, Cloud Functions, GKE Workload Identity, and Compute Engine can use the attached service account through metadata credentials.
   - Configure the runtime service account, grant it `roles/secretmanager.secretAccessor` on the needed secrets, and set project/location/version settings through the platform's normal config mechanism.

6. Off-GCP or CI without keys:
   - Prefer Workload Identity Federation.
   - Point `GOOGLE_APPLICATION_CREDENTIALS` at the generated external-account credentials file.
   - Keep project/location/version settings separate from the credentials file.

7. Service account key file, only when unavoidable:
   ```bash
   GOOGLE_APPLICATION_CREDENTIALS=/secure/path/service-account.json
   SECRET_MANAGER_PROJECT_ID=my-project
   ```
   Never commit the JSON key, never put it in the skill, and prefer replacing it with runtime ADC or Workload Identity Federation.

8. Constructor options when the project already has a config module:
   ```ts
   const client = new v1.SecretManagerServiceClient({
     projectId: appConfig.gcpProjectId,
   });
   ```
   This configures the client, but Secret Manager access requests still need full resource names such as `projects/<project>/secrets/<secret>/versions/<version>`.

## Simplest App Integration

For an existing app, add one `secret.ts` module and import `getSecret()` wherever config is loaded. Prefer reading secrets during startup and passing ordinary config values into the rest of the app.

```ts
// src/secret.ts
import { Buffer } from 'node:buffer';
import { v1 } from '@google-cloud/secret-manager';

const client = new v1.SecretManagerServiceClient();
const cache = new Map<string, Promise<string | undefined>>();

export function getSecret(key: string): Promise<string | undefined> {
  if (!cache.has(key)) {
    cache.set(key, loadSecret(key));
  }

  return cache.get(key)!;
}

async function loadSecret(key: string): Promise<string | undefined> {
  const name = secretVersionName(key);
  if (!name) {
    return undefined;
  }

  try {
    const [version] = await client.accessSecretVersion({ name });
    return payloadToUtf8(version.payload?.data);
  } catch (error) {
    if (isSecretManagerUnconfigured(error)) {
      return undefined;
    }

    throw error;
  }
}

function secretVersionName(key: string): string | null {
  const version = secretManagerVersionId();

  if (key.startsWith('projects/')) {
    return key.includes('/versions/') ? key : `${key}/versions/${version}`;
  }

  const projectId = secretManagerProjectId();
  if (!projectId) {
    return null;
  }

  const location = secretManagerLocation();
  const parent = location ? `projects/${projectId}/locations/${location}` : `projects/${projectId}`;
  return `${parent}/secrets/${key}/versions/${version}`;
}

function secretManagerProjectId(): string | undefined {
  return process.env.SECRET_MANAGER_PROJECT_ID
    ?? process.env.GOOGLE_CLOUD_PROJECT
    ?? process.env.GCP_PROJECT
    ?? process.env.GCLOUD_PROJECT;
}

function secretManagerLocation(): string | undefined {
  return process.env.SECRET_MANAGER_LOCATION ?? process.env.GOOGLE_CLOUD_LOCATION;
}

function secretManagerVersionId(): string {
  return process.env.SECRET_MANAGER_VERSION ?? process.env.GOOGLE_CLOUD_SECRET_VERSION ?? 'latest';
}

function payloadToUtf8(data: Uint8Array | string | null | undefined): string {
  if (data == null) {
    throw new Error('Secret Manager returned an empty payload');
  }

  return typeof data === 'string'
    ? Buffer.from(data, 'base64').toString('utf8')
    : Buffer.from(data).toString('utf8');
}

function isSecretManagerUnconfigured(error: unknown): boolean {
  const err = error as { code?: number | string; message?: string };

  switch (err.code) {
    case 3: // INVALID_ARGUMENT: malformed project/secret/version name.
    case 5: // NOT_FOUND: project, secret, or version does not exist.
    case 7: // PERMISSION_DENIED: IAM/API access is not configured for this identity.
    case 16: // UNAUTHENTICATED: ADC is missing or invalid.
      return true;
    default:
      return /could not load the default credentials|secret manager api has not been used|permission denied|not found/i.test(
        err.message ?? '',
      );
  }
}
```

Use it like this:

```ts
import { getSecret } from './secret.js';

export const config = {
  databaseUrl: await getSecret('DATABASE_URL'),
  stripeApiKey: await getSecret('STRIPE_API_KEY'),
};
```

For required secrets, fail explicitly at the configuration boundary:

```ts
const databaseUrl = await getSecret('DATABASE_URL');
if (!databaseUrl) {
  throw new Error('DATABASE_URL is not configured in Secret Manager');
}
```

Cloud runtime:

```bash
SECRET_MANAGER_PROJECT_ID=my-prod-project
SECRET_MANAGER_VERSION=42
```

Use full resource names when a project needs regional secrets or cross-project access:

```ts
await getSecret('projects/shared-secrets/locations/us-central1/secrets/STRIPE_API_KEY/versions/42');
```

## Scaffold Script

To add the integration module quickly:

```bash
bash /mnt/skills/user/google-cloud-secret-manager-js/scripts/create-secret-module.sh --out src/secret.ts
```

Options:

- `--out <path>`: output file, default `src/secret.ts`.
- `--language ts|js`: defaults from the output extension, then `ts`.
- `--force`: overwrite an existing file.

The script prints JSON to stdout and status to stderr.

## Common Operations

Access a secret version:

```ts
const name = `projects/${projectId}/secrets/${secretId}/versions/${versionId}`;
const [version] = await client.accessSecretVersion({ name });
const value = Buffer.from(version.payload?.data ?? []).toString('utf8');
```

Create a secret with automatic replication:

```ts
await client.createSecret({
  parent: `projects/${projectId}`,
  secretId: 'DATABASE_URL',
  secret: {
    replication: {
      automatic: {},
    },
  },
});
```

Add a new version:

```ts
await client.addSecretVersion({
  parent: `projects/${projectId}/secrets/DATABASE_URL`,
  payload: {
    data: Buffer.from(databaseUrl, 'utf8'),
  },
});
```

List secrets and versions:

```ts
const [secrets] = await client.listSecrets({ parent: `projects/${projectId}` });
const [versions] = await client.listSecretVersions({
  parent: `projects/${projectId}/secrets/DATABASE_URL`,
});
```

Disable, re-enable, or destroy a version:

```ts
const name = `projects/${projectId}/secrets/DATABASE_URL/versions/42`;
await client.disableSecretVersion({ name });
await client.enableSecretVersion({ name });
await client.destroySecretVersion({ name });
```

Delete a secret only when every consumer has migrated away:

```ts
await client.deleteSecret({
  name: `projects/${projectId}/secrets/OLD_SECRET`,
});
```

Read or check IAM:

```ts
const resource = `projects/${projectId}/secrets/DATABASE_URL`;
const [policy] = await client.getIamPolicy({ resource });
const [permissions] = await client.testIamPermissions({
  resource,
  permissions: ['secretmanager.versions.access'],
});
```

## Rotation and Versioning

- For production, pin `GOOGLE_CLOUD_SECRET_VERSION` to a numeric version and roll it forward through normal deploys. Use `latest` only when the blast radius is acceptable.
- A safe rotation is: create/add version, deploy consumers pinned to the new version, monitor, disable the old version, wait, then destroy the old version.
- Adding a version and accessing that version by number is strongly consistent. Other operations and IAM propagation are eventually consistent, so do not assume a newly granted role works immediately.
- Prefer automatic replication unless the workload has explicit data residency requirements. For regional secrets, include `/locations/<location>` in the resource name or set `GOOGLE_CLOUD_LOCATION`.

## Local Dev and Tests

- Do not read secret values from env vars. For local dev, either configure ADC and a development project or let `getSecret()` return `undefined` and use non-secret local defaults outside the secret helper.
- In unit tests, leave `GOOGLE_CLOUD_PROJECT` unset to exercise the `undefined` path, or mock `getSecret()` at the module boundary.
- For integration tests, use a dedicated project or secret prefix, create a temporary secret, add a version, access it, then disable/destroy/delete during cleanup.
- If the app reads secrets on every request, cache the promise or load once at startup. Secret Manager calls have quota and latency; a deploy or autoscaling event can create a burst.

## Binary Secrets

For binary values, expose a separate helper that returns `Buffer` or `Uint8Array`; do not decode as UTF-8:

```ts
export async function getSecretBytes(name: string): Promise<Buffer> {
  const [version] = await client.accessSecretVersion({ name });
  const data = version.payload?.data;
  if (data == null) {
    throw new Error(`Secret Manager returned an empty payload for "${name}"`);
  }

  return typeof data === 'string' ? Buffer.from(data, 'base64') : Buffer.from(data);
}
```

## Review Checklist

- The code uses `@google-cloud/secret-manager`, not raw REST, unless there is a clear reason.
- ADC setup is documented; service account keys are not committed or encouraged as the default.
- Runtime service accounts have `roles/secretmanager.secretAccessor` only on needed secrets.
- The app does not log secret payloads or dump environment variables.
- Production consumers pin numeric versions or consciously accept `latest`.
- Missing Secret Manager configuration returns `undefined`; required secrets are checked explicitly by the caller.
- The code does not fallback to env vars for secret values.
- Secret Manager clients are reused, and secret values are cached where repeated reads would add latency or quota pressure.
