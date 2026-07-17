---
name: opentelemetry-rust
description: Use when building or reviewing Rust OpenTelemetry instrumentation with open-telemetry/opentelemetry-rust: traces, metrics, logs, OTLP exporters, stdout exporters, resources, propagation, sampling, tracing/log bridges, observable instruments, shutdown, and production telemetry configuration.
---

# OpenTelemetry Rust

Use these conventions for Rust services instrumented with `open-telemetry/opentelemetry-rust`.

## Source Baseline

- Prefer released docs from `docs.rs`, crates.io, and the matching GitHub release over older examples.
- Current core crate baseline checked for this skill: `opentelemetry 0.32.0`, `opentelemetry_sdk 0.32.0`, `opentelemetry-otlp 0.32.0`.
- Current companion crate lag checked for this skill: `opentelemetry-stdout 0.31.0`, `opentelemetry-appender-tracing 0.31.1`. Do not mix those `0.31` companion crates with a `0.32` SDK unless their compatibility has been verified in the target project.
- Current MSRV on the 0.32 crate pages is `1.75.0`.
- OpenTelemetry creates, manages, and exports telemetry. It is not a storage or visualization backend.
- Library crates should normally depend on `opentelemetry` only. Applications add `opentelemetry_sdk` and exporter crates.
- The `opentelemetry` crate is the API/facade and includes no-op behavior until an SDK provider is installed.
- The SDK builds providers and processors; exporters such as `opentelemetry-otlp` or `opentelemetry-stdout` send telemetry somewhere.

## Cargo

When using only core/SDK/OTLP, prefer the current `0.32` family:

```toml
[dependencies]
opentelemetry = { version = "0.32", features = ["trace", "metrics"] }
opentelemetry_sdk = { version = "0.32", features = ["trace", "metrics"] }
```

For stdout local verification, align the crate family with the latest released stdout crate unless a newer compatible stdout release exists:

```toml
[dependencies]
opentelemetry = { version = "0.31", features = ["trace", "metrics"] }
opentelemetry_sdk = { version = "0.31", features = ["trace", "metrics"] }
opentelemetry-stdout = { version = "0.31", features = ["trace", "metrics"] }
```

For production OTLP over HTTP/protobuf:

```toml
[dependencies]
opentelemetry = { version = "0.32", features = ["trace", "metrics", "logs"] }
opentelemetry_sdk = { version = "0.32", features = ["trace", "metrics", "logs"] }
opentelemetry-otlp = { version = "0.32", features = ["trace", "metrics", "logs", "http-proto", "reqwest-blocking-client"] }
opentelemetry-semantic-conventions = "0.32"
```

Common companion crates:

- `opentelemetry-stdout`: local verification exporter for traces, metrics, and logs. Check version alignment first; latest checked release was `0.31.0`.
- `opentelemetry-otlp`: OTLP exporter for production collectors/backends.
- `opentelemetry-prometheus`: Prometheus metrics exporter.
- `opentelemetry-http`: helpers for HTTP propagation.
- `opentelemetry-semantic-conventions`: standardized attribute and resource names.
- `opentelemetry-appender-tracing`: bridge `tracing` events into OpenTelemetry logs. Check version alignment first; latest checked release was `0.31.1`.
- `tracing-opentelemetry`: common bridge from `tracing` spans to OpenTelemetry traces.

## Application Setup

Create telemetry once at process startup, install global providers only after configuration succeeds, and keep provider handles so shutdown can flush data.

```rust
use opentelemetry::trace::{Tracer, TracerProvider};
use opentelemetry_sdk::{trace::SdkTracerProvider, Resource};

fn init_tracer_provider() -> SdkTracerProvider {
    let exporter = opentelemetry_stdout::SpanExporter::default();

    SdkTracerProvider::builder()
        .with_resource(
            Resource::builder()
                .with_service_name("my-service")
                .build(),
        )
        .with_simple_exporter(exporter)
        .build()
}

fn main() {
    let provider = init_tracer_provider();
    let tracer = provider.tracer("my-service");

    tracer.in_span("startup", |_cx| {
        // Application work here.
    });

    provider.shutdown().expect("tracer provider should shut down");
}
```

