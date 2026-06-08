---
name: google-cloud-secret-manager-rust
description: Google Cloud Secret Manager conventions for Rust - google-cloud-secretmanager-v1 crate selection, ADC/IAM setup, access/create/rotate/list/delete secrets, version pinning, and get_secret(key) helpers returning None when unconfigured.
---

# Google Cloud Secret Manager for Rust

Use this skill when adding, reviewing, or debugging Google Cloud Secret Manager usage in Rust projects.

Primary sources to refresh when behavior matters:

- `googleapis/google-cloud-rust`, crate `google-cloud-secretmanager-v1`
- Crates.io metadata for `google-cloud-secretmanager-v1`, `google-secretmanager1`, and `gcloud-sdk`
- Docs.rs for `google-cloud-secretmanager-v1` and `google-cloud-gax`
- Google Cloud Secret Manager docs: client libraries, access secret version, best practices, API enablement

As of the 2026-06-08 source check, prefer `google-cloud-secretmanager-v1 = "1.10.0"`. Crates.io lists it as the current stable release, published from the official `googleapis/google-cloud-rust` repository, Apache-2.0 licensed, updated 2026-06-03, with more than 1.3M total downloads and 775K recent downloads. The latest docs.rs pages may lag the newest crates.io release, but the generated client shape is stable: `SecretManagerService::builder().build().await?`, request builders such as `access_secret_version().set_name(...).send().await?`, and payload bytes at `response.payload.unwrap().data`.

## Crate Choice

Use `google-cloud-secretmanager-v1` for new Rust code:

```toml
[dependencies]
google-cloud-secretmanager-v1 = "1.10.0"
tokio = { version = "1", features = ["sync"] }
```

Why this crate:

- It is the focused Secret Manager client from the official Google Cloud Rust repo.
- It uses Application Default Credentials (ADC) by default through the Google Cloud Rust stack.
- It exposes typed models, builders, Secret Manager IAM helpers, and `google_cloud_gax::error::Error`.
- It has frequent 2026 releases and substantially more Secret-Manager-specific recent downloads than `google-secretmanager1`.

Alternatives:

- Use `google-secretmanager1` only when a project already standardizes on `google-apis-rs`, REST-style clients, and `yup-oauth2`.
- Use `gcloud-sdk` only when a project already depends on its broad generated Google API surface. It is popular, but much larger than needed for a narrow Secret Manager integration.
- Do not hand-roll raw REST calls unless the project has an established HTTP/auth abstraction that already handles Google auth, retry, timeout, and error mapping correctly.

## Current Defaults

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
- Reuse `SecretManagerService`; it holds a connection pool internally and is cheap to clone.
- Never log secret values, full payloads, or environment dumps.
- Do not fallback to environment variables for secret values. If Secret Manager is not configured, return `Ok(None)` and make the caller decide whether the secret is required.

## Configuring GCP Settings

Use one of these configuration paths. These settings identify Google Cloud resources and credentials; they must not contain secret payload values.

1. Full resource names at the call site:
   ```rust
   let db = get_secret("projects/my-project/secrets/DATABASE_URL/versions/42").await?;
   let key = get_secret("projects/my-project/locations/us-central1/secrets/API_KEY/versions/latest").await?;
   ```
   Use this for cross-project reads, regional secrets, or per-secret version pinning.

2. App-specific env settings for resource names only:
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
   - Configure the runtime service account, grant it `roles/secretmanager.secretAccessor` on the needed secrets, and set project/location/version through the platform's normal config mechanism.

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

8. Explicit client options when the project already has a config module:
   ```rust
   let client = SecretManagerService::builder()
       .with_endpoint("https://secretmanager.googleapis.com")
       .build()
       .await?;
   ```
   Secret Manager access requests still need full resource names such as `projects/<project>/secrets/<secret>/versions/<version>`.

## Simplest App Integration

For an existing Tokio-based app, add one `secret.rs` module and import `get_secret()` wherever config is loaded. Prefer reading secrets during startup and passing ordinary config values into the rest of the app.

