---
name: go-high-performance
description: Write and audit high-performance Go with measurement-first guidance on benchmarking, profiling, allocations, GC, concurrency, PGO, and code generation. Use to make Go code faster, optimize a hot loop, reduce allocations, tune latency or throughput, or review Go performance.
---

# High-Performance Go

Optimize the workload that matters. Apply these rules to hot paths and use the project's supported Go version and deployment constraints. Retest compiler and runtime assumptions after changing either.

## How it works

1. Define the target metric and workload. For services, record throughput, p95/p99 latency, errors, CPU and peak memory at a representative load. For a kernel, measure time and allocations per operation across realistic input sizes.
2. Find the largest cost with the relevant profile. Remove unnecessary work, round trips and algorithmic costs first. Follow the audit table where the evidence points.
3. Change one variable at a time. Run the same benchmark on both implementations and compare repeated samples with `benchstat`. Keep the toolchain, target CPU, build flags, runtime settings and inputs comparable.
4. Verify correctness and measure the full workload again. Retest output, errors, cancellation, input limits, and behavior under load wherever the change touches them. Run race detection separately for concurrent changes.

## Measure first

| Signal | Start with |
|---|---|
| High CPU or cost per request | CPU `pprof`, inspect both flat and cumulative cost |
| High allocation rate or GC CPU | `alloc_space` for byte churn, `alloc_objects` for object churn |
| High live memory or rising RSS | `inuse_space` for retained Go heap, plus process/container memory to account for other sources |
| Slow requests with idle CPU or poor scaling | Block profile for the wait site, mutex profile for the holder, execution trace for scheduling and I/O waits |
| Rising goroutine count | Compare goroutine stacks over time and use the Go 1.27+ `goroutineleak` profile where applicable |

```bash
go test -run='^$' -bench='^BenchmarkAppendID$' -benchmem -count=10 ./internal/records > before.txt
# Repeat after the change with the same benchmark name and flags.
go test -run='^$' -bench='^BenchmarkAppendID$' -benchmem -count=10 ./internal/records > after.txt
benchstat before.txt after.txt
```

Use the project's package and benchmark in these commands. For small deltas, run before and after in alternating order on the same machine. Use `testing.B.Loop` starting with Go 1.24 and `B.RunParallel` with `PB.Next` for shared-state throughput. Profile separately from timing. See [measurement and profiling](references/measurement.md) for a benchmark example, working profile commands and how to read the results.

## Audit checklist

### Allocation, retention and layout

| You see | Do |
|---|---|
| Hot slice or map grows repeatedly and cardinality is predictable | Pre-size with `make([]T, 0, n)` for append, `make([]T, n)` for indexed filling, or `make(map[K]V, n)` for a map. Use a bounded estimate and check live memory. |
| Repeated scratch allocations or `fmt.Sprintf` followed by append | Reuse caller-owned scratch. Consider `strconv.Append*`, `Time.AppendFormat` or `fmt.Appendf` when formatting is hot, and `strings.Builder` when the result is a string. |
| Small long-lived slice or substring retains megabytes | Copy at the retention boundary with `bytes.Clone` or `strings.Clone`. Limiting slice capacity still shares its backing array. |
| Resliced pointer-bearing buffer retains removed entries | Clear discarded slots while they remain addressable. `slices.Delete` and `DeleteFunc` clear the obsolete tail starting with Go 1.22. |
| Heap allocation attributed to a closure, `any`, a pointer or a slice | Use `-gcflags=-m=2` to find the escape and `-benchmem` to confirm cost. Evaluate the call site before changing receiver or API types. |
| Many temporary allocations remain across independent requests | Try `sync.Pool` after simpler reuse. Reset items, cap retained sizes and release only after the last use of every alias. |
| Millions of pointers, or a scan loads a few fields from wide structs | Compare contiguous values, bounded integer indices, or a hot/cold split. Measure copied bytes, heap scan size and access locality. |

See [allocation, layout and GC](references/memory.md) for ownership, escape analysis, data layout, and `GOGC`/`GOMEMLIMIT` tuning.

### Hot paths, compiler and builds

