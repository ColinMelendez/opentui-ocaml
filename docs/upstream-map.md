# OpenTUI correspondence map

This is the navigation index between the pinned upstream source and this
repository. The upstream revision is the submodule revision recorded by Git
under `vendor/opentui`.

When a contributor finds a path under `vendor/opentui/packages/*/src`, use the
tables below before opening an issue or adding a new abstraction. A status of
`deferred` or `not applicable` is an intentional answer; it does not imply
that a same-named placeholder should be created.

## Statuses

- **implemented** — an OCaml implementation and behavior tests exist;
- **partial** — the path has a deliberately smaller first slice;
- **adapter** — the behavior is provided by an OCaml-specific boundary;
- **deferred** — planned, but not part of the current implementation gate;
- **not applicable** — tied to a JavaScript, browser, audio, or other runtime
  outside this project's scope.

## Upstream packages

| Upstream package | OCaml location | Status and explanation |
| --- | --- | --- |
| `packages/core` | `packages/opentui-core/src` | The primary source-path mirror. |
| `packages/core` native ABI under `src/zig`, `buffer.ts`, and `NativeSpanFeed.ts` | `packages/opentui-raw` | adapter; the C/Zig ownership seam is intentionally separate from the public core tree. |
| `packages/keymap` | `opentui-core/src/lib/keymap` when implemented | deferred; no public OCaml module yet. |
| `packages/react` | `opentui-lwd` | deferred; Lwd replaces the React reconciler role. |
| `packages/solid` | `opentui-lwd` | deferred; Lwd replaces the Solid reconciler role. |
| `packages/examples` | `examples/` | partial; direct renderable examples are present. |
| `packages/qrcode` | none | deferred until the core image/rendering contract exists. |
| `packages/ssh` | none | not applicable to the current core target. |
| `packages/three` | none | not applicable to the terminal-only target. |
| `packages/web` | none | not applicable to the native terminal target. |

## `packages/core/src`

