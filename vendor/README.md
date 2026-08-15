# Reference OpenTUI source

OpenTUI is a terminal user-interface framework whose reference implementation
uses TypeScript and a Zig renderer. [`opentui/`](opentui/) is the Git submodule
that contains that reference source. The submodule provides source navigation,
native build inputs, and behavior/API comparisons; it is not an OCaml package
and should not be modified as part of ordinary OCaml work.

The parent repository pins revision
`ae272000a5d12425c253c4537eb5e9e57df9265a`. The native build at that revision
requires Zig 0.16.0, provided by the repository's Nix development shell.

The OCaml packages implement a selected terminal UI subset. The source tree
does not automatically expose every export in
`opentui/packages/core/src/zig/lib.zig`; editor, audio, clipboard, image, and other
subsystems are outside the documented terminal UI scope. Their correspondence
status is recorded in the [source correspondence map](../docs/upstream-map.md).

When updating the submodule, review its build metadata and exported surface
together, update the parent Git link, and record changed ABI or ownership
assumptions in [`../packages/opentui-raw/native/ABI.md`](../packages/opentui-raw/native/ABI.md),
[`../docs/architecture.md`](../docs/architecture.md), and the [source
correspondence map](../docs/upstream-map.md).
