---
name: tonic-rust
description: Use when building or modifying Rust gRPC services with tonic: protobuf codegen, tonic-prost-build, build.rs, include_proto!, clients, servers, streaming RPCs, metadata, interceptors, TLS, compression, health checks, reflection, or gRPC error handling.
---

# Tonic Rust

Use these conventions for Rust gRPC clients and servers built with `hyperium/tonic`.

## Source Baseline

- Prefer released docs from `docs.rs/tonic`, crates.io, and the matching release branch.
- Treat GitHub `master` carefully: tonic notes that `master` is preparing breaking changes. For released code, check the `v0.14.x` branch.
- Current docs.rs baseline checked for this skill: `tonic 0.14.6`, `tonic-prost-build 0.14.6`, MSRV `1.88`.
- Tonic is gRPC over HTTP/2 built on Tokio, Hyper, Tower, and Prost.
- For protobuf compilation through Prost, use `tonic-prost-build`; `tonic-build` now points users to `tonic-prost-build` for `.proto` compilation.

## Cargo

Use pinned compatible crate families. Start narrow and add features intentionally.

```toml
[dependencies]
tonic = "0.14"
tonic-prost = "0.14"
prost = "0.14"
tokio = { version = "1", features = ["macros", "rt-multi-thread", "signal"] }
tracing = "0.1"

[build-dependencies]
tonic-prost-build = "0.14"
```

Common feature choices:

- `transport` is enabled by default and provides the client `Channel` and server `Server`.
- `server` or `channel` can be used instead of full `transport` when narrowing generated surfaces.
- `tls-ring` or `tls-aws-lc` enables rustls TLS; add `tls-native-roots` or `tls-webpki-roots` for client trust roots.
- `gzip`, `deflate`, and `zstd` enable gRPC compression support. Use only when both sides support it.
- Add `tonic-health` for the standard gRPC health service.
- Add `tonic-reflection` when clients need server reflection, grpcurl discovery, or operational introspection.

## Proto and Codegen

Keep `.proto` files in a stable root such as `proto/`. The `package` name must match the string passed to `tonic::include_proto!`.

```proto
syntax = "proto3";
package helloworld;

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply);
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
```

Add `build.rs` at the crate root:

```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_prost_build::compile_protos("proto/helloworld.proto")?;
    Ok(())
}
```

Use `configure()` when you need include roots, client/server-only generation, descriptor sets, external paths, custom derives, or generated-code placement:

```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_prost_build::configure()
        .compile_protos(&["proto/helloworld.proto"], &["proto"])?;
    Ok(())
}
```

- Ensure `protoc` is available in CI and developer machines.
- On NixOS or hermetic builders, set `PROTOC` and `PROTOC_INCLUDE` explicitly.
- Do not hand-edit generated files under `OUT_DIR`; change the proto or build configuration.
- Rebuild after proto changes and commit updated checked-in generated files only if the repository intentionally stores generated code.

## Generated Modules

Use `include_proto!` in a stable module and keep it close to the service/client code:

```rust
pub mod helloworld {
    tonic::include_proto!("helloworld");
}
```

- The string must match the `.proto` package exactly.
- Generated modules expose `*_client`, `*_server`, request/response messages, and service traits.
- Wrap generated modules behind application modules if you need a cleaner public API.

## Server

Implement generated service traits with `#[tonic::async_trait]`, return `Result<Response<T>, Status>`, and add generated server services to `Server::builder()`.

```rust
use tonic::{transport::Server, Request, Response, Status};

use helloworld::greeter_server::{Greeter, GreeterServer};
use helloworld::{HelloReply, HelloRequest};

pub mod helloworld {
    tonic::include_proto!("helloworld");
}

#[derive(Debug, Default)]
struct GreeterService;

#[tonic::async_trait]
impl Greeter for GreeterService {
    async fn say_hello(
        &self,
        request: Request<HelloRequest>,
    ) -> Result<Response<HelloReply>, Status> {
        let name = request.into_inner().name;
        Ok(Response::new(HelloReply {
            message: format!("Hello {name}!"),
        }))
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;

    Server::builder()
        .add_service(GreeterServer::new(GreeterService))
        .serve(addr)
        .await?;

    Ok(())
}
```

- Keep RPC implementations thin; delegate business logic to services/repositories.
- Use `Request::metadata()`, `extensions()`, `remote_addr()`, and `peer_certs()` for transport/request context when features support it.
- Map domain errors to `Status` intentionally. Do not turn every error into `Status::internal`.
- Use `serve_with_shutdown` for deployable binaries that need graceful shutdown.

## Client

Use generated clients and wrap messages in `tonic::Request` when you need metadata, deadlines, or extensions.

```rust
use helloworld::greeter_client::GreeterClient;
use helloworld::HelloRequest;

pub mod helloworld {
    tonic::include_proto!("helloworld");
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut client = GreeterClient::connect("http://[::1]:50051").await?;

    let mut request = tonic::Request::new(HelloRequest {
        name: "Tonic".to_owned(),
    });
    request.set_timeout(std::time::Duration::from_secs(5));

    let response = client.say_hello(request).await?;
    tracing::info!(?response, "received gRPC response");

    Ok(())
}
```

