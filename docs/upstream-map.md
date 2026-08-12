# OpenTUI source correspondence map

This file maps the reference OpenTUI source in `vendor/opentui` to the OCaml
source in this repository. In this document, “reference package” means a
directory under `vendor/opentui/packages`, and “reference path” means a file or
directory under one of those packages.

Use this map when a contributor finds a feature in the reference source. The
OCaml location may be a direct path, an adapter package, or an explicitly
unimplemented location. A missing OCaml file is intentional when the status is
`deferred` or `not applicable`.

## Statuses

- **implemented** — the corresponding OCaml behavior and tests exist;
- **partial** — an identified subset of the reference behavior exists;
- **adapter** — an OCaml-specific boundary supplies the behavior or ownership
  model;
- **deferred** — no OCaml implementation is part of the documented API;
- **not applicable** — the reference feature depends on a runtime outside the
  terminal-only OCaml target.

## Reference packages

| Reference package or path | Repository-relative OCaml location | Status and explanation |
| --- | --- | --- |
| `packages/core` | `packages/opentui-core/src` | partial; the OCaml source follows the core source directories and implements the mapped subset. |
| `packages/core/src/zig`, `buffer.ts`, `NativeSpanFeed.ts` | `packages/opentui-raw` | adapter; C/Zig calls, ABI validation, and foreign lifetimes are separate from the retained UI API. |
| `packages/keymap` | `packages/opentui-core/src/lib/keymap` | deferred; no corresponding module is present. |
| `packages/react` | no OCaml package | deferred; an Lwd package would provide the reconciler role without copying React's runtime. |
| `packages/solid` | no OCaml package | deferred; an Lwd package would provide the reconciler role without copying Solid's runtime. |
| `packages/examples` | `packages/opentui-core/examples` | partial; the direct Box/Text executable covers retained renderable construction and output. The executable is kept with the OCaml package whose API it demonstrates. |
| `packages/qrcode` | no OCaml package | deferred; the image/rendering ownership contract is not defined. |
| `packages/ssh` | no OCaml package | not applicable to the terminal UI library. |
| `packages/three` | no OCaml package | not applicable to the terminal UI library. |
| `packages/web` | no OCaml package | not applicable to the native terminal UI library. |

## `packages/core/src`

