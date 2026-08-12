# Packages

OpenTUI is a terminal user-interface framework whose reference implementation
is checked out in `vendor/opentui`. This directory contains the two OCaml
packages that implement and expose the terminal UI library. The package
boundary is explicit: `opentui-core` is the UI library, and `opentui-raw` is
the low-level foreign-function boundary that `opentui-core` uses.

## Package layout

[`opentui-core`](opentui-core/) is the user-facing Eio-native library. Its
source directories correspond to the directories in
`vendor/opentui/packages/core/src`:

```text
opentui-core/src/
├── renderer.ml              frame lifecycle and output
├── yoga.ml                  layout ownership and readback
├── renderables/             retained Box and Text implementations
├── lib/                     terminal protocol and input modules
├── platform/                Eio and Unix terminal integration
│   ├── eio_runtime/
│   └── eio_unix_runtime/
├── scene.ml                 retained UI-tree owner
└── native/                  OCaml errors for native composition
```

The package-local validation and development material is beside the source:

```text
opentui-core/
├── src/                      library implementation
├── test/                     core behavior tests
├── examples/                 public API examples and Cram transcripts
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
inspect the ABI boundary without also loading the scene, renderable, or
terminal-runtime API.

For a path-by-path lookup from the reference source to the OCaml source, use
the [source correspondence map](../docs/upstream-map.md). For package ownership and
the Eio effect boundary, use [`docs/architecture.md`](../docs/architecture.md).
