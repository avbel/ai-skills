---
name: reqwest-rust
description: Use when building or reviewing Rust HTTP clients with reqwest: async Client, ClientBuilder, TLS backend selection, JSON/form/multipart bodies, streaming downloads/uploads, blocking API, redirects, proxies, cookies, timeouts, retries around reqwest, and HTTP error handling.
---

# Reqwest Rust

Use these conventions for Rust HTTP clients built with `seanmonstar/reqwest`.

## Source Baseline

- Prefer released docs from `docs.rs/reqwest`, crates.io, and the matching GitHub release over older snippets.
- Current docs.rs baseline checked for this skill: `reqwest 0.13.3`.
- Reqwest is an ergonomic, batteries-included HTTP client with async and blocking APIs.
- The async API requires Tokio. The blocking API is feature-gated and must not run directly inside an async runtime.
- Reqwest implements Tower `Service<Request>` for `Client`, but ordinary code usually uses `Client` request builders.
- WASM support exists, but this skill is for native Rust clients; WASM disables or changes several features including TLS, cookies, blocking, and some builder methods.

## Cargo

For native async clients, prefer explicit TLS selection. Cargo features are additive, so `default-features = false` is the reliable way to avoid an unexpected default TLS backend from this crate declaration.

```toml
[dependencies]
reqwest = { version = "0.13", default-features = false, features = ["rustls", "http2", "json", "gzip", "stream"] }
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
serde = { version = "1", features = ["derive"] }
```

Common feature choices:

- `default-tls` is enabled by default and currently uses rustls, but the docs describe it as a backend-agnostic default. Use explicit features and builder methods when the backend matters.
- `rustls` enables the Rustls TLS backend.
- `native-tls` uses system TLS on Windows and macOS and OpenSSL on Linux. `native-tls-vendored` compiles OpenSSL when needed.
- `http2` is enabled by default; keep it enabled for APIs that require HTTP/2.
- `json` enables `RequestBuilder::json()` and `Response::json()`.
- `form` enables `RequestBuilder::form()`.
- `query` enables `RequestBuilder::query()`.
- `multipart` enables multipart form uploads.
- `stream` enables streaming response body APIs.
- `cookies` enables cookie store support.
- `gzip`, `brotli`, `zstd`, and `deflate` enable automatic response decompression for those encodings.
- `system-proxy` is enabled by default and allows system proxy configuration.
- `blocking` enables `reqwest::blocking`.

## Client Construction

Create one `Client` per logical configuration and reuse it. Cloning a `Client` is cheap and shares the connection pool.

```rust
use std::time::Duration;

fn http_client() -> reqwest::Result<reqwest::Client> {
    reqwest::Client::builder()
        .tls_backend_rustls()
        .https_only(true)
        .user_agent(concat!(env!("CARGO_PKG_NAME"), "/", env!("CARGO_PKG_VERSION")))
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(30))
        .pool_idle_timeout(Duration::from_secs(90))
        .build()
}
```

- Prefer `Client::builder().build()?` over `Client::new()` in application code so TLS/resolver initialization errors are returned instead of panicking.
- Set both `connect_timeout` and whole-request `timeout` for network-facing services.
- Use `https_only(true)` unless cleartext HTTP is explicitly required.
- Set a user agent for production clients; many APIs use it for support and abuse handling.
- Configure redirect policy intentionally for auth, signed URLs, and cross-origin requests.
- Configure proxies and cookie stores explicitly; do not let ambient environment behavior surprise security-sensitive clients.

## Requests and Responses

Use typed request/response values and call `error_for_status()` before parsing bodies when non-2xx statuses should be treated as failures.

```rust
use serde::{Deserialize, Serialize};

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
}
```

- `send().await?` only means a response or transport-level error was received. It does not automatically reject `4xx` or `5xx`.
- Use `error_for_status_ref()` when you need to inspect or log the body on failure before consuming the response.
- Use `bytes().await?` for binary bodies, `text().await?` for text, and `json::<T>().await?` only for trusted JSON contracts.
- Do not log full URLs or errors blindly when query strings may contain secrets. `reqwest::Error` supports `without_url()` and `with_url()`.

## Error Classification

Reqwest errors carry useful classifiers. Preserve them in domain errors instead of flattening everything to a string.

```rust
fn classify_reqwest_error(error: &reqwest::Error) -> &'static str {
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
}
```

- Use `error.status()` to preserve HTTP status when the error came from `error_for_status`.
- Treat timeout, connect, body, decode, redirect, and status failures differently in retry logic and metrics.
- Strip sensitive URLs before returning errors to users or structured logs.

## Streaming

Use streaming APIs for large downloads and uploads. Avoid loading unbounded bodies into memory with `bytes()` or `text()`.

```rust
use tokio::io::AsyncWriteExt;

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
}
```