- Use stdout exporters to prove instrumentation works before switching to OTLP, but keep the OpenTelemetry crate family version-aligned.
- Use simple exporters for tests and tiny local examples; use batch exporters/processors for production.
- Store provider handles in an application telemetry struct. Do not hide them in a temporary scope.
- Shutdown every provider during graceful shutdown so batched telemetry flushes.

## OTLP Export

Prefer OTLP through the OpenTelemetry Collector or an OTLP-compatible backend.

```rust
use std::time::Duration;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{trace::SdkTracerProvider, Resource};

fn init_otlp_traces() -> Result<SdkTracerProvider, Box<dyn std::error::Error + Send + Sync>> {
    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_http()
        .with_endpoint("http://localhost:4318/v1/traces")
        .with_timeout(Duration::from_secs(5))
        .build()?;

    let provider = SdkTracerProvider::builder()
        .with_resource(
            Resource::builder()
                .with_service_name("my-service")
                .build(),
        )
        .with_batch_exporter(exporter)
        .build();

    Ok(provider)
}
```

- Default OTLP HTTP port is usually `4318`; default OTLP gRPC port is usually `4317`.
- Use signal-specific endpoints when configuring exporters directly: `/v1/traces`, `/v1/metrics`, `/v1/logs`.
- Keep endpoints, headers, timeouts, compression, and sampling policy in config or environment variables.
- For gRPC OTLP, use the `grpc-tonic` feature and `.with_tonic()`.
- Do not point every service directly at a vendor unless the deployment intentionally skips the Collector.

## Resources

Every process needs a stable `service.name`. Use `service.version`, `deployment.environment`, region, and tenant attributes when they are bounded and operationally useful.

```rust
use opentelemetry_sdk::Resource;

let resource = Resource::builder()
    .with_service_name("checkout-api")
    .with_attribute(opentelemetry::KeyValue::new("service.version", env!("CARGO_PKG_VERSION")))
    .with_attribute(opentelemetry::KeyValue::new("deployment.environment", "production"))
    .build();
```

- `OTEL_SERVICE_NAME` takes priority over `service.name` from `OTEL_RESOURCE_ATTRIBUTES`.
- Keep deployment-specific values environment-driven when the repo already has config plumbing.
- Use semantic conventions when available instead of inventing adjacent names.

## Traces

Use manual spans for business operations and rely on `tracing` or instrumentation libraries for framework spans when available.

```rust
use opentelemetry::{global, trace::{Span, Tracer}, KeyValue};

fn charge_order(order_id: &str) {
    let tracer = global::tracer("orders");
    let mut span = tracer.start("charge_order");
    span.set_attribute(KeyValue::new("order.id", order_id.to_owned()));

    // Work here.

    span.end();
}
```

- Always end spans, or use helpers that end them when scope exits.
- Record errors and set error status when the operation fails.
- Avoid high-cardinality attributes such as raw URL, user email, access token, unbounded object ID, or full SQL text.
- For async Rust services already using `tracing`, prefer a `tracing` bridge over scattered manual span management.

## Metrics

Create instruments from a named meter and keep attribute cardinality bounded.

```rust
use opentelemetry::{global, KeyValue};
use opentelemetry_sdk::{metrics::SdkMeterProvider, Resource};

fn init_meter_provider() -> SdkMeterProvider {
    let exporter = opentelemetry_stdout::MetricExporterBuilder::default().build();

    let provider = SdkMeterProvider::builder()
        .with_resource(
            Resource::builder()
                .with_service_name("my-service")
                .build(),
        )
        .with_periodic_exporter(exporter)
        .build();

    global::set_meter_provider(provider.clone());
    provider
}

fn record_checkout() {
    let meter = global::meter("checkout");
    let counter = meter.u64_counter("checkout.started").build();
    counter.add(1, &[KeyValue::new("checkout.kind", "card")]);
}
```

- Use counters for monotonic counts, up-down counters for values that rise and fall, histograms for durations/sizes, and observable instruments for values read during collection.
- Use units consistently: seconds, milliseconds, bytes, items.
- Do not create instruments per request. Build them once and reuse them.
- For observable gauges/counters/up-down counters, keep the handle returned by `.build()` alive for the process lifetime. Dropping observable handles can unregister instruments and has caused SDK pipeline memory growth in real services. Bind handles to `_name`, not bare `_`, and drop them after provider shutdown. The `otel-observable-handles-rust` skill covers this keep-alive pattern in depth.

