---
name: tower-rust
description: Use when building or modifying Rust services and middleware with tower: Service, Layer, ServiceBuilder, readiness, backpressure, timeouts, buffers, load shedding, concurrency/rate limits, retries, boxed services, testing, or integrating tower with axum, tonic, hyper, or custom protocols.
---

# Tower Rust

Use these conventions for Rust request/response services built with `tower-rs/tower`.

## Source Baseline

- Prefer released docs from `docs.rs/tower`, crates.io, and the matching GitHub release over examples from old blog posts or older crate snippets.
- Current docs.rs baseline checked for this skill: `tower 0.5.3`.
- Current GitHub release baseline checked for this skill: `tower 0.5.3`.
- Tower is protocol-agnostic middleware for request/response systems. It fits HTTP, gRPC, RPC, and queue-style request handling.
- Tower is usually the wrong core abstraction for protocols that are entirely stream based and do not naturally expose discrete requests and responses.
- `tower` itself is not `no_std`; `tower-layer` and `tower-service` are `no_std`.
- Tower's documented MSRV is `1.64.0`, but downstream frameworks may require newer Rust versions.

## Cargo

Start with only the features you need. Use `full` for prototypes, examples, and throwaway experiments, then narrow before production.

```toml
[dependencies]
tower = { version = "0.5", features = ["util", "timeout", "limit", "load-shed"] }
```

Common feature choices:

- `util` provides `ServiceExt`, `service_fn`, boxed services, and utility adapters.
- `timeout` aborts slow response futures after a configured duration.
- `limit` provides concurrency and rate limiting middleware.
- `load-shed` returns an error immediately when the inner service is not ready.
- `buffer` adds an mpsc-backed queue and makes a service cheap to clone across tasks.
- `retry` wraps a service with an explicit retry `Policy`.
- `make` helps construct services per target, connection, or request context.
- `balance`, `discover`, `load`, and `ready-cache` are useful for dynamic endpoint pools.
- `reconnect`, `spawn-ready`, and `steer` are specialized tools for connection management and routing.

## Core Model

`Service<Request>` is an asynchronous function from a request to a response result. It has associated `Response`, `Error`, and `Future` types.

```rust
use tower::{service_fn, BoxError, Service, ServiceExt};

async fn call_service() -> Result<String, BoxError> {
    let mut svc = service_fn(|request: String| async move {
        Ok::<_, BoxError>(format!("hello {request}"))
    });

    let response = svc.ready().await?.call("tower".to_owned()).await?;
    Ok(response)
}
```

Rules that matter in reviews:

- Always drive readiness before calling: `svc.ready().await?.call(request).await?`.
- `Service::call` may panic if called before `poll_ready` has returned `Poll::Ready(Ok(()))`.
- `poll_ready` can reserve capacity that the following `call` consumes. If cancellation happens between readiness and call, the service implementation must release that reservation.
- `Poll::Ready(Err(_))` means the service cannot process further requests; discard that instance.
- Be careful cloning a ready service. The clone may not be ready, even when the original is. If a ready inner service must move into a future, use a replacement pattern instead of calling an unready clone.
- Prefer `ServiceExt::oneshot(request)` for one-off calls where consuming the service is acceptable.

## ServiceBuilder

Use `ServiceBuilder` for ordinary middleware stacks. Keep ordering intentional and cover it with tests when timeouts, error mapping, load shedding, and retry interact.

```rust
use std::time::Duration;
use tower::{BoxError, ServiceBuilder};

let svc = ServiceBuilder::new()
    .load_shed()
    .concurrency_limit(64)
    .timeout(Duration::from_secs(5))
    .service_fn(|request: String| async move {
        Ok::<_, BoxError>(format!("handled {request}"))
    });
```

- Put capacity and overload behavior near the front of the design. Decide whether callers should wait, fail fast, or retry elsewhere.
- Use small, explicit limits. Unbounded buffering hides overload and increases tail latency.
- Avoid boxing in the middle of generic code. Use `BoxService` or `BoxCloneService` at public boundaries, dynamic registries, or places where type names become unmanageable.
- When wrapping framework services, check the framework's expected error type and response conversion rules.

## Middleware Selection

- `timeout`: use for per-request response deadlines. It fails when the response future does not complete in time.
- `concurrency_limit`: use to cap in-flight requests. Capacity is held until the response future completes.
- `rate_limit`: use for fixed-rate admission over a duration. It is not a distributed rate limiter.
- `load_shed`: use when overload should fail immediately instead of queueing.
- `buffer`: use when one service must be shared by cloned handles or driven from many tasks. Choose queue capacity deliberately and account for memory and latency.
- `retry`: use only for idempotent or explicitly retry-safe operations. Add budgets, backoff, and careful response/error classification.
- `filter`: use to reject or transform requests before calling the inner service.
- `make`: use when each connection, target, or tenant needs its own service value.

