# Benchmarking and profiling

## Build a benchmark around the decision

- Keep the benchmark name and work per operation identical for an A/B comparison. Include representative sizes, data distributions, and hit/miss ratios. If an operation mutates input, restore equivalent input for every iteration and decide whether that preparation belongs in the measured operation.
- Match buffer lifetimes to production. Benchmark a reused destination only when callers reuse it. Add a separate benchmark for callers with an empty destination if that path matters.
- For Go 1.24+, use the exact `for b.Loop() { ... }` form. It times the loop and keeps work in the body from being optimized away. Go 1.24 and 1.25 can suppress inlining of calls inside that loop, which can change allocation counts. Go 1.26 removed that restriction. On older toolchains use `for i := 0; i < b.N; i++`, call `b.ResetTimer()` after setup, and make the result observable. Avoid a global write on every iteration unless it represents the real workload. [Go benchmarking guide](https://go.dev/blog/testing-b-loop), [Go 1.26 release notes](https://go.dev/doc/go1.26).
- Use `b.RunParallel` with `for pb.Next()`, keep scratch state local to each worker, and keep shared state where production shares it. Compare representative `-cpu` settings. Its `ns/op` describes aggregate wall time per operation and does not report the latency distribution of individual operations.
- Use `b.SetBytes(n)` for operations that process a known number of bytes per iteration, `b.ReportAllocs()` or `-benchmem` for allocation costs, and `b.ReportMetric` for additional metrics such as records per operation. `-benchmem` counts Go allocations. Measure native memory separately when cgo is involved. [Go `testing` package](https://pkg.go.dev/testing), [Go test flags](https://pkg.go.dev/cmd/go#hdr-Description_of_testing_flags).

This benchmark models an ID written repeatedly into caller-owned scratch. The baseline appends the result of `strconv.FormatUint(id, 10)`. The candidate appends the digits directly into the same destination.

```go
package records

import (
	"strconv"
	"testing"
)

func BenchmarkAppendID(b *testing.B) {
	ids := []uint64{934, 1_234_567, 8_765_432_109, ^uint64(0)}
	dst := make([]byte, 0, 20) // A uint64 in base ten needs at most 20 bytes.
	b.ReportAllocs()
	for b.Loop() {
		for _, id := range ids {
			out := strconv.AppendUint(dst[:0], id, 10)
			if len(out) == 0 {
				b.Fatal("missing ID")
			}
		}
	}
	b.ReportMetric(float64(len(ids)), "IDs/op")
}
```

An operation here formats all four IDs. Keep exact-output checks in ordinary tests. Start with 10 samples per build and interleave runs when the effect is small. Use a consistent CPU budget, toolchain, PGO setting, and input setup. Interpret median, spread and significance together. A noisy result warrants better control of the workload or environment.

On an Apple M2 Max with Go 1.27.4, `GOMAXPROCS=12`, PGO off and 10 samples per variant at `-benchtime=100ms`, the baseline median was 74 ns/op with 56 B/op and 4 allocs/op. The append variant had a median of 35 ns/op with 0 B/op and 0 allocs/op.

## Benchmark tooling

Use the project's `benchstat` if available. To install it for local use, run `go install golang.org/x/perf/cmd/benchstat@latest` and put the install directory on `PATH` (`go env GOBIN`, or `$(go env GOPATH)/bin` for a default single-entry `GOPATH`). Pin the tool version for recurring comparisons in CI. [benchstat documentation](https://pkg.go.dev/golang.org/x/perf/cmd/benchstat).

## Capture one diagnostic at a time

Run from the package being benchmarked. Keep the profile's binary and source revision for symbolization. Use a scratch output directory for profiles and test binaries if they should stay out of the checkout. [Go diagnostics guide](https://go.dev/doc/diagnostics).

```bash
go test -run='^$' -bench='^BenchmarkAppendID$' -benchtime=3s -cpuprofile=cpu.pprof
go tool pprof -top cpu.pprof
go tool pprof -top -cum cpu.pprof
go tool pprof -list=BenchmarkAppendID cpu.pprof

go test -run='^$' -bench='^BenchmarkAppendID$' -memprofile=mem.pprof
go tool pprof -top -sample_index=alloc_space mem.pprof
go tool pprof -top -sample_index=inuse_space mem.pprof
```

For a package with a parallel workload benchmark named `BenchmarkConcurrent`, use separate captures for synchronization or scheduling. Replace the example benchmark name with the real one.

```bash
go test -run='^$' -bench='^BenchmarkConcurrent$' -mutexprofile=mutex.pprof -mutexprofilefraction=10
go tool pprof -top mutex.pprof

go test -run='^$' -bench='^BenchmarkConcurrent$' -blockprofile=block.pprof -blockprofilerate=1000000
go tool pprof -top block.pprof

go test -run='^$' -bench='^BenchmarkConcurrent$' -benchtime=200ms -trace=trace.out
go tool trace -http=127.0.0.1:6061 trace.out
```

- CPU samples show executing code. Compare flat time with cumulative cost and inspect callers before rewriting a leaf function.
- Allocation samples attribute bytes or objects to allocation sites. Account for setup and runtime allocations. Live heap profiles identify where still-live objects were created. Inspect their owners to find why they stay live.
- Block and mutex delays are cumulative across goroutines. The block stack shows where a goroutine waited. The mutex stack usually ends at the unlock that caused other goroutines to wait. In a running service, enable sampling explicitly with `runtime.SetBlockProfileRate` or `runtime.SetMutexProfileFraction` for a targeted window. Higher sample rates add overhead. [`runtime/pprof` profile semantics](https://pkg.go.dev/runtime/pprof).
- Use `go tool trace` for scheduler latency, syscalls and GC events. Use `runtime/trace.FlightRecorder` (Go 1.25+) for rare latency spikes that need a recent trace window. A goroutine dump helps diagnose persistent wait stacks. `goroutineleak` (Go 1.27+) detects some permanently blocked goroutines via reachability. Check trends and stacks as well. [Go 1.25 runtime notes](https://go.dev/doc/go1.25#runtime), [Go 1.27 runtime notes](https://go.dev/doc/go1.27#runtime).
- For service profiling, use an existing private diagnostics listener or `runtime/pprof`. `net/http/pprof` registers on `http.DefaultServeMux` at import time. Use a separate mux for public traffic and keep profile artifacts within the service's diagnostics access boundary. [`net/http/pprof`](https://pkg.go.dev/net/http/pprof).

On a private listener, capture each profile during a comparable load window. Use a delta allocation profile to focus on that window and a heap snapshot to examine retained objects.

```bash
curl -fsS 'http://127.0.0.1:6060/debug/pprof/profile?seconds=30' -o service-cpu.pprof
curl -fsS 'http://127.0.0.1:6060/debug/pprof/allocs?seconds=30' -o service-allocs.pprof
go tool pprof -top -sample_index=alloc_space service-allocs.pprof
curl -fsS 'http://127.0.0.1:6060/debug/pprof/heap' -o service-heap.pprof
go tool pprof -top -sample_index=inuse_space service-heap.pprof
curl -fsS 'http://127.0.0.1:6060/debug/pprof/goroutine?debug=2' -o goroutines.txt
```

Compare separate goroutine snapshots before, during and after load to identify wait stacks that persist after the workload drains.

## Prevent a known regression

Keep the benchmark close to the code. Compare repeat runs on a stable runner for timing regressions. For a deliberately allocation-free path, assert a realistic upper bound with `testing.AllocsPerRun` in an isolated serial test. It warms up the function and temporarily sets `GOMAXPROCS` to 1. Choose the bound for the supported toolchains and workloads. Verify concurrency changes separately with `go test -race` and exercise the paths that share state.
