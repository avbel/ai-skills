#!/bin/bash
set -euo pipefail

scenario="${1:-server}"

case "$scenario" in
  proto|build|server|client|streaming)
    ;;
  *)
    echo "Unsupported scenario: $scenario. Use proto, build, server, client, or streaming." >&2
    exit 2
    ;;
esac

echo "Preparing tonic scaffold for $scenario" >&2

case "$scenario" in
  proto)
    snippet=$(cat <<PROTO
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
PROTO
)
    ;;
  build)
    snippet=$(cat <<RUST
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_prost_build::compile_protos("proto/helloworld.proto")?;
    Ok(())
}
RUST
)
    ;;
  server)
    snippet=$(cat <<RUST
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
RUST
)
    ;;
  client)
    snippet=$(cat <<RUST
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
RUST
)
    ;;
  streaming)
    snippet=$(cat <<RUST
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
RUST
)
    ;;
esac

SCENARIO="$scenario" SNIPPET="$snippet" python3 <<PY
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "dependencies": {
        "runtime": "tokio = { version = \"1\", features = [\"macros\", \"rt-multi-thread\", \"signal\"] }",
        "grpc": ["tonic = \"0.14\"", "tonic-prost = \"0.14\"", "prost = \"0.14\""],
        "build": "tonic-prost-build = \"0.14\""
    },
    "snippet": os.environ["SNIPPET"],
    "reminders": [
        "Use docs.rs or v0.14.x for released APIs; tonic master may contain breaking changes.",
        "The include_proto! string must match the proto package.",
        "Install protoc or set PROTOC/PROTOC_INCLUDE in hermetic builds.",
        "Map domain failures to precise tonic::Status codes."
    ]
}, indent=2))
PY