- Prefer constructing a reusable `Channel` for clients used repeatedly.
- Set per-request deadlines with `Request::set_timeout` or channel/service timeout layers.
- Add metadata through `request.metadata_mut()` for auth and request context.
- Use TLS for non-local traffic; `https://` endpoints need the appropriate TLS features and roots.

## Streaming

Tonic supports unary, server streaming, client streaming, and bidirectional streaming.

- For response streams, return a stream of `Result<Message, Status>`.
- For client streams, consume `tonic::Streaming<T>` from the request body.
- Use bounded channels for application-produced streams so slow clients apply backpressure.
- Do not spawn unbounded stream producers without cancellation handling.
- Treat `Status::cancelled` and dropped streams as normal client behavior when clients disconnect.

```rust
use tokio_stream::wrappers::ReceiverStream;

type ResponseStream = ReceiverStream<Result<HelloReply, tonic::Status>>;

async fn lots_of_replies(
    &self,
    request: tonic::Request<HelloRequest>,
) -> Result<tonic::Response<ResponseStream>, tonic::Status> {
    let name = request.into_inner().name;
    let (tx, rx) = tokio::sync::mpsc::channel(8);

    tokio::spawn(async move {
        let _ = tx
            .send(Ok(HelloReply {
                message: format!("Hello {name}!"),
            }))
            .await;
    });

    Ok(tonic::Response::new(ReceiverStream::new(rx)))
}
```

## Metadata, Interceptors, and Extensions

- Use metadata for gRPC headers: auth tokens, tenant IDs, request IDs, and routing hints.
- Use interceptors for simple metadata validation/injection. Keep heavy async auth in Tower middleware or service code because interceptors are not a replacement for full async middleware.
- Use `Request::extensions_mut()` to attach typed per-request data from interceptors or Tower layers.
- Extensions must be cloneable when inserted by interceptors.

```rust
#[derive(Clone)]
struct AuthToken(String);

fn auth_interceptor(
    mut request: tonic::Request<()>,
) -> Result<tonic::Request<()>, tonic::Status> {
    let token = request
        .metadata()
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| tonic::Status::unauthenticated("missing authorization"))?
        .to_owned();

    request.extensions_mut().insert(AuthToken(token));
    Ok(request)
}
```

## Middleware and Tower

- Tonic transport is Tower-based. Use Tower layers for timeouts, tracing, concurrency limits, load shedding, and auth.
- Put limits and timeouts close to the boundary, then map Tower errors to appropriate gRPC `Status`.
- Be deliberate with backpressure: gRPC streams can stay open for a long time.
- Share middleware patterns with axum/hyper services where the types line up, but verify tonic error/status conversion.

## TLS, Compression, and Limits

- Enable TLS with `tls-ring` or `tls-aws-lc`; add root features for clients that need system/webpki roots.
- For mTLS, configure client identity and server/client certificate authorities through tonic transport TLS config.
- Use compression only when both client and server are configured for the same algorithms.
- Review message limits for large protobufs. Tonic defaults to a 4 MB decoding limit and effectively unlimited encoding limit; set explicit max encoding/decoding sizes when messages may be large or untrusted.

## Health and Reflection

- Add `tonic-health` to expose the standard health checking service for load balancers and orchestration.
- Add `tonic-reflection` when operational tools need to discover services, methods, and descriptors.
- Generate and include descriptor sets when reflection needs schema data.

## Testing

- Unit test service implementation directly by constructing `Request<T>` and asserting `Response<T>` or `Status`.
- Integration test client/server behavior by binding to `127.0.0.1:0` or a Unix socket and using the generated client.
- Test metadata, deadlines, max-message limits, and streaming cancellation explicitly.
- Use `grpcurl` with `-plaintext`, `-import-path`, and `-proto` for quick manual checks against local plaintext servers.

## Review Checklist

- Released tonic API checked against `docs.rs` or `v0.14.x`, not only `master`.
- `tonic-prost-build` is used for protobuf compilation through Prost.
- `include_proto!` package string matches the `.proto` package.
- `protoc` availability is documented for local and CI builds.
- RPC handlers return precise `Status` codes.
- Request metadata and extensions are used intentionally, not as untyped global state.
- Streaming RPCs use bounded channels/backpressure and handle cancellation.
- TLS, compression, and message limits are explicit for production traffic.
- Health/reflection are included when operations or clients need them.
- Tests cover generated client/server paths, not only pure domain logic.

## Helper Script

Use the helper for compact scaffold snippets:

```bash
bash /mnt/skills/user/tonic-rust/scripts/tonic-rust-bootstrap.sh proto
bash /mnt/skills/user/tonic-rust/scripts/tonic-rust-bootstrap.sh build
bash /mnt/skills/user/tonic-rust/scripts/tonic-rust-bootstrap.sh server
bash /mnt/skills/user/tonic-rust/scripts/tonic-rust-bootstrap.sh client
```