```rust
// src/secret.rs
use std::env;
use std::error::Error as StdError;
use std::fmt;
use std::string::FromUtf8Error;

use google_cloud_secretmanager_v1::Error as GcpError;
use google_cloud_secretmanager_v1::client::SecretManagerService;
use tokio::sync::OnceCell;

static CLIENT: OnceCell<SecretManagerService> = OnceCell::const_new();

#[derive(Debug)]
pub enum SecretError {
    SecretManager(GcpError),
    EmptyPayload(String),
    Utf8(FromUtf8Error),
}

impl fmt::Display for SecretError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::SecretManager(error) => write!(f, "Secret Manager error: {error}"),
            Self::EmptyPayload(name) => {
                write!(f, "Secret Manager returned an empty payload for {name}")
            }
            Self::Utf8(error) => write!(f, "Secret Manager payload is not valid UTF-8: {error}"),
        }
    }
}

impl StdError for SecretError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::SecretManager(error) => Some(error),
            Self::Utf8(error) => Some(error),
            Self::EmptyPayload(_) => None,
        }
    }
}

pub async fn get_secret(key: &str) -> Result<Option<String>, SecretError> {
    let Some(name) = secret_version_name(key) else {
        return Ok(None);
    };

    let client = match CLIENT
        .get_or_try_init(|| async { SecretManagerService::builder().build().await })
        .await
    {
        Ok(client) => client,
        Err(error) if is_secret_manager_unconfigured(error) => return Ok(None),
        Err(error) => return Err(SecretError::SecretManager(error)),
    };

    access_secret_name(client, &name).await
}

pub async fn get_secret_with_client(
    client: &SecretManagerService,
    key: &str,
) -> Result<Option<String>, SecretError> {
    let Some(name) = secret_version_name(key) else {
        return Ok(None);
    };

    access_secret_name(client, &name).await
}

async fn access_secret_name(
    client: &SecretManagerService,
    name: &str,
) -> Result<Option<String>, SecretError> {
    let response = match client
        .access_secret_version()
        .set_name(name.to_owned())
        .send()
        .await
    {
        Ok(response) => response,
        Err(error) if is_secret_manager_unconfigured(&error) => return Ok(None),
        Err(error) => return Err(SecretError::SecretManager(error)),
    };

    let payload = response
        .payload
        .ok_or_else(|| SecretError::EmptyPayload(name.to_owned()))?;

    String::from_utf8(payload.data.to_vec())
        .map(Some)
        .map_err(SecretError::Utf8)
}

fn secret_version_name(key: &str) -> Option<String> {
    let version = secret_manager_version_id();

    if key.starts_with("projects/") {
        return Some(if key.contains("/versions/") {
            key.to_owned()
        } else {
            format!("{key}/versions/{version}")
        });
    }

    let project_id = secret_manager_project_id()?;
    let parent = match secret_manager_location() {
        Some(location) => format!("projects/{project_id}/locations/{location}"),
        None => format!("projects/{project_id}"),
    };

    Some(format!("{parent}/secrets/{key}/versions/{version}"))
}

fn secret_manager_project_id() -> Option<String> {
    [
        "SECRET_MANAGER_PROJECT_ID",
        "GOOGLE_CLOUD_PROJECT",
        "GCP_PROJECT",
        "GCLOUD_PROJECT",
    ]
    .into_iter()
    .find_map(env_non_empty)
}

fn secret_manager_location() -> Option<String> {
    env_non_empty("SECRET_MANAGER_LOCATION").or_else(|| env_non_empty("GOOGLE_CLOUD_LOCATION"))
}

fn secret_manager_version_id() -> String {
    env_non_empty("SECRET_MANAGER_VERSION")
        .or_else(|| env_non_empty("GOOGLE_CLOUD_SECRET_VERSION"))
        .unwrap_or_else(|| "latest".to_owned())
}

fn env_non_empty(name: &str) -> Option<String> {
    env::var(name)
        .ok()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn is_secret_manager_unconfigured(error: &GcpError) -> bool {
    if matches!(error.http_status_code(), Some(400 | 401 | 403 | 404)) {
        return true;
    }

    let message = error.to_string().to_ascii_lowercase();
    [
        "application default credentials",
        "could not load default credentials",
        "could not load the default credentials",
        "invalid argument",
        "not found",
        "permission denied",
        "secret manager api has not been used",
        "unauthenticated",
    ]
    .iter()
    .any(|needle| message.contains(needle))
}
```

Use it like this:

```rust
let database_url = get_secret("DATABASE_URL").await?;
let stripe_key = get_secret("STRIPE_API_KEY").await?;
```

For required secrets, fail explicitly at the configuration boundary:

```rust
let database_url = get_secret("DATABASE_URL")
    .await?
    .ok_or_else(|| anyhow::anyhow!("DATABASE_URL is not configured in Secret Manager"))?;
```

Use full resource names when a project needs regional secrets or cross-project access:

```rust
let key = get_secret(
    "projects/shared-secrets/locations/us-central1/secrets/STRIPE_API_KEY/versions/42",
)
.await?;
```

## Scaffold Script

To add the integration module quickly:

```bash
bash /mnt/skills/user/google-cloud-secret-manager-rust/scripts/create-secret-module.sh --out src/secret.rs
```

Options:

- `--out <path>`: output file, default `src/secret.rs`.
- `--force`: overwrite an existing file.

The script prints JSON to stdout and status to stderr.

## Common Operations

Create a reusable client:

```rust
use google_cloud_secretmanager_v1::client::SecretManagerService;

let client = SecretManagerService::builder().build().await?;
```

Access a secret version:

```rust
let name = format!("projects/{project_id}/secrets/{secret_id}/versions/{version_id}");
let response = client.access_secret_version().set_name(name).send().await?;
let payload = response.payload.expect("Secret Manager returned no payload");
let value = String::from_utf8(payload.data.to_vec())?;
```

Create a secret with automatic replication:

```rust
use google_cloud_secretmanager_v1::model::replication::Automatic;
use google_cloud_secretmanager_v1::model::{Replication, Secret};

let secret = Secret::new().set_replication(Replication::new().set_automatic(Automatic::new()));

let created = client
    .create_secret()
    .set_parent(format!("projects/{project_id}"))
    .set_secret_id("DATABASE_URL")
    .set_secret(secret)
    .send()
    .await?;
```

