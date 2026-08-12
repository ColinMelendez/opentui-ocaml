# Current plan

Status: structure established; review gate, 2026-08-11.

The project follows the pinned OpenTUI source tree. Read
[`docs/architecture.md`](docs/architecture.md) for the package and effect
model, and [`docs/upstream-map.md`](docs/upstream-map.md) to locate an OCaml
counterpart for an upstream path.

## Completed

- the Dune monorepo, Nix development environment, and pinned OpenTUI source;
- the audited Zig/C ABI and native link seam in `opentui-raw`;
- the raw renderer, Yoga, output-feed, capability, and event ownership slices;
- the retained `Scene` identity, layout, flush, pointer, and teardown slice;
- direct `Box` and plain `Text` renderables with deterministic examples;
- incremental terminal framing, key/mouse decoding, mode descriptions, and
  bounded event handoff;
- Eio flow/output/wakeup/dispatch and Unix terminal-session building blocks;
- movement of those implementations into the mirrored
  `opentui-core/src/lib` and `opentui-core/src/platform` tree.

## Current gate: review the structure

Before implementing more renderables, review:

1. whether `opentui-core` is the right single Eio-native public package;
2. whether every current implementation is findable from its upstream path;
3. whether the translation rules for inheritance, events, ownership, and
   reconciliation are clear enough for contributors;
4. whether the `opentui-raw` exception is understandable and remains narrow;
5. whether the archived design documents should be retained, shortened, or
   replaced with focused notes.

## Next implementation gate, after review

Add the smallest integrated Eio-native CLI renderer/runtime under the mirrored
`opentui-core/src/renderer` and `src/platform` concepts. It should compose the
existing scene, input, output, resize, and terminal-session modules rather
than introduce parallel ownership or parsing abstractions.

Acceptance criteria:

- one Eio switch owns terminal setup, input, output, and restoration;
- a basic Box/Text app can enter the alternate screen, render, accept a key,
  and restore terminal state on normal and exceptional exit;
- resize events reach the scene without dropping lossless input;
- the runtime has a deterministic non-PTY test seam and a host-gated PTY
  acceptance test;
- the upstream correspondence map is updated for every new module;
- no Lwd, widgets, editor, or convenience composition layer is required by
  the first runtime.

## Later gates

- foundational styled/nested text and layout properties;
- remaining direct renderables and controls in mirrored `src/renderables`
  paths;
- optional `src/renderables/composition` convenience layer;
- Lwd bindings over the retained tree;
- measured allocation and comparative behavior/performance work for each
  feature family.

Deferred zero-copy and bespoke memory-management ideas remain in
[`future-performance.md`](future-performance.md). They are not prerequisites
for this structural review or for the first integrated runtime.