## Logs

OpenTelemetry Rust logs are active, but bridge crates can lag core crate versions. Check exact crate compatibility before wiring logs into a production pipeline.

- For `tracing` applications, use `opentelemetry-appender-tracing` to bridge events into OpenTelemetry logs when versions align.
- Keep a normal `tracing_subscriber::fmt` or existing logging layer for local diagnostics unless the service has a reason to export only OTel logs.
- Filter exporter/client internals such as `hyper`, `tonic`, `h2`, and `reqwest` carefully to avoid telemetry-induced log loops.
- Do not replace a mature production logging path with OTel logs unless the deployment and backend are ready for it.

## Propagation

- Use existing instrumentation libraries for HTTP/gRPC propagation when possible.
- For custom transports, inject and extract OpenTelemetry context through the propagation API or `opentelemetry-http` helpers.
- Do not invent custom trace headers unless bridging to a known legacy protocol.
- Verify propagation in tests by asserting a downstream span joins the incoming trace rather than starting a new trace.

## Sampling

- Default local examples can sample everything.
- Production services should configure sampling intentionally through environment or central config.
- Prefer parent-based sampling at service boundaries unless there is a strong reason to break upstream decisions.
- Keep sampling policy separate from business logic.

## Shutdown

- Call `shutdown()` on tracer, meter, and logger providers during graceful shutdown.
- Shutdown after the application stops accepting new work, but before process exit.
- Keep observable instrument handles alive until after metric provider shutdown (see `otel-observable-handles-rust`).
- Treat shutdown errors as operational diagnostics; do not hide repeated exporter failures.

## Helper Script

Generate starter snippets without loading extra context:

```bash
bash /mnt/skills/user/opentelemetry-rust/scripts/opentelemetry-rust-bootstrap.sh stdout-trace
bash /mnt/skills/user/opentelemetry-rust/scripts/opentelemetry-rust-bootstrap.sh otlp-http
bash /mnt/skills/user/opentelemetry-rust/scripts/opentelemetry-rust-bootstrap.sh metrics
bash /mnt/skills/user/opentelemetry-rust/scripts/opentelemetry-rust-bootstrap.sh manual-span
bash /mnt/skills/user/opentelemetry-rust/scripts/opentelemetry-rust-bootstrap.sh observable
```

The script prints JSON with a `scenario`, `cargo`, and `snippet` field.

## Review Checklist

- Do libraries depend only on `opentelemetry` while binaries wire SDK/exporters?
- Is `service.name` stable and configured exactly once?
- Are providers retained and shut down gracefully?
- Is stdout used only for local verification?
- Are OTLP endpoints, headers, timeouts, compression, and sampling configurable?
- Are high-cardinality attributes avoided?
- Are metrics instruments reused instead of created per request?
- Are observable instrument handles kept alive until after shutdown?
- Does async/tracing integration preserve context across task and service boundaries?
- Are logs bridged only with compatible crate versions and safe filters?

## Sources

- `https://github.com/open-telemetry/opentelemetry-rust`
- `https://opentelemetry.io/docs/languages/rust/`
- `https://docs.rs/opentelemetry/latest/opentelemetry/`
- `https://docs.rs/opentelemetry_sdk/latest/opentelemetry_sdk/`
- `https://docs.rs/opentelemetry-otlp/latest/opentelemetry_otlp/`
- `https://docs.rs/opentelemetry_sdk/latest/opentelemetry_sdk/trace/`
- `https://docs.rs/opentelemetry_sdk/latest/opentelemetry_sdk/metrics/`
- `https://docs.rs/opentelemetry_sdk/latest/opentelemetry_sdk/logs/`
- `https://docs.rs/opentelemetry-stdout/latest/opentelemetry_stdout/`
- `https://docs.rs/opentelemetry-appender-tracing/latest/opentelemetry_appender_tracing/`
- `https://docs.rs/opentelemetry-semantic-conventions/latest/opentelemetry_semantic_conventions/`