Add a new version:

```rust
use google_cloud_secretmanager_v1::model::SecretPayload;

let parent = format!("projects/{project_id}/secrets/DATABASE_URL");
let version = client
    .add_secret_version()
    .set_parent(parent)
    .set_payload(SecretPayload::new().set_data(database_url.as_bytes().to_vec()))
    .send()
    .await?;
```

List secrets and versions:

```rust
use google_cloud_gax::paginator::ItemPaginator as _;

let mut secrets = client
    .list_secrets()
    .set_parent(format!("projects/{project_id}"))
    .by_item();

while let Some(secret) = secrets.next().await.transpose()? {
    println!("{:?}", secret);
}

let mut versions = client
    .list_secret_versions()
    .set_parent(format!("projects/{project_id}/secrets/DATABASE_URL"))
    .by_item();
```

If you use paginator helpers directly, add a matching `google-cloud-gax` dependency:

```toml
google-cloud-gax = "1.11.0"
```

Disable, re-enable, or destroy a version:

```rust
let name = format!("projects/{project_id}/secrets/DATABASE_URL/versions/42");
client.disable_secret_version().set_name(name.clone()).send().await?;
client.enable_secret_version().set_name(name.clone()).send().await?;
client.destroy_secret_version().set_name(name).send().await?;
```

Delete a secret only when every consumer has migrated away:

```rust
client
    .delete_secret()
    .set_name(format!("projects/{project_id}/secrets/OLD_SECRET"))
    .send()
    .await?;
```

Read or check IAM:

```rust
let resource = format!("projects/{project_id}/secrets/DATABASE_URL");
let policy = client.get_iam_policy().set_resource(resource.clone()).send().await?;
let permissions = client
    .test_iam_permissions()
    .set_resource(resource)
    .set_permissions(["secretmanager.versions.access"])
    .send()
    .await?;
```

`test_iam_permissions` is for diagnostics and user interfaces. Do not use it as the sole authorization check for a privileged action because Google documents this style of method as permission-aware tooling, not authorization enforcement.

## Rotation and Versioning

- For production, pin `GOOGLE_CLOUD_SECRET_VERSION` to a numeric version and roll it forward through normal deploys. Use `latest` only when the blast radius is acceptable.
- A safe rotation is: create/add version, deploy consumers pinned to the new version, monitor, disable the old version, wait, then destroy the old version.
- Adding a version and accessing that version by number is strongly consistent. Other operations and IAM propagation are eventually consistent, so do not assume a newly granted role works immediately.
- Prefer automatic replication unless the workload has explicit data residency requirements. For regional secrets, include `/locations/<location>` in the resource name or set `GOOGLE_CLOUD_LOCATION`.

## Local Dev and Tests

- Do not read secret values from env vars. For local dev, either configure ADC and a development project or let `get_secret()` return `Ok(None)` and use non-secret local defaults outside the secret helper.
- In unit tests, leave `GOOGLE_CLOUD_PROJECT` unset to exercise the `Ok(None)` path, or call `get_secret_with_client()` with a mocked `SecretManagerService` built via `from_stub`.
- For integration tests, use a dedicated project or secret prefix, create a temporary secret, add a version, access it, then disable/destroy/delete during cleanup.
- If the app reads secrets on every request, cache the promise/future or load once at startup. Secret Manager calls have quota and latency; a deploy or autoscaling event can create a burst.

## Binary Secrets

For binary values, expose a separate helper that returns bytes; do not decode as UTF-8:

```rust
pub async fn get_secret_bytes(client: &SecretManagerService, name: &str) -> Result<Vec<u8>, SecretError> {
    let response = client
        .access_secret_version()
        .set_name(name.to_owned())
        .send()
        .await
        .map_err(SecretError::SecretManager)?;

    let payload = response
        .payload
        .ok_or_else(|| SecretError::EmptyPayload(name.to_owned()))?;

    Ok(payload.data.to_vec())
}
```

## Installation

Manual install for Claude Code:

```bash
cp -r skills/google-cloud-secret-manager-rust ~/.claude/skills/
```

For claude.ai Projects, add the skill to project knowledge or paste this `SKILL.md` into the conversation. If web access is required, allow `cloud.google.com`, `docs.rs`, `crates.io`, and `github.com`.

## Review Checklist

- The code uses `google-cloud-secretmanager-v1` for new integrations unless the project already standardizes on `google-apis-rs` or `gcloud-sdk`.
- ADC setup is documented; service account keys are not committed or encouraged as the default.
- Runtime service accounts have `roles/secretmanager.secretAccessor` only on needed secrets.
- The app does not log secret payloads or dump environment variables.
- Production consumers pin numeric versions or consciously accept `latest`.
- Missing Secret Manager configuration returns `Ok(None)`; required secrets are checked explicitly by the caller.
- The code does not fallback to env vars for secret values.
- Secret Manager clients are reused, and secret values are cached where repeated reads would add latency or quota pressure.
