# Performance profile

`profile.exe` measures a warmed renderer-buffer loop. Each iteration clears a
borrowed native buffer, draws a short string, resolves the buffer into
caller-owned bytes, records a coalesced render request, and executes one native
frame. The profile reports elapsed monotonic time, allocated words, and GC
collections.

Run the default and warmed profiles from the repository root:

```sh
nix develop -c dune exec --profile release \
  ./packages/opentui-core/bench/profile.exe
nix develop -c dune exec --profile release \
  ./packages/opentui-core/bench/profile.exe -- --workload warmed
```

The warmed profile repeats the same owner and borrowed buffer for 512 measured
iterations. The default profile uses 64 iterations. Values are diagnostic
baselines; compare runs with the same compiler, native revision, host, and
parameters.

The reference OpenTUI renderer and native buffer benchmarks remain under
`vendor/opentui/packages/core/src/benchmark` and
`vendor/opentui/packages/core/src/zig/bench`. Compare scenario meaning and
ownership boundaries before comparing measurements.

## Runtime tracing

Tracing lives in the development-only `opentui-bench` package. The production
packages do not depend on tracing libraries.

Runtime-event tracing uses the wrapper from the repository root:

```sh
sh packages/opentui-core/bench/trace_runtime_events.sh gc-stats warmed
sh packages/opentui-core/bench/trace_runtime_events.sh \
  trace /tmp/opentui-profile-warmed.json warmed
```

The JSON trace can be opened in [Perfetto](https://ui.perfetto.dev/). If the
capture reports lost ring-buffer events, repeat it with a larger runtime-event
ring such as `OCAMLRUNPARAM=e=20`.

The optional Eio-specific workflow is separate because `eio-trace` includes a
GTK visualizer:

```sh
sh packages/opentui-core/bench/trace_eio.sh /tmp/opentui-profile.fxt warmed
eio-trace show /tmp/opentui-profile.fxt
```

The profile’s renderer and buffer work is synchronous and is best inspected
with runtime-event or CPU tracing. Eio tracing applies when the profile or its
surrounding application performs Eio work.
