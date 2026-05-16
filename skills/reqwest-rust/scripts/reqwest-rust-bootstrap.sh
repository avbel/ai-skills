#!/bin/bash
set -e

scenario="${1:-client}"

case "$scenario" in
  client)
    cargo='reqwest = { version = "0.13", default-features = false, features = ["rustls", "http2", "json", "gzip"] }
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }'
    snippet='use std::time::Duration;

fn http_client() -> reqwest::Result<reqwest::Client> {
    reqwest::Client::builder()
        .tls_backend_rustls()
        .https_only(true)
        .user_agent(concat!(env!("CARGO_PKG_NAME"), "/", env!("CARGO_PKG_VERSION")))
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(30))
        .pool_idle_timeout(Duration::from_secs(90))
        .build()
}'
    ;;
  json)
    cargo='reqwest = { version = "0.13", default-features = false, features = ["rustls", "http2", "json"] }
serde = { version = "1", features = ["derive"] }
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }'
    snippet='use serde::{Deserialize, Serialize};

#[derive(Serialize)]
struct CreateWidgetRequest {
    name: String,
}

#[derive(Deserialize)]
struct Widget {
    id: String,
    name: String,
}

async fn create_widget(
    client: &reqwest::Client,
    base_url: &str,
    request: &CreateWidgetRequest,
) -> reqwest::Result<Widget> {
    client
        .post(format!("{base_url}/widgets"))
        .json(request)
        .send()
        .await?
        .error_for_status()?
        .json::<Widget>()
        .await
}'
    ;;
  stream)
    cargo='reqwest = { version = "0.13", default-features = false, features = ["rustls", "http2", "stream"] }
tokio = { version = "1", features = ["fs", "io-util", "macros", "rt-multi-thread"] }'
    snippet='use tokio::io::AsyncWriteExt;

async fn download_to_file(
    client: &reqwest::Client,
    url: &str,
    path: &std::path::Path,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut response = client.get(url).send().await?.error_for_status()?;
    let mut file = tokio::fs::File::create(path).await?;

    while let Some(chunk) = response.chunk().await? {
        file.write_all(&chunk).await?;
    }

    Ok(())
}'
    ;;
  blocking)
    cargo='reqwest = { version = "0.13", features = ["blocking", "json"] }'
    snippet='fn fetch_text(url: &str) -> reqwest::Result<String> {
    reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()?
        .get(url)
        .send()?
        .error_for_status()?
        .text()
}'
    ;;
  classify)
    cargo='reqwest = "0.13"'
    snippet='fn classify_reqwest_error(error: &reqwest::Error) -> &'"'"'static str {
    if error.is_timeout() {
        "timeout"
    } else if error.is_connect() {
        "connect"
    } else if error.is_status() {
        "status"
    } else if error.is_decode() {
        "decode"
    } else if error.is_body() {
        "body"
    } else if error.is_redirect() {
        "redirect"
    } else {
        "other"
    }
}'
    ;;
  *)
    echo "Usage: $0 [client|json|stream|blocking|classify]" >&2
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
