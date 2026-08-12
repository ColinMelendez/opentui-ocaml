# opentui-core

`opentui-core` is the user-facing OCaml library for terminal UI programs. It
uses Eio for terminal resource lifetime and I/O, and it uses `opentui-raw` for
checked calls to the Zig renderer. The source directories correspond to
`vendor/opentui/packages/core/src`, the matching directory in the reference
OpenTUI source tree. Package-specific tests, examples, reference comparisons,
and benchmarks are kept beside this source tree under `test/`, `examples/`,
`reference/`, and `bench/`.

## Scene and renderables

A scene is the owner of a retained UI tree. It owns a renderer and a Yoga
layout tree, and it keeps each attached node alive until that node is
destroyed. Yoga is the layout engine that calculates node positions and
dimensions. A retained node has a stable identity, so changing text,
dimensions, colors, or border properties updates the existing node instead of
constructing a replacement.

The public scene API provides:

- `Scene.create` and `Scene.root` for creating a tree and obtaining its root;
- `Scene.Box` for a filled or bordered rectangular container;
- `Scene.Text` for copied plain text with colors and attributes;
- `Scene.Node` for child ordering, dimensions, destruction, and pointer handlers;
- `Scene.flush` for layout calculation and output into caller-owned `bytes`; and
- `Scene.dispatch_pointer` for hit-testing and target-to-parent propagation.

`Scene.flush` is the frame boundary. It skips an unchanged scene unless
`force:true` is supplied. A rendered result reports the defined prefix of the
caller-owned output buffer. `Platform.Eio_runtime.Output_flow` can write that
prefix to an Eio output flow. A failed frame leaves the scene dirty so the
caller can inspect the error or retry the operation.

The example in [`examples/README.md`](examples/README.md) shows a Box
containing Text, two property updates, and the resulting frame output.

## Terminal modules

`Lib` contains the terminal protocol, input decoding, mode descriptions, and
bounded event handoff modules. `Platform.Eio_runtime` contains Eio flow,
wakeup, output, and dispatch modules. `Platform.Eio_unix_runtime` contains
Unix terminal-size, signal, and termios-session modules. These modules expose
the building blocks needed to compose an application runtime; this package
does not provide a single implicit application loop.

Lwd is the OCaml incremental-computation library intended for reactive UI
bindings. It is not a dependency of `opentui-core`. The documented
`opentui-core` API does not include the following features:

- styled or nested text beyond the plain `Text` renderable;
- the remaining OpenTUI renderables and direct controls;
- editor buffers, image/audio support, or post-processing;
- an Lwd reactive binding package; or
- widget-level focus and keyboard-routing policy.

The source location and status of each omitted reference feature are listed in
the [source correspondence map](../../docs/upstream-map.md).
