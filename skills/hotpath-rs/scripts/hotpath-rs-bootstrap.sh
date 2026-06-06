#!/bin/bash
set -e

scenario="${1:-basic}"

case "$scenario" in
  basic)
    cargo='hotpath = "0.16.1"

[features]
hotpath = ["hotpath/hotpath"]
hotpath-alloc = ["hotpath/hotpath-alloc"]'
    command="cargo run --features='hotpath,hotpath-alloc'"
    snippet='use std::time::Duration;

#[hotpath::measure]
fn compute(input: u64) -> u64 {
    std::thread::sleep(Duration::from_millis(input % 3));
    input * 2
}

#[hotpath::main(percentiles = [50, 95, 99])]
fn main() {
    for input in 0..100 {
        let value = compute(input);
        hotpath::measure_block!("format_output", {
            std::hint::black_box(format!("value={value}"));
        });
    }
}'
    ;;
  tokio)
    cargo='tokio = { version = "1", features = ["macros", "rt-multi-thread", "sync", "time"] }
hotpath = "0.16.1"

[features]
hotpath-tokio = ["hotpath/hotpath", "hotpath/tokio"]'
    command="cargo run --features='hotpath-tokio'"
    snippet='use tokio::{sync::mpsc, time::{sleep, Duration}};

#[hotpath::measure]
async fn handle_job(job: u64) {
    sleep(Duration::from_millis(job % 10)).await;
}

#[tokio::main]
#[hotpath::main(report = "functions-timing,channels,tokio_runtime,threads")]
async fn main() {
    hotpath::tokio_runtime!();

    let (tx, mut rx) = hotpath::channel!(
        mpsc::channel::<u64>(128),
        label = "jobs",
        log = true
    );

    tokio::spawn(async move {
        for job in 0..1_000 {
            tx.send(job).await.expect("jobs receiver alive");
        }
    });

    while let Some(job) = rx.recv().await {
        hotpath::future!(handle_job(job), label = "job_future").await;
    }
}'
    ;;
  data-flow)
    cargo='tokio = { version = "1", features = ["macros", "rt-multi-thread", "time"] }
futures = "0.3"
hotpath = "0.16.1"

[features]
hotpath-data-flow = ["hotpath/hotpath", "hotpath/tokio", "hotpath/futures"]'
    command="cargo run --features='hotpath-data-flow'"
    snippet='use futures::{stream, StreamExt};

#[hotpath::future_fn(log = true)]
async fn fetch_page(page: u64) -> Vec<u8> {
    tokio::time::sleep(std::time::Duration::from_millis(page % 5)).await;
    vec![page as u8; 16]
}

#[tokio::main]
#[hotpath::main(report = "streams,futures")]
async fn main() {
    let pages = hotpath::stream!(stream::iter(1..=100), label = "pages", log = true);

    let total: usize = pages
        .then(|page| hotpath::future!(fetch_page(page), label = "fetch_page"))
        .map(|bytes| bytes.len())
        .sum()
        .await;

    std::hint::black_box(total);
}'
    ;;
  mcp)
    cargo='tokio = { version = "1", features = ["macros", "rt-multi-thread", "sync", "time"] }
hotpath = "0.16.1"

[features]
hotpath-tokio = ["hotpath/hotpath", "hotpath/tokio"]
hotpath-alloc = ["hotpath/hotpath-alloc"]
hotpath-mcp = ["hotpath/hotpath-mcp"]'
    command="HOTPATH_OUTPUT_FORMAT=none HOTPATH_MCP_PORT=6771 cargo run --features='hotpath-tokio,hotpath-alloc,hotpath-mcp'"
    snippet='#[hotpath::measure]
async fn request_path(id: u64) -> String {
    tokio::time::sleep(std::time::Duration::from_millis(id % 20)).await;
    format!("request-{id}")
}

#[tokio::main]
#[hotpath::main(report = "functions-timing,functions-alloc,tokio_runtime")]
async fn main() {
    hotpath::tokio_runtime!();

    loop {
        for id in 0..100 {
            std::hint::black_box(request_path(id).await);
        }
    }
}

// Connect an AI agent:
// claude mcp add --transport http hotpath http://localhost:6771/mcp'
    ;;
  cpu)
    cargo='hotpath = "0.16.1"

[features]
hotpath = ["hotpath/hotpath"]
hotpath-alloc = ["hotpath/hotpath-alloc"]
hotpath-cpu = ["hotpath/hotpath-cpu"]

[profile.profiling]
inherits = "release"
debug = true'
    command="cargo run --features='hotpath,hotpath-alloc,hotpath-cpu' --profile profiling"
    snippet='struct Worker;

#[hotpath::measure_all]
impl Worker {
    fn run(&self, input: u64) -> u64 {
        let mut acc = 0;
        for i in 0..input {
            acc += i ^ input;
        }
        acc
    }
}

#[hotpath::main]
fn main() {
    let worker = Worker;
    for input in 0..10_000 {
        std::hint::black_box(worker.run(input));
    }
}'
    ;;
  *)
    echo "Usage: $0 [basic|tokio|data-flow|mcp|cpu]" >&2
    exit 2
    ;;
esac

SCENARIO="$scenario" CARGO="$cargo" COMMAND="$command" SNIPPET="$snippet" python3 <<'PY'
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "cargo": os.environ["CARGO"],
    "command": os.environ["COMMAND"],
    "snippet": os.environ["SNIPPET"],
}, indent=2))
PY
