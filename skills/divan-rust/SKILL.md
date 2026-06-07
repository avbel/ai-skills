---
name: divan-rust
description: Divan Rust benchmarking conventions - Cargo bench setup, bench macro usage, Bencher, black_box, args/types/consts, counters, threads, AllocProfiler, and benchmark results.
---

# Divan Rust Benchmarking

Apply this skill when adding, reviewing, or debugging Rust benchmarks that use the `divan` crate.

Primary sources:
- `https://github.com/nvzqz/divan`
- `https://docs.rs/divan/latest/divan/`
- `https://docs.rs/divan/latest/divan/attr.bench.html`

## Setup

- Add Divan as a dev dependency. Current docs show Divan `0.1.21`, requiring Rust `1.80.0` or later:
  ```toml
  [dev-dependencies]
  divan = "0.1.21"

  [[bench]]
  name = "example"
  harness = false
  ```
- Put benchmark files under `benches/<name>.rs` unless the project already has a separate benchmarking crate.
- Every Divan bench target needs:
  ```rust
  fn main() {
      divan::main();
  }
  ```
- Run benchmarks with:
  ```bash
  cargo bench
  cargo bench --bench example
  ```

## Sample Usage

Use this as the default shape for a new benchmark file:

```rust
// benches/example.rs
use divan::{black_box, Bencher};

fn main() {
    divan::main();
}

fn reverse_bytes(input: &[u8]) -> Vec<u8> {
    let mut output = input.to_vec();
    output.reverse();
    output
}

#[divan::bench(args = [16, 256, 4096])]
fn reverse_allocating(len: usize) -> Vec<u8> {
    let input = vec![42; len];
    reverse_bytes(black_box(&input))
}

#[divan::bench(args = [16, 256, 4096])]
fn reverse_with_reused_input(bencher: Bencher, len: usize) {
    let input = vec![42; len];

    bencher
        .counter(divan::counter::BytesCount::of_slice(&input))
        .bench(|| reverse_bytes(black_box(&input)));
}

#[divan::bench]
fn copy_into_reused_buffer(bencher: Bencher) {
    let src = vec![1_u8; 1024];
    let mut dst = vec![0_u8; src.len()];

    bencher.bench_local(|| {
        black_box(&mut dst).copy_from_slice(black_box(&src));
    });
}
```

## Benchmark Functions

- Mark each benchmark with `#[divan::bench]`.
- Use direct return benchmarks for pure functions that need little setup:
  ```rust
  #[divan::bench]
  fn parse_id() -> u64 {
      divan::black_box("42").parse().unwrap()
  }
  ```
- Use `Bencher` when setup should happen outside the timed loop, when inputs must be reused, or when throughput counters are needed.
- Use `bench()` for closures that can run with Divan's parallel `threads` option. Use `bench_local()` for closures that mutate local state or are strictly single-threaded.
- Use `with_inputs()` when each iteration needs fresh input and generation time must not be included in the measurement.
- Use `bench_values`, `bench_refs`, or the local variants when generated inputs should be passed by value or reference.

## Inputs and Comparisons

- Use `args = [...]` to compare input values:
  ```rust
  #[divan::bench(args = [1, 2, 4, 8, 16, 32])]
  fn fibonacci(n: u64) -> u64 {
      match n {
          0 | 1 => 1,
          n => fibonacci(n - 2) + fibonacci(n - 1),
      }
  }
  ```
- Non-`Copy` args can be accepted by reference.
- Common string argument types can be accepted as `&str`.
- Use `consts = [...]` for const-generic benchmarks.
- Use `types = [...]` for generic benchmarks over several types.
- Combine `types` and `args` when comparing a matrix of type and input-size scenarios.

## Preventing Bad Measurements

- Put input values and outputs through `divan::black_box()` when the optimizer could remove or fold the work.
- Use `divan::black_box_drop` when benchmarking lazy iterators or values whose drop must be included without retaining the result.
- Do not include expensive setup inside the measured closure unless the setup is the thing being benchmarked.
- Do not benchmark debug builds; `cargo bench` uses the bench profile, but custom runners/scripts should preserve optimized builds.
- Keep benchmark functions deterministic. Avoid network, disk, sleeping, random seeds without control, and shared global state unless measuring those effects deliberately.
- Prefer comparing variants in one bench target so environment noise affects all variants similarly.

## Counters and Throughput

- Add counters when runtime alone is not enough. Use counters to report bytes, chars, or items processed per iteration.
- Use the `counters = ...` attribute for static counts, or `bencher.counter(...)` when counts depend on setup or an argument.
- Use `input_counter(...)` when counts depend on generated inputs from `with_inputs()`.
- Prefer bytes counters for parsers, codecs, hashing, compression, and I/O-like algorithms; prefer item counters for collection operations.

## Threads and Contention

- Use `#[divan::bench(threads)]` or explicit thread counts only when measuring thread-safe work or contention on atomics, locks, caches, or shared structures.
- `threads` uses the available parallelism by default; explicit thread lists should match the question being asked.
- Remember that `sample_count` is effectively multiplied across thread counts so each competing thread gets comparable sample work.
- Do not use `bench_local()` for code intended to be exercised with Divan's `threads` option.

## Allocation Profiling

- Use `AllocProfiler` only when allocation counts or bytes are meaningful for the benchmark:
  ```rust
  use divan::AllocProfiler;

  #[global_allocator]
  static ALLOC: AllocProfiler = AllocProfiler::system();
  ```
- Allocation profiling affects timing because allocation information is collected during measured time. Interpret timing and allocation numbers together.
- Allocations in threads not controlled by Divan are not currently counted.
- If the project already uses a custom global allocator such as mimalloc, wrap it with `AllocProfiler::new(allocator)`.

## CLI and Tuning

- Use bench attributes for stable defaults: `sample_count`, `sample_size`, `min_time`, `max_time`, `threads`, and `ignore`.
- Use runtime overrides for ad hoc investigation:
  ```bash
  cargo bench -- --sample-count 1000
  cargo bench -- --sample-size 100
  ```
- Environment variables such as `DIVAN_SAMPLE_COUNT` and `DIVAN_SAMPLE_SIZE` can override attribute defaults.
- Mark expensive or platform-specific benchmarks with `ignore` and document how to run them.

## Reviewing Divan Benchmarks

- Verify `[[bench]] harness = false` exists for each Divan bench target.
- Verify benchmark files call `divan::main()`.
- Check that the benchmark actually measures the intended code path and not setup, allocation, parsing, cloning, or drop behavior by accident.
- Check that optimizer-sensitive inputs and outputs use `black_box`.
- Check that throughput counters match the actual amount of work per iteration.
- Check that `bench()` vs `bench_local()` matches the closure's thread-safety and mutability.
- Prefer small, focused benchmark names and input labels that make Divan's output readable.