| Upstream path | OCaml path | Status | Notes |
| --- | --- | --- | --- |
| `Renderable.ts` | `opentui-core/src/scene.ml` and retained renderable modules | partial | Persistent identity and ownership exist; the TypeScript class hierarchy is replaced by composition. |
| `renderer.ts` | `opentui-core/src/renderer.ml` | partial | Native frame lifecycle exists; the integrated Eio CLI renderer is the next reviewed increment. |
| `yoga.ts` | `opentui-core/src/yoga.ml` | partial | Owner-scoped Yoga tree and fixed dimensions/padding are implemented. |
| `buffer.ts` | `opentui-raw/buffer.ml` | adapter | Cell storage stays native; the raw package exposes checked operations rather than a copied OCaml grid. |
| `NativeSpanFeed.ts` | `opentui-raw/span_feed.ml` | adapter | Current seam uses copied payloads and explicit release/cancel ownership. |
| `renderables/Box.ts` | `opentui-core/src/renderables/box.ml` | partial | Fill, border, layout participation, and typed properties exist. |
| `renderables/Text.ts` | `opentui-core/src/renderables/text.ml` | partial | Copied plain text exists; styled and nested text remain deferred. |
| `renderables/TextNode.ts` | `opentui-core/src/renderables/text_node.ml` | deferred | No placeholder module is present. |
| `renderables/TextBufferRenderable.ts` | `opentui-core/src/renderables/text_buffer.ml` | deferred | Depends on the text-buffer contract. |
| `renderables/EditBufferRenderable.ts` | `opentui-core/src/renderables/edit_buffer.ml` | deferred | The OCaml state/event relationship must be designed before implementation. |
| `renderables/FrameBuffer.ts` | `opentui-core/src/renderables/frame_buffer.ml` | deferred | Requires a stable public buffer/view contract. |
| `renderables/Input.ts` | `opentui-core/src/renderables/input.ml` | deferred | Direct control family, no Lwd dependency implied. |
| `renderables/Textarea.ts` | `opentui-core/src/renderables/textarea.ml` | deferred | Direct control family. |
| `renderables/Select.ts` | `opentui-core/src/renderables/select.ml` | deferred | Direct control family. |
| `renderables/ScrollBox.ts` | `opentui-core/src/renderables/scroll_box.ml` | deferred | Direct control family. |
| `renderables/Slider.ts` | `opentui-core/src/renderables/slider.ml` | deferred | Direct control family. |
| `renderables/TabSelect.ts` | `opentui-core/src/renderables/tab_select.ml` | deferred | Direct control family. |
| `renderables/ScrollBar.ts` | `opentui-core/src/renderables/scroll_bar.ml` | deferred | Direct control family. |
| `renderables/Code.ts`, `Diff.ts`, `Markdown.ts`, `TextTable.ts` | matching files under `opentui-core/src/renderables` | deferred | Content renderables are ported after foundational text behavior. |
| `renderables/Image.ts`, `ASCIIFont.ts` | matching files under `opentui-core/src/renderables` | deferred | Requires a deliberate image/font boundary. |
| `renderables/composition/*` | `opentui-core/src/renderables/composition` | deferred | Optional convenience layer; it must not create a second identity tree. |
| `lib/stdin-parser.ts` | `opentui-core/src/lib/stdin_parser.ml` | implemented | Incremental framing with bounded, owned events. |
| `lib/parse.keypress.ts` | `opentui-core/src/lib/key_decoder.ml` | partial | Common key semantics are implemented; unknown sequences remain opaque. |
| `lib/parse.mouse.ts` | `opentui-core/src/lib/mouse_decoder.ml` | partial | SGR/X10 mouse semantics and button tracking are implemented. |
| `lib/queue.ts` | `opentui-core/src/lib/byte_queue.ml` and `event_queue.ml` | adapter | Byte storage and bounded event handoff are separate explicit queues. |
| `lib/paste.ts` | `opentui-core/src/lib/stdin_parser.ml` | partial | Bracketed paste framing is owned by the parser. |
| `lib/clock.ts` | `opentui-core/src/platform/eio_runtime` | adapter | Eio monotonic time supplies runtime deadlines. |
| `lib/terminal-*`, `ansi.ts` | `opentui-core/src/lib/terminal_modes.ml` and terminal modules | partial | Pure mode descriptions are separated from Eio writes. |
| `platform/*` | `opentui-core/src/platform` | adapter | Eio flow and Unix terminal policy live here. |
| `post/*` | matching files under `opentui-core/src/post` | deferred | No post-processing contract yet. |
| `animation/*` | matching files under `opentui-core/src/animation` | deferred | No animation scheduler yet. |
| `plugins/*` | matching files under `opentui-core/src/plugins` | deferred | No plugin registry contract yet. |
| `audio*` | matching files under `opentui-core/src/audio*` | not applicable | Outside the current terminal UI target. |
| `image.ts` | `opentui-core/src/image.ml` | deferred | Requires a native/image ownership decision. |
| `text-buffer.ts`, `text-buffer-view.ts`, `edit-buffer.ts`, `editor-view.ts` | matching files under `opentui-core/src` | deferred | Editor and buffer semantics are intentionally not guessed. |
| `testing/*` | `test/` and `reference/` | adapter | Windtrap, Cram, and reference runners provide OCaml test infrastructure. |
| `benchmark/*` | `bench/` and `reference/` | adapter | OCaml benchmarks and comparative runners live outside the library. |

## Translation rules

These rules apply whenever an upstream path has a JavaScript relationship that
does not translate literally:

| TypeScript relationship | OCaml rule |
| --- | --- |
| Inheritance between renderables | Compose an abstract retained node with a typed renderable module. |
| `EventEmitter` base behavior | Use typed event values and explicit cleanup owned by the scene/runtime scope. |
| Mutable option/property bags | Use labelled constructors, typed setters, and explicit clear operations. |
| Ambient renderer lookup | Pass the renderer, scene, parent, or Eio capability explicitly. |
| Promise/timer scheduling | Use Eio fibers and clocks at the platform boundary. |
| React/Solid host reconciliation | Bind Lwd values to existing retained nodes; do not create a second mandatory tree. |

Every non-literal translation needs a map entry, an invariant, and a test
whose observable behavior can be compared with the reference where that is
meaningful.
