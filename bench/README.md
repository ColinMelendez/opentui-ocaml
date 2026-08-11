# Performance profile

`profile.exe` is a small repeatable native benchmark for the current public
seams. It reports monotonic elapsed nanoseconds and OCaml GC words for:

- retained text updates and caller-owned resolved-character output;
- retained dimension/layout updates, child reordering, and create/destroy
  lifecycle churn;
- full 80x24 native frame updates and resolved-character output;
- Eio input reads through the terminal coordinator; and
- repeated writes through the Eio output sink.

Run it from the Nix development environment:

```sh
nix develop --command dune exec --profile release ./bench/profile.exe
```

To run the warmed synthetic application loop, which keeps one retained scene,
input adapter, event queue, output buffer, and Eio sink alive across warm-up and
measurement, use:

```sh
nix develop --command dune exec --profile release ./bench/profile.exe -- \
  --workload warmed
```

The warmed run performs 128 unmeasured frames followed by 512 measured frames.
Each frame admits mixed key, paste, and mouse input, processes queued events,
updates retained scene state, flushes caller-owned output bytes, and writes the
frame through the Eio sink. It is a synthetic steady-state workload, not a
terminal replay or a user-facing latency guarantee.

The values are diagnostic baselines, not absolute gates. Compare runs using
the same compiler, native revision, host, and benchmark parameters. The
profile intentionally does not cover Lwd, widgets, or native-owned span
views; those require their own contracts first.

## Allocation regression suite

The warmed fixture is also exercised by a separate Thumper suite. It keeps
fixture construction outside the measured region and checks exact OCaml words
for three steady-state cases: retained 80x24 frame updates, a lossless input
burst through the bounded event queue, and caller-owned output writes.

Run the allocation gate explicitly from the release profile:

```sh
nix develop .#test -c dune build @bench --profile release
```

The suite is attached to `@bench`, not ordinary `@runtest`, because each case
is a real performance measurement. The committed
[`warmed.thumper`](warmed.thumper) file is a machine-local allocation
baseline; it is intentionally not a portable wall-time promise. The current
gate measures `alloc_words` only, with no time budget yet. Re-baseline only
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
also closes the JSON array emitted by the currently pinned
`runtime_events_tools` release.

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
paths. `obs` is not wired into this repository yet because it is not available
as a package in the current Dune lock universe; it should be added later as a
development-only wrapper around the same release-profile workload.