- Use a temporary file plus atomic rename when partial downloads must not be observed as complete files.
- Enforce maximum byte counts for untrusted responses.
- Preserve cancellation behavior; dropping the response should stop the download.
- Prefer `bytes_stream()` when integrating with stream combinators, backpressure-aware pipelines, or hashing/decompression stages.

## Blocking API

Enable `blocking` only for synchronous binaries or integration points that cannot be async.

```toml
reqwest = { version = "0.13", features = ["blocking", "json"] }
```

```rust
fn fetch_text(url: &str) -> reqwest::Result<String> {
    reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()?
        .get(url)
        .send()?
        .error_for_status()?
        .text()
}
```

- Do not call `reqwest::blocking` directly inside Tokio async tasks; it can panic when attempting to block.
- If the caller is async but a legacy synchronous dependency is unavoidable, isolate it with `tokio::task::spawn_blocking`.
- Reuse a blocking `Client` for repeated requests to keep connection pooling.

## TLS

- Prefer Rustls for portable server/CLI binaries unless the deployment needs platform certificate stores or native client identity behavior.
- If an exact backend matters, enable that backend feature and call `tls_backend_rustls()` or `tls_backend_native()` on the builder.
- Use `native-tls` carefully on Linux because it depends on OpenSSL availability unless vendored.
- Add custom server roots through `Certificate` and client certificates through `Identity`.
- Avoid disabling certificate validation. For tests, prefer local test CAs or mock HTTP servers.
- `tls_backend_preconfigured()` is advanced and has no semver-stable internals; use builder methods when possible.

## Bodies and Forms

- Use `.json(&value)` for JSON request bodies; it requires `serde::Serialize` and the `json` feature.
- Use `.query(&value)` for query strings; it requires the `query` feature in v0.13.
- Use `.form(&value)` for `application/x-www-form-urlencoded` bodies; it requires the `form` feature in v0.13.
- Use `multipart::Form` for file uploads and enable the `multipart` feature.
- Use `Body` or streaming bodies for large uploads; do not read large files fully into memory.
- Set explicit headers only when needed. Let reqwest set `Content-Type` for JSON, forms, and multipart unless a server requires a specific override.

## Retries

Reqwest does not make application retry policy magically safe. Implement retries above reqwest with explicit rules.

- Retry only idempotent requests by default: `GET`, `HEAD`, safe `PUT`, or operations with idempotency keys.
- Do not retry generic `POST` without an idempotency key or duplicate-safe server contract.
- Classify `is_timeout`, `is_connect`, `status()`, and response bodies before retrying.
- Use jittered exponential backoff and a bounded retry budget.
- Do not retry after a request body stream has been partially consumed unless it is replayable.

## Testing

- Use a local mock HTTP server for request method/path/header/body assertions.
- Test timeout and retry paths separately from success parsing.
- Test status handling by asserting `error_for_status` behavior and preserved status codes.
- Avoid tests that depend on public internet endpoints.
- For TLS behavior, use a local test CA or explicit test certificates instead of disabling validation.

## Helper Script

Generate starter snippets without loading extra context:

```bash
bash /mnt/skills/user/reqwest-rust/scripts/reqwest-rust-bootstrap.sh client
bash /mnt/skills/user/reqwest-rust/scripts/reqwest-rust-bootstrap.sh json
bash /mnt/skills/user/reqwest-rust/scripts/reqwest-rust-bootstrap.sh stream
bash /mnt/skills/user/reqwest-rust/scripts/reqwest-rust-bootstrap.sh blocking
bash /mnt/skills/user/reqwest-rust/scripts/reqwest-rust-bootstrap.sh classify
```

The script prints JSON with a `scenario`, `cargo`, and `snippet` field.

## Review Checklist

- Is `Client` reused instead of rebuilt per request?
- Are `connect_timeout`, whole-request `timeout`, TLS backend, redirect policy, and user agent explicit?
- Does code call `error_for_status()` or intentionally handle non-2xx statuses?
- Are large bodies streamed with byte limits instead of buffered unboundedly?
- Are sensitive URLs stripped from errors and logs?
- Is blocking reqwest kept out of async runtime tasks?
- Are retries limited to replayable/idempotent operations with backoff and budgets?
- Are TLS verification shortcuts absent from production code?

## Sources

- `https://github.com/seanmonstar/reqwest`
- `https://docs.rs/reqwest/latest/reqwest/`
- `https://docs.rs/reqwest/latest/reqwest/struct.Client.html`
- `https://docs.rs/reqwest/latest/reqwest/struct.ClientBuilder.html`
- `https://docs.rs/reqwest/latest/reqwest/struct.Response.html`
- `https://docs.rs/reqwest/latest/reqwest/struct.Error.html`
- `https://docs.rs/reqwest/latest/reqwest/blocking/index.html`
- `https://docs.rs/reqwest/latest/reqwest/tls/index.html`
- `https://docs.rs/crate/reqwest/latest/features`
