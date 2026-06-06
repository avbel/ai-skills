#!/bin/bash
set -e

project_name="${1:-node-rust-addon-example}"

if [ -e "$project_name" ]; then
  echo "Target already exists: $project_name" >&2
  exit 1
fi

mkdir -p "$project_name/src"

cat > "$project_name/package.json" <<'JSON'
{
  "type": "module",
  "main": "index.js",
  "types": "index.d.ts",
  "scripts": {
    "build": "napi build --release --platform",
    "build:debug": "napi build"
  },
  "devDependencies": {
    "@napi-rs/cli": "^3.6.0"
  },
  "napi": {
    "name": "native_addon",
    "triples": {
      "defaults": true
    }
  }
}
JSON

cat > "$project_name/Cargo.toml" <<'TOML'
[package]
name = "native_addon"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
napi = { version = "3", features = ["napi8", "tokio_rt"] }
napi-derive = "3"
tokio = { version = "1", features = ["fs", "rt-multi-thread"] }
TOML

cat > "$project_name/src/lib.rs" <<'RUST'
use napi::bindgen_prelude::*;
use napi_derive::napi;

#[napi]
pub fn sum_u64(values: Vec<u64>) -> u64 {
    values.into_iter().sum()
}

#[napi]
pub async fn read_file_async(path: String) -> Result<Buffer> {
    let bytes = tokio::fs::read(path)
        .await
        .map_err(|error| Error::new(Status::GenericFailure, format!("read failed: {error}")))?;

    Ok(bytes.into())
}
RUST

cat > "$project_name/index.js" <<'JS'
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const native = require('./native_addon.node');

export const { readFileAsync, sumU64 } = native;
JS

echo "Created $project_name" >&2
printf '{"project":"%s","next":["cd %s","pnpm install","pnpm build"]}\n' "$project_name" "$project_name"
