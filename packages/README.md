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