## Retry Policy

Tower retries are explicit. A `Policy` decides whether a result should be retried, whether the request can be cloned, and whether to wait before the next attempt.

```rust
use std::future::{self, Ready};
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
}
```

- If `clone_request` returns `None`, Tower cannot retry that request.
- Do not retry non-idempotent writes unless the operation is explicitly safe under duplicate execution.
- Treat response-based retries separately from transport failures. A `500`, `Status::unavailable`, timeout, and application validation error usually have different retry semantics.
- Add jittered backoff for real network retries instead of immediate tight loops.

## Implementing Services

Keep service implementations explicit about readiness, error type, and future type.

```rust
use std::future::Ready;
use std::task::{Context, Poll};
use tower::Service;

#[derive(Clone, Default)]
struct Echo;

impl Service<String> for Echo {
    type Response = String;
    type Error = std::convert::Infallible;
    type Future = Ready<Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, _cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        Poll::Ready(Ok(()))
    }

    fn call(&mut self, request: String) -> Self::Future {
        std::future::ready(Ok(request))
    }
}
```

- Delegate `poll_ready` through wrappers unless the wrapper owns capacity or admission.
- Do not do expensive work in `poll_ready`; it may be polled repeatedly.
- If `call` returns a future that borrows from `self`, prefer boxing or restructure ownership so the future is valid for the framework using it.
- For wrappers around an inner service, if readiness of the exact inner instance matters, avoid calling a freshly cloned inner service.

## Implementing Layers

Use `Layer` for reusable middleware configuration. Layers should usually be cheap to clone and should hold configuration, not request state.

```rust
use std::task::{Context, Poll};
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

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Req) -> Self::Future {
        tracing::trace!("calling inner service");
        self.inner.call(request)
    }
}
```

## Framework Integration

- Axum middleware and routers are Tower services. Ensure middleware errors become HTTP responses; axum handlers normally want infallible services at the router boundary.
- Tonic clients and servers are Tower-based. Map middleware failures to `tonic::Status` before they cross a gRPC API boundary.
- Hyper integrations should respect body types, connection lifetime, and backpressure. Do not hide body streaming behind a request/response helper that buffers the entire body unless that is intentional.
- For custom protocols, define a request and response type that preserves cancellation, deadlines, metadata, and tracing context.

## Testing

- Use `tower::service_fn` for small focused tests.
- Use `ServiceExt::oneshot` for one-request assertions.
- Use `tower-test` mock services when verifying readiness, backpressure, or wrapper behavior.
- Test overload paths explicitly: not ready, load shed, timeout, retry exhausted, buffer closed, and inner service error.
- Use Tokio's paused time tools for timeout and backoff tests when the crate already uses Tokio tests.

## Helper Script

Generate starter snippets without loading extra context:

```bash
bash /mnt/skills/user/tower-rust/scripts/tower-rust-bootstrap.sh basic
bash /mnt/skills/user/tower-rust/scripts/tower-rust-bootstrap.sh builder
bash /mnt/skills/user/tower-rust/scripts/tower-rust-bootstrap.sh service
bash /mnt/skills/user/tower-rust/scripts/tower-rust-bootstrap.sh layer
bash /mnt/skills/user/tower-rust/scripts/tower-rust-bootstrap.sh retry
```

The script prints JSON with a `scenario`, `cargo`, and `snippet` field.

## Review Checklist

- Does every direct `call` happen after readiness?
- Are overload semantics explicit: wait, shed, buffer, limit, or retry?
- Are buffers bounded, monitored, and acceptable for latency?
- Are retries restricted to safe operations with request cloning and retry budget handled?
- Are framework boundary errors converted to `Response`, `Status`, or the expected domain error?
- Is boxing used only where it reduces public type complexity?
- Do tests cover readiness/backpressure, timeout, load-shed, retry, and inner-error behavior?

## Sources

- `https://github.com/tower-rs/tower`
- `https://docs.rs/tower/latest/tower/`
- `https://docs.rs/tower/latest/tower/trait.Service.html`
- `https://docs.rs/tower/latest/tower/struct.ServiceBuilder.html`
- `https://docs.rs/tower/latest/tower/retry/trait.Policy.html`
