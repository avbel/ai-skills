#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: create-secret-module.sh [--out path] [--language ts|js] [--force]

Creates a small Secret Manager integration module exporting getSecret(key).
Writes JSON metadata to stdout and status messages to stderr.
USAGE
}

out="src/secret.ts"
language=""
force="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      out="${2:-}"
      shift 2
      ;;
    --language)
      language="${2:-}"
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

if [[ -z "$language" ]]; then
  case "$out" in
    *.js|*.mjs)
      language="js"
      ;;
    *)
      language="ts"
      ;;
  esac
fi

case "$language" in
  ts|js)
    ;;
  *)
    echo "--language must be ts or js" >&2
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

write_ts() {
  cat >"$tmp" <<'TS'
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
    case 3:
    case 5:
    case 7:
    case 16:
      return true;
    default:
      return /could not load the default credentials|secret manager api has not been used|permission denied|not found/i.test(
        err.message ?? '',
      );
  }
}
TS
}

write_js() {
  cat >"$tmp" <<'JS'
import { Buffer } from 'node:buffer';
import { v1 } from '@google-cloud/secret-manager';

const client = new v1.SecretManagerServiceClient();
const cache = new Map();

export function getSecret(key) {
  if (!cache.has(key)) {
    cache.set(key, loadSecret(key));
  }

  return cache.get(key);
}

async function loadSecret(key) {
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

function secretVersionName(key) {
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

function secretManagerProjectId() {
  return process.env.SECRET_MANAGER_PROJECT_ID
    ?? process.env.GOOGLE_CLOUD_PROJECT
    ?? process.env.GCP_PROJECT
    ?? process.env.GCLOUD_PROJECT;
}

function secretManagerLocation() {
  return process.env.SECRET_MANAGER_LOCATION ?? process.env.GOOGLE_CLOUD_LOCATION;
}

function secretManagerVersionId() {
  return process.env.SECRET_MANAGER_VERSION ?? process.env.GOOGLE_CLOUD_SECRET_VERSION ?? 'latest';
}

function payloadToUtf8(data) {
  if (data == null) {
    throw new Error('Secret Manager returned an empty payload');
  }

  return typeof data === 'string'
    ? Buffer.from(data, 'base64').toString('utf8')
    : Buffer.from(data).toString('utf8');
}

function isSecretManagerUnconfigured(error) {
  const code = error?.code;

  switch (code) {
    case 3:
    case 5:
    case 7:
    case 16:
      return true;
    default:
      return /could not load the default credentials|secret manager api has not been used|permission denied|not found/i.test(
        error?.message ?? '',
      );
  }
}
JS
}

case "$language" in
  ts)
    write_ts
    ;;
  js)
    write_js
    ;;
esac

mv "$tmp" "$out"
trap - EXIT

echo "Created $out" >&2
escaped_out=${out//\\/\\\\}
escaped_out=${escaped_out//\"/\\\"}
printf '{"file":"%s","language":"%s"}\n' "$escaped_out" "$language"