| You see | Do |
|---|---|
| Handwritten search, equality, bit count or integer encoding | Start with `bytes`, `strings`, `math/bits`, `encoding/binary` or `strconv`. Preserve byte, rune, overflow and ordering semantics. |
| Temporary `[]byte`-to-string conversions appear in hot map lookups | Use `m[string(keyBytes)]` directly for lookup so the compiler can elide the copy. Stored keys need their own stable contents. |
| Copy of a large struct in a `range` loop | Use an index and access the required fields in place. When taking an address, distinguish the slice element from the loop variable. |
| Repeated middle deletes or sort recomputes an expensive key | Compact in one pass, or compute sort keys once. Preserve order and stability where callers rely on them. |
| CPU-hot bounds checks or indirect calls | Make slice lengths evident with a correct outer guard. Inspect remaining checks and inlining. Try PGO before redesigning an interface purely for dispatch cost. |
| Numerical kernel still dominates CPU | Improve layout and locality, then check emitted instructions on the target CPU. Evaluate tuned libraries or explicit SIMD only when the gain covers dispatch and maintenance. |

See [compiler, PGO and CPU targets](references/toolchain.md) for verified commands, feature versions, and portability.

### Concurrency and I/O

| You see | Do |
|---|---|
| A goroutine per cheap item or an ever-growing queue | Batch small items. Bound admission before spawning work, and size workers and queues against CPU budget, downstream limits and latency. |
| Hot shared lock, map or counter | Keep work local and merge, then shorten critical sections. Consider sharding or immutable snapshots when contention remains. Measure `Mutex`, `RWMutex` or `sync.Map` under actual read/write skew. |
| Container throttling or excessive runnable goroutines | Compare effective `runtime.GOMAXPROCS(0)`, CPU quota, throttling and scheduler delay. Check whether an override disables container-aware defaults. |
| Small syscalls, per-call connections, or whole-body reads | Buffer small I/O, reuse HTTP and database connections, and stream large bodies within the existing size and deadline limits. |
| JSON or logging dominates CPU | Decode into concrete types for known schemas, guard expensive log fields with `Enabled`, and check wire compatibility when changing JSON APIs. |

See [concurrency, I/O and services](references/concurrency-io.md) for cancellation, timers, connection reuse, logging and serialization details.

## Usage

For two existing checkouts, the helper compiles the same package in each checkout and runs each pair in alternating order. It uses Go, `jq`, and GNU coreutils `timeout` (`gtimeout` on macOS) and executes the test binaries on the current host. To measure container quota effects, run inside the target container configuration. Pass the baseline and candidate module directories, one package path, a benchmark regexp and an existing output parent directory. For a local installation, resolve `scripts/compare-benchmarks.sh` relative to this skill's directory.

The optional arguments set samples per build (`10`), Go benchmark time per benchmark (`1s`), and the wall-clock timeout for each test binary invocation (`10m`). The timeout accepts positive whole seconds or a whole value with an `s`, `m`, `h`, or `d` suffix. Increase it if one invocation runs several benchmarks or performs lengthy setup.

```bash
bash /mnt/skills/user/go-high-performance/scripts/compare-benchmarks.sh \
  /tmp/go-before /tmp/go-after ./internal/records '^BenchmarkAppendID$' /tmp

bash /mnt/skills/user/go-high-performance/scripts/compare-benchmarks.sh \
  /tmp/go-before /tmp/go-after ./internal/records '^BenchmarkAppendID$' /tmp 20 500ms 2m
```

The helper writes plain benchmark files and prints their locations as JSON. Pass the two paths to `benchstat` in before/after order. See [benchmark tooling setup](references/measurement.md#benchmark-tooling) if `benchstat` is unavailable.

```json
{
  "before": "/tmp/go-bench.ABC123/before.txt",
  "after": "/tmp/go-bench.ABC123/after.txt",
  "go_version": "go1.27.4",
  "samples_per_variant": 10,
  "benchtime": "1s",
  "sample_timeout": "10m"
}
```

If either package or benchmark is missing, verify the package path and match the benchmark name in both checkouts. If the toolchain versions differ, select a common supported toolchain for a code-only comparison. For an intentional toolchain comparison, collect the two samples directly and record both versions.

## Report results

Report the bottleneck, the exact workload and environment, before/after metrics with sample counts, and any correctness or resource trade-offs. Describe an inconclusive delta as inconclusive. Add a benchmark or allocation budget only when the project intends to maintain that performance contract.

## Installation

For Claude Code, copy the directory from the repository root with `cp -r skills/go-high-performance ~/.claude/skills/`. For claude.ai, add `SKILL.md` to project knowledge or paste its contents into the conversation, and provide the supporting reference files when needed.
