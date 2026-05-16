#!/bin/bash
set -e

scenario="${1:-basic}"

cargo_full='tower = { version = "0.5", features = ["full"] }'

case "$scenario" in
  basic)
    cargo='tower = { version = "0.5", features = ["util"] }'
    snippet='use tower::{service_fn, BoxError, Service, ServiceExt};

async fn call_service() -> Result<String, BoxError> {
    let mut svc = service_fn(|request: String| async move {
        Ok::<_, BoxError>(format!("hello {request}"))
    });

    let response = svc.ready().await?.call("tower".to_owned()).await?;
    Ok(response)
}'
    ;;
  builder)
    cargo='tower = { version = "0.5", features = ["util", "timeout", "limit", "load-shed"] }'
    snippet='use std::time::Duration;
use tower::{BoxError, ServiceBuilder};

let svc = ServiceBuilder::new()
    .load_shed()
    .concurrency_limit(64)
    .timeout(Duration::from_secs(5))
    .service_fn(|request: String| async move {
        Ok::<_, BoxError>(format!("handled {request}"))
    });'
    ;;
  service)
    cargo='tower = "0.5"'
    snippet='use std::future::Ready;
use std::task::{Context, Poll};
use tower::Service;

#[derive(Clone, Default)]
struct Echo;

impl Service<String> for Echo {
    type Response = String;
    type Error = std::convert::Infallible;
    type Future = Ready<Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, _cx: &mut Context<'"'"'_>) -> Poll<Result<(), Self::Error>> {
        Poll::Ready(Ok(()))
    }

    fn call(&mut self, request: String) -> Self::Future {
        std::future::ready(Ok(request))
    }
}'
    ;;
  layer)
    cargo='tower = "0.5"'
    snippet='use std::task::{Context, Poll};
use tower::{Layer, Service};

#[derive(Clone)]
struct TraceLayer;

impl<S> Layer<S> for TraceLayer {
    type Service = TraceService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        TraceService { inner }
    }
}

#[derive(Clone)]
struct TraceService<S> {
    inner: S,
}

impl<S, Req> Service<Req> for TraceService<S>
where
    S: Service<Req>,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = S::Future;

    fn poll_ready(&mut self, cx: &mut Context<'"'"'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Req) -> Self::Future {
        tracing::trace!("calling inner service");
        self.inner.call(request)
    }
}'
    ;;
  retry)
    cargo='tower = { version = "0.5", features = ["retry"] }'
    snippet='use std::future::{self, Ready};
use tower::retry::Policy;

#[derive(Clone)]
struct Attempts {
    remaining: usize,
}

impl<Req, Res, E> Policy<Req, Res, E> for Attempts
where
    Req: Clone,
{
    type Future = Ready<()>;

    fn retry(&mut self, _req: &mut Req, result: &mut Result<Res, E>) -> Option<Self::Future> {
        if result.is_err() && self.remaining > 0 {
            self.remaining -= 1;
            Some(future::ready(()))
        } else {
            None
        }
    }

    fn clone_request(&mut self, req: &Req) -> Option<Req> {
        Some(req.clone())
    }
}'
    ;;
  *)
    echo "Usage: $0 [basic|builder|service|layer|retry]" >&2
    exit 2
    ;;
esac

SCENARIO="$scenario" CARGO="$cargo" CARGO_FULL="$cargo_full" SNIPPET="$snippet" python3 <<'PY'
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "cargo": os.environ["CARGO"],
    "prototype_cargo": os.environ["CARGO_FULL"],
    "snippet": os.environ["SNIPPET"],
}, indent=2))
PY
