# Compiler, PGO and CPU targets

## Inspect the code the compiler produced

The standard Go compiler optimizes regular builds. Match the deployed architecture, build tags, and PGO settings. Debug builds with `-N -l`, race instrumentation, and coverage change the code being measured.

```bash
go build -gcflags=-m=2 ./internal/records
go build -gcflags=-d=ssa/check_bce/debug ./internal/records
go build -gcflags=-S ./internal/records 2> assembly.txt
go test -c -o records.test ./internal/records
go tool objdump -s 'BenchmarkAppendID' records.test
```

- Read escape and inlining diagnostics at the relevant call site. Inlining can expose constants, concrete types and ownership information to other optimization passes. Compare an interface call with a concrete implementation only when dispatch is a measured cost, and keep the interface at boundaries that need it. Measure the call and allocation costs of a generic specialization as well. [Go compiler diagnostics](https://go.dev/src/cmd/compile/README).
- A `Found IsInBounds` or `Found IsSliceInBounds` diagnostic identifies a check that remains at that point in compilation. Make the input invariant evident with a correct guard and a direct loop or validated subslice. Keep error behavior and check the caller's assembly when the function inlines. An absent standalone symbol can be an effect of inlining or dead-code elimination.

```go
package records

func sumProducts(left, right []uint64) (uint64, bool) {
	if len(left) != len(right) {
		return 0, false
	}
	var sum uint64
	for i, value := range left {
		sum += value * right[i]
	}
	return sum, true
}
```

This example rejects unequal lengths and uses unsigned modular arithmetic. Verify bounds-check elimination on the supported toolchains. Use an index loop and `&rows[i]` when large element copies matter or code needs the actual element's address. The range value is a copy. [Go spec](https://go.dev/ref/spec).

- Prefer `bytes.IndexByte`, `strings.IndexByte`, `bytes.Equal`, `copy`, `math/bits`, or a matching standard primitive before writing a kernel. When reading bytes from a string, indexing visits bytes and `range` visits decoded runes. Benchmark the version that preserves the required semantics.
- Do a direct `m[string(keyBytes)]` lookup in a string-keyed map when the compiler can use the byte slice transiently. Copying may still be necessary for a stored key. For tiny collections or dense integer IDs, compare a linear scan or slice index to hashing. Use the built-in map as the baseline and preserve collision handling if changing the data structure. [Compiler map lookup optimization](https://go.dev/src/cmd/compile/internal/walk/order.go).
- Prefer `slices.Sort` for ordered types and `slices.SortFunc` for a custom order on Go 1.21+. Use `slices.SortStableFunc` when tie order matters. Precompute sort keys if a hot comparator repeats expensive work. Compare the temporary storage and copy cost as well. [`slices`](https://pkg.go.dev/slices).

## Compare profile-guided builds

PGO takes a CPU `pprof` profile from the program's normal workload. Choose a realistic traffic mix or a full-program benchmark for a CLI. Keep the emitted binary and revision with the profile. Compare binaries built from the same source with the same configuration under a representative workload.

```bash
go build -pgo=off -o service-base ./cmd/service
go build -pgo=/path/to/profile.pprof -o service-pgo ./cmd/service
```

Go 1.21+ defaults to `-pgo=auto`, which looks for `default.pgo` beside each main package's sources. An explicit profile path applies to every main package in that invocation. Associate the right profile with each binary. Refresh profiles when the workload mix or hot call paths change. Measure CPU per unit of work and tail latency alongside binary size and cold build cost. [Go PGO guide](https://go.dev/doc/pgo).

## CPU targets, SIMD and cgo

- `GOAMD64` and `GOARM64` set a minimum CPU target for the binary. For example, `GOAMD64=v3` requires a compatible x86-64 deployment fleet. Use the deployment baseline for shared artifacts and benchmark any higher target. Keep baseline coverage or a portable fallback for mixed fleets. [Go minimum CPU targets](https://go.dev/wiki/MinimumRequirements#microarchitecture-support).
- For numerical kernels, consider contiguous data and less work per element first. Check the emitted instructions on the target CPU to see whether a scalar loop was vectorized. [Go assembler and disassembly](https://go.dev/doc/asm).
- Consider a tested library or SIMD only for a measured compute bottleneck. Go 1.26 introduced experimental `simd/archsimd` for amd64. Go 1.27 adds experimental portable `simd` and extends `archsimd` to arm64 and wasm with an updated API. Both use `GOEXPERIMENT=simd` in Go 1.27. Keep experimental code isolated with a scalar baseline, test tails and alignment, and check exact floating-point requirements and ordering before changing reductions. For handwritten architecture-specific code, use build constraints and check optional CPU features once outside the hot loop. [Go 1.26 SIMD experiment](https://go.dev/doc/go1.26), [Go 1.27 SIMD packages](https://go.dev/doc/go1.27).
- Measure cgo against the pure Go path end to end, including data conversion, copies and native memory. Batch enough work to amortize the call boundary. Follow the cgo rules for pointer lifetime and memory ownership. A fast native function can still lose on small inputs. [cgo documentation](https://pkg.go.dev/cmd/cgo).

## Size, startup and build time

- Compare artifacts for the same target and build mode. `-ldflags=-s` removes the symbol table and debug information. Keep the matching profiling or debugging artifacts for shipped binaries. Measure size separately from runtime speed. [Go linker flags](https://pkg.go.dev/cmd/link).
- To investigate cold startup, time the real invocation and use `GODEBUG=inittrace=1` to identify costly package initialization. Moving work from startup to the first request shifts its latency cost to the caller, so measure both. [Go diagnostics](https://go.dev/doc/diagnostics#godebug).
- Compare cold and warm build times explicitly. Preserve the reusable Go build and module caches in CI. Use `go build -x` to inspect unexpected rebuilds and `go version -m` to record a binary's build settings. A first PGO build may rebuild dependencies with the new profile before subsequent builds can reuse those results. [Go command documentation](https://pkg.go.dev/cmd/go), [PGO build time](https://go.dev/doc/pgo).

## Performance-related changes by Go version

| Go | Change to consider |
|---|---|
| [1.18](https://go.dev/doc/go1.18) | `GOAMD64` for a minimum x86-64 target |
| [1.19](https://go.dev/doc/go1.19) | `GOMEMLIMIT` and typed atomics |
| [1.20](https://go.dev/doc/go1.20) | Profile-guided builds with `-pgo` |
| [1.21](https://go.dev/doc/go1.21) | PGO defaults to auto, `slices` package and `clear` builtin |
| [1.22](https://go.dev/doc/go1.22) | Several `slices` helpers clear obsolete elements |
| [1.23](https://go.dev/doc/go1.23) | `GOARM64`, `unique`, and new channel timer semantics with version-dependent opt-in |
| [1.24](https://go.dev/doc/go1.24) | Swiss Table maps and `testing.B.Loop` |
| [1.25](https://go.dev/doc/go1.25) | Container-aware `GOMAXPROCS`, trace flight recorder, and more small slice makes eligible for stack allocation |
| [1.26](https://go.dev/doc/go1.26) | Green Tea GC by default, expanded stack-backed slices at `append` sites, cheaper cgo calls, and experimental amd64 `simd/archsimd` |
| [1.27](https://go.dev/doc/go1.27) | Size-specialized small allocations, `goroutineleak` profile, new JSON implementation and API, experimental `simd` and expanded `simd/archsimd` |
