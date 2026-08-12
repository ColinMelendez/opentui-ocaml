# Upstream OpenTUI

[`opentui/`](opentui/) is a pinned Git submodule containing the upstream
OpenTUI source. It is kept here for local source navigation, native build
integration, and API audits; it is not an OCaml package and should not be
modified as part of ordinary OCaml work.

The parent repository currently pins revision
`de64d210e4f0163720fc1fbfa838d4d1aad47d53`. The native build at that revision
requires Zig 0.16.0, provided by the repository's Nix development shell.

The OCaml project will bind a deliberately selected TUI subset of the native
surface. It will not automatically mirror every export in
`opentui/packages/core/src/zig/lib.zig`; editor, audio, image, and other
subsystems remain out of scope until they have a concrete OCaml consumer.

When updating the submodule, review the upstream build metadata and exported
surface together, update the parent gitlink, and record any changed ABI or
ownership assumptions in [`../docs/architecture.md`](../docs/architecture.md)
and [`../docs/upstream-map.md`](../docs/upstream-map.md).
