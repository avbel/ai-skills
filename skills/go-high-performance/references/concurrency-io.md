# Concurrency, I/O and services

## Scale the workload before changing primitives

- Measure the serial path. Batch small items and keep scratch and counters local to a worker, then merge results after synchronization. A goroutine handoff, scheduler wake-up, or shared atomic on every element can dominate cheap work.
- Bound work before spawning a goroutine. Try a fixed worker set reading a bounded queue for a long stream. For a finite batch, `errgroup.WithContext` and `SetLimit` can be a good fit. `Group.Go` can block while admitting work and its admission does not check the context. Use cancellation-aware queue or semaphore acquisition when the submission path must wake on cancellation. Avoid nested submissions to the same saturated group. [`errgroup` admission and cancellation](https://pkg.go.dev/golang.org/x/sync/errgroup).
- Choose CPU-bound parallelism around `runtime.GOMAXPROCS(0)` and benchmark smaller and larger settings where useful. Choose I/O parallelism against downstream connection limits, response times and memory per in-flight operation. Measure queue wait, latency, failures and throughput under load. Decide how the existing API handles overload, including backpressure or a bounded wait.
- Have a path for workers to exit on cancellation, including a sender whose consumer stops reading. Pass context to I/O and join workers before releasing shared resources. Close a jobs channel from the producer side or have a coordinator close it once all producers finish. Adding buffer space can delay a stall without fixing its cause. [Go pipelines and cancellation](https://go.dev/blog/pipelines).
- Go 1.25 introduced container-aware `GOMAXPROCS` defaults on Linux. Check the effective behavior for the main module's Go version and `GODEBUG` settings. Manual `GOMAXPROCS` overrides disable automatic updates. The runtime uses cgroup CPU limits in that calculation. In cgroup v2, read `cpu.max` for quota and period and compare the change in `cpu.stat` fields `nr_throttled` and `throttled_usec` over the same load window as tail latency. [Container-aware `GOMAXPROCS`](https://go.dev/blog/container-aware-gomaxprocs), [Linux cgroup v2 CPU controls](https://docs.kernel.org/admin-guide/cgroup-v2.html#cpu-interface-files).

## Reduce synchronization costs

- Keep the lock around the complete invariant. Move independent computation and I/O out of the critical section. For a hot map, start with a typed map plus a short `Mutex`. Compare `RWMutex` when reads can overlap enough to matter. Compare `sync.Map` for write-once/read-many keys or workloads operating on disjoint keys. Use typed sharding when the measured workload supports it and preserve cross-key invariants. [`sync`](https://pkg.go.dev/sync).
- Use typed atomics for independent scalar operations, or `atomic.Pointer[T]`/`atomic.Value` to publish a fully initialized immutable snapshot. Writers that derive a snapshot from the previous one still need coordination to avoid lost updates. Include nested maps/slices in the immutability contract. Go's atomic operations are sequentially consistent. [Go memory model](https://go.dev/ref/mem), [`sync/atomic`](https://pkg.go.dev/sync/atomic).
- High contention on a shared counter can remain after switching to atomics. Aggregate locally and publish at a frequency consistent with the required visibility. If throughput drops even though workers write distinct counters, investigate false sharing. Measure layout and padding on the target CPU before adding portable code that depends on a cache-line size.
- If repeated timer creation is hot, reuse a channel-based `time.Timer` under one owner when timeout behavior permits. Go 1.23 introduced synchronous timer channels and collection of unreachable unstopped timers. Through Go 1.26, check the main module version and `asynctimerchan` setting before using the new reset/stop guarantees. Go 1.27 removed that setting and always uses synchronous timer channels. Keep the older stop/drain protocol when supporting older semantics. `AfterFunc` has a separate callback lifecycle. [Go timer changes](https://go.dev/wiki/Go123Timer), [Go 1.27 runtime notes](https://go.dev/doc/go1.27#runtime).

## Buffer small I/O and reuse connections

- Use `bufio.Reader` or `bufio.Writer` for many small reads/writes. Check `Flush` errors and respect streaming flush points. `Scanner.Bytes` shares storage and can be overwritten by the next scan. Copy when tokens must outlive that point. Set the scanner's token cap with `Scanner.Buffer` before scanning when the input needs a different limit, and check `Scanner.Err`. [`bufio`](https://pkg.go.dev/bufio).
- Use `io.Copy` to stream. It calls `src.WriteTo` or `dst.ReadFrom` when available. `io.CopyBuffer` allows scratch reuse when neither fast path applies. Wrapper types can hide these interfaces and change the transfer path. Keep body size limits and deadlines when switching from whole-buffer processing to streaming. [`io.Copy` and `CopyBuffer`](https://pkg.go.dev/io#CopyBuffer).
- Reuse a configured `http.Client` and its `Transport`. Close every successful response body promptly. Reading the body through EOF enables HTTP/1.x connection reuse. Follow request deadlines and avoid an unbounded drain of an unwanted body. Current transports can attempt a bounded drain for HTTP/1.x when closing. Check reuse with `net/http/httptrace` before tuning the pool. Use separate limits for idle connections and total per-host connections according to the measured bottleneck. [`net/http.Client`](https://pkg.go.dev/net/http#Client), [HTTP tracing](https://pkg.go.dev/net/http/httptrace).
- Reuse the shared `*sql.DB` handle and close `Rows` promptly when finishing early. Tune idle connections, open connections and connection lifetime against database capacity and app concurrency. Inspect `DB.Stats` wait counts and duration before interpreting pool saturation as slow queries. Eliminate N+1 queries and unnecessary round trips where batching preserves semantics. [Database connection management](https://go.dev/doc/database/manage-connections).

```go
package records

import (
	"bufio"
	"io"
	"strconv"
)

func writeIDs(dst io.Writer, ids []uint64) error {
	out := bufio.NewWriter(dst)
	var scratch [21]byte // 20 digits and one newline.
	for _, id := range ids {
		line := strconv.AppendUint(scratch[:0], id, 10)
		line = append(line, '\n')
		if _, err := out.Write(line); err != nil {
			return err
		}
	}
	return out.Flush()
}
```

## Serialization, logging and caching

- Decode JSON into typed structs for known schemas. Stream a sequence of records when the protocol allows and measure peak memory for the largest supported payload. In Go 1.27, `encoding/json` uses the new engine with v1 semantics, so test a toolchain update on the existing API first. The public `encoding/json/v2` package has different defaults. Test duplicate names, invalid UTF-8, case matching, empty versus null fields, output order when relevant, and custom marshalers before switching. [Go 1.27 JSON release notes](https://go.dev/doc/go1.27#standard-library), [`encoding/json/v2`](https://pkg.go.dev/encoding/json/v2).
- On a measured logging hot path, use `slog.Logger.LogAttrs` for typed attributes. Check `Enabled` before computing expensive fields. For a slow sink, measure time in formatting and the writer before buffering. Any asynchronous writer needs bounded memory and an explicit full-queue policy consistent with the log delivery contract. [`log/slog`](https://pkg.go.dev/log/slog).
- If repeated loads for the same key dominate, `singleflight.Group` can coalesce in-flight calls. Use a key that preserves caller and data isolation, and define cancellation and error behavior for shared work. Add a bounded cache only when reuse justifies eviction and staleness costs. Measure hit rate, backend requests, memory and p99 together. [`singleflight`](https://pkg.go.dev/golang.org/x/sync/singleflight).
