#!/bin/bash
set -e

scenario="${1:-stdout-trace}"

case "$scenario" in
  stdout-trace)
    cargo='opentelemetry = { version = "0.31", features = ["trace"] }
opentelemetry_sdk = { version = "0.31", features = ["trace"] }
opentelemetry-stdout = { version = "0.31", features = ["trace"] }'
    snippet='use opentelemetry::trace::{Tracer, TracerProvider};
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
}'
    ;;
  otlp-http)
    cargo='opentelemetry = { version = "0.32", features = ["trace"] }
opentelemetry_sdk = { version = "0.32", features = ["trace"] }
opentelemetry-otlp = { version = "0.32", features = ["trace", "http-proto", "reqwest-blocking-client"] }'
    snippet='use std::time::Duration;
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
}'
    ;;
  metrics)
    cargo='opentelemetry = { version = "0.31", features = ["metrics"] }
opentelemetry_sdk = { version = "0.31", features = ["metrics"] }
opentelemetry-stdout = { version = "0.31", features = ["metrics"] }'
    snippet='use opentelemetry::{global, KeyValue};
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
}'
    ;;
  manual-span)
    cargo='opentelemetry = { version = "0.32", features = ["trace"] }'
    snippet='use opentelemetry::{global, trace::{Span, Tracer}, KeyValue};

fn charge_order(order_id: &str) {
    let tracer = global::tracer("orders");
    let mut span = tracer.start("charge_order");
    span.set_attribute(KeyValue::new("order.id", order_id.to_owned()));

    // Work here.

    span.end();
}'
    ;;
  observable)
    cargo='opentelemetry = { version = "0.32", features = ["metrics"] }'
    snippet='use std::{any::Any, sync::Arc};
use opentelemetry::metrics::Meter;

struct AppState;

impl AppState {
    fn queue_depth(&self) -> u64 {
        0
    }
}

#[must_use]
fn register_observable_metrics(meter: &Meter, state: Arc<AppState>) -> Vec<Box<dyn Any>> {
    let mut handles: Vec<Box<dyn Any>> = Vec::new();

    handles.push(Box::new(
        meter
            .u64_observable_gauge("queue.depth")
            .with_description("Current queue depth")
            .with_callback(move |observer| {
                observer.observe(state.queue_depth(), &[]);
            })
            .build(),
    ));

    handles
}

// In main: bind to `_observable_handles`, not bare `_`, and drop after provider shutdown.'
    ;;
  *)
    echo "Usage: $0 [stdout-trace|otlp-http|metrics|manual-span|observable]" >&2
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
