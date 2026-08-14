# Packages

OpenTUI is a terminal user-interface framework whose reference implementation
is checked out in `vendor/opentui`. This directory contains the OCaml packages
that port the reference package boundaries. The package boundary is explicit:
`opentui-core` owns the Eio-native UI and terminal library, and `opentui-raw`
owns the low-level foreign-function boundary that `opentui-core` uses.

## Package layout

[`opentui-core`](opentui-core/) is the user-facing Eio-native library. Its
implemented source directories follow the directories in
`vendor/opentui/packages/core/src`; the complete coverage and deferred areas
are recorded in the [core source mirror](../docs/major-features/in-progress/core-source-mirror/feature.md):

```text
opentui-core/src/
├── renderer.ml              renderer ownership and frame execution
├── render_context.ml        renderer-owned capabilities
├── buffer.ml                checked borrowed drawing views
├── color.ml                 raw-backed renderer color values
├── error.ml                 structured core errors
├── event_kernel.ml          internal synchronous event dispatch
├── yoga.ml                  independent layout-node ownership and readback
├── event_subscription.ml    owner-local notification cancellation
├── layout_children.ml       typed layout-child capability
├── renderer_events.ml       internal renderer event vocabulary
├── native_measure.ml        internal text measurement seam
├── lib/                     terminal protocol and input modules
├── platform/                Eio and Unix terminal integration
│   ├── eio_runtime/
│   └── eio_unix_runtime/
└── native/                  core-side errors for native composition
```

The package-local validation and development material is beside the source:

```text
opentui-core/
├── src/                      library implementation
├── test/                     core behavior tests
├── examples/                 executable public API examples
├── reference/                optional comparisons with the reference source
└── bench/                    profiles, allocation baselines, and tracing
```

The raw package keeps its ABI and native-link tests in
[`opentui-raw/test`](opentui-raw/test). The active architecture and source-map
documents remain in the repository-level [`docs/`](../docs/) directory because
they explain the boundary between both packages; package-specific usage notes
are kept in each package README and its local development directories.

[`opentui-raw`](opentui-raw/) translates calls between OCaml and the C/Zig
interface exported by the renderer in `vendor/opentui`. It owns typed foreign
handles, native resource lifetimes, ABI validation, and the native build/link
rules. It is separate from `opentui-core` because those responsibilities are
different from retained UI ownership and because the higher-level package must
not expose raw pointers or packed handle values.

The dependency direction is:

```text
opentui-core  ──depends on──>  opentui-raw  ──calls──>  reference Zig renderer
```

`opentui-raw` does not depend on `opentui-core`. A contributor can therefore
inspect the ABI boundary without also loading the retained-rendering or
terminal-runtime API.

For a path-by-path lookup from the reference source to the OCaml source, use
the [source correspondence map](../docs/upstream-map.md). For package
ownership and the Eio effect boundary, use
[`docs/architecture.md`](../docs/architecture.md). For the procedure for
adding a corresponding feature, use the repository
[`CONTRIBUTING.md`](../CONTRIBUTING.md).
