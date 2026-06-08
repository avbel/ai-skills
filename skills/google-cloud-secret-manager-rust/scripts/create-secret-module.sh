#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: create-secret-module.sh [--out path] [--force]

Creates a small Rust Secret Manager integration module exporting get_secret(key).
Writes JSON metadata to stdout and status messages to stderr.
USAGE
}

out="src/secret.rs"
force="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      out="${2:-}"
      shift 2
      ;;
    --force)
      force="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$out" ]]; then
  echo "--out must not be empty" >&2
  exit 2
fi

case "$out" in
  *.rs)
    ;;
  *)
    echo "--out must end with .rs" >&2
    exit 2
    ;;
esac

if [[ -e "$out" && "$force" != "true" ]]; then
  echo "Refusing to overwrite existing file: $out" >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"
tmp="${out}.tmp.$$"
cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT

cat >"$tmp" <<'RS'
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
RS

mv "$tmp" "$out"
trap - EXIT

echo "Created $out" >&2
escaped_out=${out//\\/\\\\}
escaped_out=${escaped_out//\"/\\\"}
printf '{"file":"%s","language":"rust"}\n' "$escaped_out"
