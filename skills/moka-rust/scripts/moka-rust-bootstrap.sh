#!/bin/bash
set -e

scenario="${1:-sync}"

case "$scenario" in
  sync)
    cargo='moka = { version = "0.12", features = ["sync"] }'
    snippet='use moka::sync::Cache;
use std::{sync::Arc, time::Duration};

#[derive(Debug)]
struct User {
    id: u64,
    name: String,
}

fn user_cache() -> Cache<u64, Arc<User>> {
    Cache::builder()
        .max_capacity(10_000)
        .time_to_live(Duration::from_secs(300))
        .time_to_idle(Duration::from_secs(60))
        .build()
}

fn load_user(cache: &Cache<u64, Arc<User>>, id: u64) -> Arc<User> {
    cache.get_with(id, || {
        Arc::new(User {
            id,
            name: format!("user-{id}"),
        })
    })
}'
    ;;
  future)
    cargo='moka = { version = "0.12", features = ["future"] }
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }'
    snippet='use moka::future::Cache;
use std::{sync::Arc, time::Duration};

#[derive(Debug)]
struct User {
    id: u64,
    name: String,
}

fn user_cache() -> Cache<u64, Arc<User>> {
    Cache::builder()
        .max_capacity(10_000)
        .time_to_live(Duration::from_secs(300))
        .time_to_idle(Duration::from_secs(60))
        .build()
}

async fn load_user(cache: &Cache<u64, Arc<User>>, id: u64) -> Arc<User> {
    cache
        .get_with(id, async move {
            Arc::new(User {
                id,
                name: format!("user-{id}"),
            })
        })
        .await
}'
    ;;
  try-get)
    cargo='moka = { version = "0.12", features = ["sync"] }'
    snippet='use moka::sync::Cache;
use std::{io, sync::Arc};

#[derive(Debug)]
struct Config(String);

fn load_config_from_disk(key: &str) -> io::Result<Arc<Config>> {
    Ok(Arc::new(Config(format!("config:{key}"))))
}

fn get_config(cache: &Cache<String, Arc<Config>>, key: &str) -> io::Result<Arc<Config>> {
    cache
        .try_get_with(key.to_owned(), || load_config_from_disk(key))
        .map_err(|error| io::Error::new(error.kind(), error.to_string()))
}'
    ;;
  weighted)
    cargo='moka = { version = "0.12", features = ["sync"] }'
    snippet='use moka::sync::Cache;

fn weighted_cache() -> Cache<String, String> {
    Cache::builder()
        .weigher(|_key, value: &String| value.len().try_into().unwrap_or(u32::MAX))
        .max_capacity(32 * 1024 * 1024)
        .build()
}'
    ;;
  eviction)
    cargo='moka = { version = "0.12", features = ["sync"] }'
    snippet='use moka::{notification::RemovalCause, sync::Cache};
use std::{sync::Arc, time::Duration};

fn cache_with_listener() -> Cache<String, Arc<String>> {
    Cache::builder()
        .max_capacity(10_000)
        .time_to_live(Duration::from_secs(300))
        .eviction_listener(|key: Arc<String>, _value: Arc<String>, cause: RemovalCause| {
            if cause.was_evicted() {
                eprintln!("cache entry evicted: key={key}, cause={cause:?}");
            }
        })
        .build()
}'
    ;;
  *)
    echo "Usage: $0 [sync|future|try-get|weighted|eviction]" >&2
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
}, indent=2))
PY
