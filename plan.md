# Implementation plan

This document records the current implementation boundary and the next
bounded integration work for the OCaml OpenTUI library. The vendored source in
`vendor/opentui` is the reference. Package boundaries and terminology are
defined in [`docs/architecture.md`](docs/architecture.md), and source
correspondence is recorded in [`docs/upstream-map.md`](docs/upstream-map.md).

The plan is not a claim that the reference library has been fully reproduced.
Reference areas without an OCaml destination remain explicitly deferred in the
source map.

## Current foundation

The repository currently provides:

- the Dune monorepo, Nix development environment, and fixed OpenTUI reference
  source;
- `opentui-raw`, which owns the audited Zig/C ABI and native resource boundary;
- `opentui-wgpu`, a scaffold for the typed `webgpu.h` boundary over the pinned
  official wgpu-native release, registered for the three-renderer feature
  record;
- `opentui-core` renderer/context ownership, borrowed native buffers, and
  independently owned Yoga nodes;
- typed incremental terminal parsing in `Lib.Stdin_parser`, with
  `Lib.Key_decoder`, `Lib.Mouse_decoder`, `Lib.Input_coordinator`, and
  `Lib.Event_queue` providing parser support and bounded handoff; and
- Eio and Unix terminal building blocks under
  `Platform.Eio_runtime` and `Platform.Eio_unix_runtime`, including input,
  output, wakeup, dispatch, resize, and terminal-session modules.

Examples, package tests, reference comparisons, and benchmarks live with the
package whose behavior they exercise.

## Current integration boundary

The Eio and Unix modules are composable runtime building blocks. They do not
yet form a single high-level terminal application runtime or provide an
implicit application loop. `Renderer.render` is an explicit frame execution
and presentation boundary, and `Platform.Eio_runtime.Dispatch` remains a
caller-run dispatch loop over the bounded event handoff.

The renderer owns a private typed event-channel kernel for resize and frame
notifications. `Lib.Event_queue` remains the bounded terminal-input handoff;
it is not the observer-channel abstraction described by the event-system
design.

The event-system record defines that cross-cutting abstraction and considers
both current and future producers. Its design includes future event families
such as audio and edit-buffer events so that the abstraction has the correct
ownership and scheduling shape before those components are implemented. The
presence of those design cases does not make the corresponding components part
of the current package surface.

## Planned terminal integration

The planned terminal integration target is a high-level Eio composition of the
renderer, input, output, resize, and terminal-session building blocks. Its target
contract is:

- one Eio switch owns terminal setup, input, output, and restoration;
- a `Box`/`Text` application can enter the alternate screen, render, accept a
  key, and restore terminal state on normal and exceptional exit;
- resize events reach the renderer without dropping lossless input;
- deterministic non-PTY tests and host-gated PTY acceptance tests exercise the
  integration; and
- the integration remains independent of Lwd, widgets, editor buffers, audio,
  and convenience composition layers.

This is an integration target, not a description of functionality already
exposed by `opentui-core`.

## Later feature work

The following remain future work for the package surface:

- styled and nested text and the remaining layout properties;
- the remaining direct renderables and controls;
- editor buffers, text-buffer views, image, audio, and post-processing;
- the composition and convenience layers represented by deferred reference
  paths.

Zero-copy and bespoke memory-management candidates are documented separately
in [`future-performance.md`](future-performance.md). They are not prerequisites
for the current correctness and integration work.
