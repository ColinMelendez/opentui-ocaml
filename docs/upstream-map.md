# OpenTUI source correspondence map

This file maps the reference OpenTUI source in `vendor/opentui` to locations in
this repository. In this document, “reference package” means a directory under
`vendor/opentui/packages`, and “reference path” means a file or directory under
one of those packages.

Use this map when a contributor finds a feature in the reference source. A
destination may be a file, directory, package, or `deferred` when no OCaml
destination is selected. Cross-cutting rows identify the reference paths that
share one feature contract and point to that contract as well as its owning
modules. The contributor workflow is in
[`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Reference packages

| Reference package or path | Repository-relative OCaml location |
| --- | --- |
| `packages/core` | `packages/opentui-core/src` |
| `packages/core/src/zig` | `packages/opentui-raw` |
| `packages/core/src/buffer.ts`, `NativeSpanFeed.ts` | `packages/opentui-raw` for ABI bindings and the [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md) for core-facing ports |
| `packages/keymap` | `deferred` |
| `packages/react` | `deferred` |
| `packages/solid` | `deferred` |
| `packages/examples` | `packages/opentui-core/examples` |
| `packages/qrcode` | `deferred` |
| `packages/ssh` | `deferred` |
| `packages/three` | no OCaml package |
| `packages/web` | no OCaml package |

## `packages/core/src`

| Reference path | Repository-relative OCaml path |
| --- | --- |
| `Renderable.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/renderable.ml` and `layout_children.ml` |
| `renderer.ts` (`CliRenderer`) | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/renderer.ml` |
| `types.ts` (`RenderContext`) | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/render_context.ml` |
| `yoga.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/yoga.ml` with private per-renderable ownership |
| Cross-cutting event model in `Renderable.ts`, `renderer.ts`, `types.ts`, and `lib/KeyHandler.ts` | `docs/major-features/in-progress/event-system/feature.md` plus the owning `opentui-core` modules |
| `Renderable.ts` mouse handlers and pointer dispatch in `renderer.ts` | `docs/major-features/in-progress/pointer-dispatch/feature.md`; `packages/opentui-core/src/renderable.ml` and `renderer.ml` |
| `buffer.ts` (`OptimizedBuffer`) | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/buffer.ml`; ABI binding: `packages/opentui-raw/buffer.ml` |
| `NativeSpanFeed.ts` | `packages/opentui-raw/span_feed.ml` |
| `renderables/Box.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md) and `packages/opentui-core/src/renderables/box.ml` |
| `lib/border.ts` | `packages/opentui-core/src/lib/border.ml` |
| `renderables/Text.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md) and `packages/opentui-core/src/renderables/text.ml` with `text_children.ml` |
| `renderables/TextNode.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/renderables/text_node.ml` |
| `renderables/TextBufferRenderable.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/renderables/text_buffer_renderable.ml` |
| `renderables/EditBufferRenderable.ts` | `deferred` |
| `renderables/FrameBuffer.ts` | `deferred` |
| `renderables/Input.ts` | `deferred` |
| `renderables/Textarea.ts` | `deferred` |
| `renderables/Select.ts` | `deferred` |
| `renderables/ScrollBox.ts` | `deferred` |
| `renderables/Slider.ts` | `deferred` |
| `renderables/TabSelect.ts` | `deferred` |
| `renderables/ScrollBar.ts` | `deferred` |
| `renderables/Code.ts`, `Diff.ts`, `Markdown.ts`, `TextTable.ts` | `deferred` |
| `renderables/Image.ts`, `ASCIIFont.ts` | `deferred` |
| `renderables/composition/*` | `deferred` |
| `lib/stdin-parser.ts` (framing and typed event production) | `packages/opentui-core/src/lib/stdin_parser.ml` |
| `lib/parse.keypress.ts` (parser helper) | `packages/opentui-core/src/lib/key_decoder.ml` |
| `lib/parse.mouse.ts` (parser helper) | `packages/opentui-core/src/lib/mouse_decoder.ml` |
| `lib/queue.ts` | `deferred` |
| private `ByteQueue` in `lib/stdin-parser.ts` | `packages/opentui-core/src/lib/byte_queue.ml` |
| OCaml input handoff | `packages/opentui-core/src/lib/input_coordinator.ml` and `event_queue.ml` |
| `lib/KeyHandler.ts` (`KeyHandler`, `InternalKeyHandler`) | `docs/major-features/in-progress/keyboard-dispatch/feature.md`; `packages/opentui-core/src/lib/key_handler.ml` |
| `lib/paste.ts` | `packages/opentui-core/src/lib/stdin_parser.ml` |
| `lib/clock.ts` | `packages/opentui-core/src/platform/eio_runtime` |
| `lib/terminal-*`, `ansi.ts` | `packages/opentui-core/src/lib/terminal_modes.ml` and terminal modules |
| `platform/*` | `packages/opentui-core/src/platform` |
| `post/*` | `deferred` |
| `animation/*` | `deferred` |
| `plugins/*` | `deferred` |
| `audio*` | `deferred` |
| `image.ts` | `deferred` |
| `text-buffer.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/text_buffer.ml` |
| `text-buffer-view.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/text_buffer_view.ml` |
| `lib/styled-text.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/lib/styled_text.ml` |
| `syntax-style.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); target `packages/opentui-core/src/syntax_style.ml` |
| `edit-buffer.ts`, `editor-view.ts` | `deferred` |
| `testing/*`, `tests/*` | `packages/opentui-core/test` |
| `benchmark/*` | `packages/opentui-core/bench` |
| core parser comparison harness | `packages/opentui-core/reference` |

The raw package's ABI and link tests live in `packages/opentui-raw/test` because
they validate the separate C/Zig boundary. Repository-wide architecture,
source-mapping, planning, and performance-policy documents remain under the
repository root because they describe more than one package.
