# Implementation plan

This plan records the implementation order for the OCaml OpenTUI library. The
reference source is `vendor/opentui`; package boundaries and terminology are
defined in [`docs/architecture.md`](docs/architecture.md). The [source
correspondence map](docs/upstream-map.md) identifies the OCaml location of
each reference feature.

## Repository capabilities

- The repository contains the Dune monorepo, Nix development environment, and
  fixed OpenTUI reference source.
- `opentui-raw` contains the audited Zig/C ABI and native link boundary.
- The raw renderer, Yoga, output-feed, capability, and event ownership modules
  define the native-facing core.
- `Scene` defines retained identity, layout, flush, pointer, and teardown
  behavior.
- `Box` and plain `Text` provide direct renderables with deterministic examples.
- `Stdin_parser` provides typed incremental terminal parsing, with
  `Key_decoder` and `Mouse_decoder` as parser helpers, plus mode descriptions
  and bounded event handoff.
- Eio flow/output/wakeup/dispatch and Unix terminal-session modules provide the
  terminal runtime building blocks.
- The corresponding implementations reside in `opentui-core/src/lib` and
  `opentui-core/src/platform`.

## Package structure

- `opentui-core` is the Eio-native public package for the retained UI tree,
  renderables, terminal protocols, and terminal platform modules.
- `opentui-raw` is the separate C/Zig ABI package. It owns foreign handles,
  ABI validation, and native resource lifetimes.
- Package-owned tests, examples, reference comparisons, and benchmarks live
  under the package they exercise. Repository-wide architecture, mapping,
  planning, and performance-policy documents remain at the repository root.
- Every implemented feature has a repository-relative entry in the source
  correspondence map.
- Cross-cutting feature contracts live under `docs/major-features`; active
  contracts are separate from non-normative context records.
- TypeScript inheritance, event emitters, ambient context, and reconciliation
  are represented by the translation rules in the architecture document.
- Historical design documents live under `docs/archive/` and do not define the
  active package contract.

## Integrated Eio terminal runtime

The integrated runtime composes the scene, input, output, resize, and
terminal-session modules into an Eio-native terminal runtime under the
corresponding `opentui-core/src/renderer` and `src/platform` concepts. The
runtime has one parser, one scene, and one renderer.

Acceptance criteria:

- One Eio switch owns terminal setup, input, output, and restoration.
- A Box/Text app enters the alternate screen, renders, accepts a key, and
  restores terminal state on normal and exceptional exit.
- Resize events reach the scene without dropping lossless input.
- The runtime has a deterministic non-PTY test seam and a host-gated PTY
  acceptance test.
- The source correspondence map has an entry for every runtime module.
- The runtime has no dependency on Lwd, widgets, editor buffers, or a
  convenience composition layer.

## Deferred feature groups

The following feature groups are outside the implemented library surface:

- foundational styled/nested text and layout properties;
- direct renderables and controls in mirrored `src/renderables` paths;
- an optional `src/renderables/composition` convenience layer;
- Lwd bindings over the retained tree; and
- measured allocation and comparative behavior/performance work for each
  feature family.

Zero-copy and bespoke memory-management candidates are documented in
[`future-performance.md`](future-performance.md). They are separate from the
correctness work in the structural review and terminal-runtime units.
