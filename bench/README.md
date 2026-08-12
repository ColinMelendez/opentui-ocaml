# Performance profile

`profile.exe` is a repeatable benchmark for the public renderer, retained-tree,
terminal, and Eio boundaries. It reports monotonic elapsed nanoseconds and
OCaml GC words for:

- retained text updates and caller-owned resolved-character output;
- retained dimension/layout updates, child reordering, and create/destroy
  lifecycle churn;
- varied pointer hit-testing and bubbling across a warmed retained tree;
- full 80x24 native frame updates and resolved-character output;
- Eio input reads through the terminal coordinator; and
- repeated writes through the Eio output sink.

Run it from the Nix development environment:

```sh
nix develop --command dune exec --profile release ./bench/profile.exe
```

To run the warmed synthetic application loop, which keeps one scene and its
retained UI tree, input adapter, event queue, output buffer, and Eio sink alive
across warm-up and measurement, use:

```sh
nix develop --command dune exec --profile release ./bench/profile.exe -- \
  --workload warmed
```

The warmed run performs 128 unmeasured frames followed by 512 measured frames.
Each frame admits mixed key, paste, and mouse input, processes queued events,
updates retained UI-tree state, flushes caller-owned output bytes, and writes the
frame through the Eio sink. It is a synthetic steady-state workload, not a
terminal replay or a user-facing latency guarantee.

The values are diagnostic baselines, not absolute gates. Compare runs using
the same compiler, native revision, host, and benchmark parameters. The
profile does not cover Lwd, widgets, or native-owned span views; those features
require separate contracts and workloads.

The retained profile's `retained_pointer` case varies the hit row and
x-coordinate across a warmed 24-row retained UI tree. It is a traversal-shape
diagnostic; the `retained-core/pointer` Thumper case remains a fixed
representative path so its allocation count can stay an exact regression
gate.

## Reference OpenTUI comparisons

The reference OpenTUI source has analogous layout/tree-mutation scenarios in
`packages/core/src/benchmark/layout-benchmark.ts` and direct/parser-inclusive
mouse bubbling scenarios in `packages/core/src/benchmark/mouse-event-benchmark.ts`.
Run the source benchmarks from the reference package directory:

```sh
cd vendor/opentui/packages/core
bun src/benchmark/layout-benchmark.ts \
  --scenario=wide_shallow_siblings_full_render,deep_chain_leaf_full_render,insert_remove_rows_full_render \
  --iterations=16 --warmup=2 --rounds=3 --min-sample-ms=10 --width=40 --height=20
bun src/benchmark/mouse-event-benchmark.ts \
  --depth=8 --direct-iterations=1000 --stdin-iterations=1000 --samples=3 --warmup=1 --json
```

On 2026-08-11, reference revision
`de64d210e4f0163720fc1fbfa838d4d1aad47d53`
ran with Bun 1.3.10 on Darwin arm64. The layout probe reported median
latencies of 325,387 ns/op for the wide tree, 350,360 ns/op for the deep
chain, and 77,188 ns/op for insert/remove rows. The mouse probe reported
72.3 ns/event for direct depth-8 bubbling and 2,009.4 ns/event for the
stdin-SGR path. The short samples have wide relative error, and the suites
exercise different tree sizes, renderers, event representations, and
allocation strategies from the OCaml profile. Use them to keep scenario
meaning and traversal coverage aligned, not to rank the implementations.

## Allocation regression suite

The warmed fixture is also exercised by a separate Thumper suite. It keeps
fixture construction and layout preparation outside the measured region and
checks exact OCaml words for three steady-state cases: retained 80x24 frame
updates, a lossless input burst through the bounded event queue, and
caller-owned output writes. A separate `retained-core` group covers text
updates, layout changes, child reordering, pointer dispatch, and create/destroy
teardown. These cases measure the retained operation itself; they do not add a
wall-time gate yet. Reorder and pointer use fixed representative paths so the
allocation probe can prove an exact per-call count; broader traversal-shape
timing remains diagnostic profile work.

Run the allocation gate explicitly from the release profile:

```sh
nix develop .#test -c dune build @bench --profile release
```

The suite is attached to `@bench`, not ordinary `@runtest`, because each case
is a real performance measurement. The committed
[`warmed.thumper`](warmed.thumper) file is a machine-local allocation
baseline; it is not a portable wall-time promise. The gate measures
`alloc_words` only and has no time budget. Re-baseline only
after reviewing an intentional allocation change on the same compiler and
host, and keep the corrected baseline diff with that change.

## Runtime tracing

Tracing lives in the separate `opentui-bench` development package. The
production packages do not depend on tracing libraries.

`runtime_events_tools` supplies `olly` through Dune's package management. Use
the wrapper from the repository root to report wall, CPU, and GC time together
with GC latency percentiles:

```sh
sh bench/trace_runtime_events.sh gc-stats warmed
```

Omit `warmed` to trace the original isolated probes.

To write a Chrome/Perfetto-compatible runtime event trace:

```sh
sh bench/trace_runtime_events.sh trace /tmp/opentui-profile-warmed.json warmed
```

If the capture reports lost ring-buffer events, treat the trace as incomplete
and repeat with a larger runtime-events ring, for example
`OCAMLRUNPARAM=e=20 sh bench/trace_runtime_events.sh trace /tmp/opentui-profile.json`.
The JSON trace can be opened in [Perfetto](https://ui.perfetto.dev/); the
underlying event model is described in the [OCaml runtime tracing
manual](https://ocaml.org/manual/latest/runtime-tracing.html). The wrapper
also closes the JSON array emitted by the `runtime_events_tools` release
selected in `dune.lock`.

The optional Eio-specific workflow is kept outside the default test shell
because `eio-trace` 0.4 includes a GTK visualizer. After installing that tool
in a tracing-capable environment, record an Eio/fiber trace with:

```sh
sh bench/trace_eio.sh /tmp/opentui-profile-warmed.fxt warmed
eio-trace show /tmp/opentui-profile-warmed.fxt
eio-trace gc-stats /tmp/opentui-profile-warmed.fxt
```

See the [`eio-trace` documentation](https://ocaml.org/p/eio-trace/0.4/doc/README.html)
for installation and rendering details.

The `eio-trace` capture is most informative for the input and output portions
of this benchmark, where Eio is active. The retained and native renderer
sections remain outside Eio and require the runtime-event or CPU profiling
paths. `obs` is not part of this repository because it is not available as a
package in the Dune lock universe. If it becomes available, its integration
belongs in the development-only benchmark package and should use the same
release-profile workload.