| Reference path | Repository-relative OCaml path | Status | Notes |
| --- | --- | --- | --- |
| `Renderable.ts` | `packages/opentui-core/src/scene.ml` and `packages/opentui-core/src/renderables/` | partial | `Scene` owns the retained UI tree; the TypeScript class hierarchy is represented by composition. |
| `renderer.ts` | `packages/opentui-core/src/renderer.ml` | partial | The native frame lifecycle exists; terminal application policy is composed by the caller. |
| `yoga.ts` | `packages/opentui-core/src/yoga.ml` | partial | Owner-scoped Yoga layout tree with fixed dimensions and padding. |
| `buffer.ts` | `packages/opentui-raw/buffer.ml` | adapter | Cell storage remains native; checked operations cross the ABI instead of exposing an OCaml grid. |
| `NativeSpanFeed.ts` | `packages/opentui-raw/span_feed.ml` | adapter | Payloads are copied and release/cancel ownership is explicit. |
| `renderables/Box.ts` | `packages/opentui-core/src/renderables/box.ml` | partial | Fill, border, layout participation, and typed properties. |
| `renderables/Text.ts` | `packages/opentui-core/src/renderables/text.ml` | partial | Copied plain text; styled and nested text are not part of the documented API. |
| `renderables/TextNode.ts` | `packages/opentui-core/src/renderables/text_node.ml` | deferred | No module is present. |
| `renderables/TextBufferRenderable.ts` | `packages/opentui-core/src/renderables/text_buffer.ml` | deferred | Requires a defined text-buffer contract. |
| `renderables/EditBufferRenderable.ts` | `packages/opentui-core/src/renderables/edit_buffer.ml` | deferred | Requires a defined OCaml state and event ownership model. |
| `renderables/FrameBuffer.ts` | `packages/opentui-core/src/renderables/frame_buffer.ml` | deferred | Requires a stable public buffer/view contract. |
| `renderables/Input.ts` | `packages/opentui-core/src/renderables/input.ml` | deferred | Direct control API is not present. |
| `renderables/Textarea.ts` | `packages/opentui-core/src/renderables/textarea.ml` | deferred | Direct control API is not present. |
| `renderables/Select.ts` | `packages/opentui-core/src/renderables/select.ml` | deferred | Direct control API is not present. |
| `renderables/ScrollBox.ts` | `packages/opentui-core/src/renderables/scroll_box.ml` | deferred | Direct control API is not present. |
| `renderables/Slider.ts` | `packages/opentui-core/src/renderables/slider.ml` | deferred | Direct control API is not present. |
| `renderables/TabSelect.ts` | `packages/opentui-core/src/renderables/tab_select.ml` | deferred | Direct control API is not present. |
| `renderables/ScrollBar.ts` | `packages/opentui-core/src/renderables/scroll_bar.ml` | deferred | Direct control API is not present. |
| `renderables/Code.ts`, `Diff.ts`, `Markdown.ts`, `TextTable.ts` | matching paths under `packages/opentui-core/src/renderables` | deferred | Content renderables require a broader text contract. |
| `renderables/Image.ts`, `ASCIIFont.ts` | matching paths under `packages/opentui-core/src/renderables` | deferred | Image and font ownership is not defined. |
| `renderables/composition/*` | `packages/opentui-core/src/renderables/composition` | deferred | A convenience layer must use the retained node identity rather than create another tree. |
| `lib/stdin-parser.ts` | `packages/opentui-core/src/lib/stdin_parser.ml` | implemented | Incremental framing with bounded, owned events. |
| `lib/parse.keypress.ts` | `packages/opentui-core/src/lib/key_decoder.ml` | partial | Common key semantics; unknown sequences remain opaque. |
| `lib/parse.mouse.ts` | `packages/opentui-core/src/lib/mouse_decoder.ml` | partial | SGR/X10 mouse semantics and button tracking. |
| `lib/queue.ts` | `packages/opentui-core/src/lib/byte_queue.ml` and `event_queue.ml` | adapter | Byte storage and bounded event handoff are separate explicit queues. |
| `lib/paste.ts` | `packages/opentui-core/src/lib/stdin_parser.ml` | partial | Bracketed paste framing belongs to the parser. |
| `lib/clock.ts` | `packages/opentui-core/src/platform/eio_runtime` | adapter | Eio monotonic time supplies runtime deadlines. |
| `lib/terminal-*`, `ansi.ts` | `packages/opentui-core/src/lib/terminal_modes.ml` and terminal modules | partial | Pure mode descriptions are separate from Eio writes. |
| `platform/eio` | `packages/opentui-core/src/platform/eio_runtime` | adapter | The directory name avoids shadowing the external `Eio` module under Dune qualified subdirectories. |
| `platform/unix` | `packages/opentui-core/src/platform/eio_unix_runtime` | adapter | The directory name avoids shadowing the external `Unix` module under Dune qualified subdirectories. |
| `platform/*` | `packages/opentui-core/src/platform` | adapter | Eio flow and Unix terminal policy. The specific directory mappings above define the OCaml names. |
| `post/*` | matching paths under `packages/opentui-core/src/post` | deferred | No post-processing contract is present. |
| `animation/*` | matching paths under `packages/opentui-core/src/animation` | deferred | No animation scheduler is present. |
| `plugins/*` | matching paths under `packages/opentui-core/src/plugins` | deferred | No plugin contract is present. |
| `audio*` | matching paths under `packages/opentui-core/src/audio*` | not applicable | Outside the terminal UI target. |
| `image.ts` | `packages/opentui-core/src/image.ml` | deferred | Requires a native image ownership decision. |
| `text-buffer.ts`, `text-buffer-view.ts`, `edit-buffer.ts`, `editor-view.ts` | matching paths under `packages/opentui-core/src` | deferred | Editor and buffer semantics are not present. |
| `testing/*`, `tests/*` | `packages/opentui-core/test` | adapter | Windtrap and Cram provide package-local OCaml tests for the corresponding core behavior. |
| `benchmark/*` | `packages/opentui-core/bench` | adapter | Thumper, profile workloads, and tracing wrappers provide package-local OCaml measurements. |
| core parser comparison harness | `packages/opentui-core/reference` | adapter | The comparison runners and shared vectors are OCaml repository tooling associated with the core parser; they are not a second runtime layer. |

The raw package's ABI and link tests live in `packages/opentui-raw/test` because
they validate the separate C/Zig boundary. Repository-wide architecture,
source-mapping, planning, and performance-policy documents remain under the
repository root because they describe more than one package.

## Translation rules

These rules apply when a reference relationship does not have a literal OCaml
equivalent:

| TypeScript relationship | OCaml rule |
| --- | --- |
| Inheritance between renderables | Compose a retained node with a typed renderable module. |
| `EventEmitter` base behavior | Use typed event values and cleanup owned by the scene or runtime scope. |
| Mutable option/property bags | Use labelled constructors, typed setters, and explicit clear operations. |
| Ambient renderer lookup | Pass the renderer, scene, parent, or Eio capability explicitly. |
| Promise/timer scheduling | Use Eio fibers and clocks at the platform boundary. |
| React/Solid host reconciliation | Bind Lwd values to existing retained nodes; do not create a second required tree. |

Every non-literal translation needs a map entry, an ownership invariant, and a
test whose observable behavior can be compared with the reference when that
comparison is meaningful.
