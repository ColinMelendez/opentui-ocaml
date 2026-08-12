# Implementation plan

This plan records the implementation order for the OCaml OpenTUI library. The
reference source is `vendor/opentui`; package boundaries and terminology are
defined in [`docs/architecture.md`](docs/architecture.md). The [source
correspondence map](docs/upstream-map.md) identifies the OCaml location of
each reference feature.

## Implemented units

- the Dune monorepo, Nix development environment, and fixed OpenTUI reference source;
- the audited Zig/C ABI and native link boundary in `opentui-raw`;
- the raw renderer, Yoga, output-feed, capability, and event ownership modules;
- retained `Scene` identity, layout, flush, pointer, and teardown behavior;
- direct `Box` and plain `Text` renderables with deterministic examples;
- incremental terminal framing, key/mouse decoding, mode descriptions, and
  bounded event handoff;
- Eio flow/output/wakeup/dispatch and Unix terminal-session building blocks;
- those implementations located in the corresponding
  `opentui-core/src/lib` and `opentui-core/src/platform` directories.

## Package structure decisions

- `opentui-core` is the Eio-native public package for the retained UI tree,
  renderables, terminal protocols, and terminal platform modules.
- `opentui-raw` is the separate C/Zig ABI package. It owns foreign handles,
  ABI validation, and native resource lifetimes.
- Every implemented feature has a repository-relative entry in the source
  correspondence map.
- TypeScript inheritance, event emitters, ambient context, and reconciliation
  are represented by the translation rules in the architecture document.
- Historical design documents live under `docs/archive/` and do not define the
  active package contract.

## Implementation unit: integrated Eio terminal runtime

Compose the existing scene, input, output, resize, and terminal-session
modules into an Eio-native terminal runtime under the corresponding
`opentui-core/src/renderer` and `src/platform` concepts. The runtime must not
introduce a second parser, scene, or renderer.

Acceptance criteria:

- one Eio switch owns terminal setup, input, output, and restoration;
- a Box/Text app can enter the alternate screen, render, accept a key, and
  restore terminal state on normal and exceptional exit;
- resize events reach the scene without dropping lossless input;
- the runtime has a deterministic non-PTY test seam and a host-gated PTY
  acceptance test;
- the source correspondence map is updated for every new module;
- the runtime has no dependency on Lwd, widgets, editor buffers, or a
  convenience composition layer.

## Following implementation units

- foundational styled/nested text and layout properties;
- remaining direct renderables and controls in mirrored `src/renderables`
  paths;
- optional `src/renderables/composition` convenience layer;
- Lwd bindings over the retained tree; and
- measured allocation and comparative behavior/performance work for each
  feature family.

Zero-copy and bespoke memory-management candidates are documented in
[`future-performance.md`](future-performance.md). They are separate from the
correctness work in the structural review and terminal-runtime units.
