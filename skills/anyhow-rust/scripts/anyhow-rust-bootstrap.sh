#!/bin/bash
set -e

scenario="${1:-context}"
cargo='anyhow = "1"'

case "$scenario" in
  context)
    snippet='use anyhow::{Context, Result};

fn load_config(path: &str) -> Result<String> {
    // Static context is cheap — use .context(...).
    let bytes = std::fs::read(path).context("reading config file")?;

    // Formatted context allocates — use .with_context(|| ...) so the closure
    // only runs on the error path.
    let text = std::str::from_utf8(&bytes)
        .with_context(|| format!("config at {path} is not valid UTF-8"))?;

    Ok(text.to_owned())
}'
    ;;
  bail)
    snippet='use anyhow::{bail, Result};

fn authorize(user: &str, resource: &str) -> Result<()> {
    if !has_permission(user, resource) {
        // Equivalent to: return Err(anyhow!("permission denied ..."));
        bail!("permission denied: {user} cannot access {resource}");
    }
    Ok(())
}

fn has_permission(_user: &str, _resource: &str) -> bool {
    false
}'
    ;;
  ensure)
    snippet='use anyhow::{ensure, Result};

const MAX_DEPTH: usize = 32;

fn descend(depth: usize) -> Result<()> {
    // ensure! returns early on false — never panics, unlike assert!.
    ensure!(
        depth <= MAX_DEPTH,
        "recursion limit {MAX_DEPTH} exceeded (depth = {depth})"
    );
    Ok(())
}'
    ;;
  downcast)
    snippet='use anyhow::{Context, Error, Result};
use std::io;

fn read_optional(path: &str) -> Result<Option<Vec<u8>>> {
    match std::fs::read(path).with_context(|| format!("reading {path}")) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(err) => match err.downcast_ref::<io::Error>() {
            Some(io_err) if io_err.kind() == io::ErrorKind::NotFound => Ok(None),
            _ => Err(err),
        },
    }
}

fn print_chain(err: &Error) {
    eprintln!("error: {err}");
    for cause in err.chain().skip(1) {
        eprintln!("  caused by: {cause}");
    }
    eprintln!("root cause: {}", err.root_cause());
}'
    ;;
  main)
    snippet='use anyhow::{Context, Result};

fn run() -> Result<()> {
    let cfg = std::fs::read_to_string("settings.toml").context("loading settings")?;
    println!("loaded {} bytes", cfg.len());
    Ok(())
}

// Returning anyhow::Result<()> from main triggers Debug-formatting of the error,
// which prints the full chain plus backtrace (if RUST_BACKTRACE / RUST_LIB_BACKTRACE).
fn main() -> Result<()> {
    run()
}'
    ;;
  thiserror-mix)
    cargo='anyhow = "1"
thiserror = "2"'
    snippet='// Library crate: define a concrete error enum with thiserror.
#[derive(thiserror::Error, Debug)]
pub enum StorageError {
    #[error("blob {0} not found")]
    NotFound(String),
    #[error("io error")]
    Io(#[from] std::io::Error),
}

pub fn read_blob(id: &str) -> Result<Vec<u8>, StorageError> {
    std::fs::read(format!("blobs/{id}")).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => StorageError::NotFound(id.to_owned()),
        _ => StorageError::from(e),
    })
}

// Application crate: use anyhow::Result, propagate with `?`, attach context.
use anyhow::{Context, Result};

pub fn handle_request(id: &str) -> Result<Vec<u8>> {
    // ? lifts StorageError into anyhow::Error via From.
    read_blob(id).with_context(|| format!("loading blob {id}"))
}'
    ;;
  *)
    echo "Usage: $0 [context|bail|ensure|downcast|main|thiserror-mix]" >&2
    exit 2
    ;;
esac

SCENARIO="$scenario" CARGO="$cargo" SNIPPET="$snippet" python3 <<'PY'
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "cargo": os.environ["CARGO"],
    "snippet": os.environ["SNIPPET"],
    "reminders": [
        "anyhow for binaries/glue; thiserror (or hand-rolled enums) for libraries.",
        "Prefer .with_context(|| format!(...)) over .context(format!(...)) — lazy.",
        "Return anyhow::Result<()> from main to print the full chain via Debug.",
        "Set RUST_BACKTRACE=1 (or RUST_LIB_BACKTRACE=1) to capture backtraces.",
    ],
}, indent=2))
PY
