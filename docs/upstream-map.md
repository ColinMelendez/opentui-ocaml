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

| Reference package or path | Repository-relative OCaml location | Status |
| --- | --- | --- |
| `packages/core` | `packages/opentui-core/src` | Partial; see the [core source mirror](major-features/in-progress/core-source-mirror/feature.md) |
| `packages/core/src/zig` | `packages/opentui-raw` | Translated native boundary |
| `packages/keymap` | `deferred` | Separate package design follows core host-seam work |
| `packages/react` | `deferred` | No React runtime exists in the OCaml port |
| `packages/solid` | `deferred` | No Solid runtime exists in the OCaml port |
| `packages/examples` | `packages/opentui-core/examples` | Support layout |
| `packages/qrcode` | `deferred` | Separate feature |
| `packages/ssh` | `deferred` | Separate feature |
| `packages/three` | no OCaml package | No corresponding OCaml runtime boundary |
| `packages/web` | no OCaml package | No corresponding OCaml runtime boundary |

## `packages/core/src`

The tables below cover runtime source paths. Generated snapshots, native
vendor trees, and test fixtures use the support-layout rows at the end.

### Core ownership and native boundary

| Reference path | Repository-relative OCaml path | Status |
| --- | --- | --- |
| `Renderable.ts` | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); `packages/opentui-core/src/renderable.ml` and `layout_children.ml` | Active slice |
| `renderer.ts` (`CliRenderer`) | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); `packages/opentui-core/src/renderer.ml` | Partial |
| `types.ts` (`RenderContext`) | `packages/opentui-core/src/render_context.ml`; internal `renderer_events.ml` is surfaced through `Render_context` and `Renderer` | Partial |
| `yoga.ts` | `packages/opentui-core/src/yoga.ml`; native ownership remains in `opentui-raw` | Active slice |
| `buffer.ts` (`OptimizedBuffer`) | `packages/opentui-core/src/buffer.ml`; ABI binding in `packages/opentui-raw/buffer.ml` | Partial / translated |
| `NativeSpanFeed.ts` | `packages/opentui-raw/span_feed.ml`; core-facing integration remains part of the renderable boundary | Partial / translated |
| `zig.ts`, `zig-structs.ts` | `packages/opentui-raw` | Translated native boundary |
| `utils.ts` | No OCaml module | Deferred; its reference utilities have no core owner |
| `ansi.ts` | `packages/opentui-core/src/lib/terminal_modes.ml` and terminal modules | Partial / translated |
| `renderer-theme-mode.ts` | No OCaml module | Deferred |
| `types.ts` exports not represented by `Render_context` | The owning core module named by the corresponding source-map or feature-record row | Partial |
| `index.ts` | `packages/opentui-core/src` Dune library boundary | Translated package boundary; no literal barrel module is introduced |
| `node-assets.ts`, `node-asset-target.ts` | No OCaml module | Deferred Node native and parser-asset discovery; the Eio-native package has no Node asset manifest |

### Input and library modules

| Reference path | Repository-relative OCaml path | Status |
| --- | --- | --- |
| `lib/KeyHandler.ts` (`KeyHandler`, `InternalKeyHandler`) | [keyboard-dispatch feature record](major-features/in-progress/keyboard-dispatch/feature.md); `packages/opentui-core/src/lib/key_handler.ml` | Active slice |
| `lib/index.ts` | `packages/opentui-core/src/lib` namespace | Translated package boundary; no literal barrel module is introduced |
| `lib/stdin-parser.ts` | `packages/opentui-core/src/lib/stdin_parser.ml` | Partial |
| `lib/parse.keypress.ts` | `packages/opentui-core/src/lib/key_decoder.ml` | Partial |
| `lib/parse.mouse.ts` | `packages/opentui-core/src/lib/mouse_decoder.ml` | Partial |
| `lib/paste.ts` | `packages/opentui-core/src/lib/stdin_parser.ml` | Translated into parser ownership |
| Private `ByteQueue` in `lib/stdin-parser.ts` | `packages/opentui-core/src/lib/byte_queue.ml` | Active slice |
| `lib/queue.ts` | No OCaml module | Deferred; it is distinct from the parser byte queue and event handoff |
| OCaml input handoff | `packages/opentui-core/src/lib/input_coordinator.ml` and `event_queue.ml` | Translated integration |
| `lib/border.ts` | `packages/opentui-core/src/lib/border.ml` | Active slice |
| `lib/styled-text.ts` | `packages/opentui-core/src/lib/styled_text.ml` | Partial |
| `lib/RGBA.ts` | No equivalent; `packages/opentui-core/src/color.ml` is a smaller raw-backed color wrapper | Deferred |
| `lib/ascii.font.ts` | No OCaml module | Deferred |
| `lib/bunfs.ts` | No OCaml module | Deferred Bun embedded-file path handling; the Eio-native package has no Bun filesystem boundary |
| `lib/fonts/*.json` | No OCaml module | Deferred support data for the ASCII-font feature |
| `lib/clipboard.ts`, `lib/host-clipboard.internal.ts`, `lib/host-clipboard.native.ts` | No OCaml module | Deferred; clipboard policy and host backends remain outside the current OCaml scope |
| `lib/clock.ts` | Eio `Clock` capability supplied at `packages/opentui-core/src/platform/eio_runtime` | Translated Eio clock boundary; no standalone clock module mirrors the Bun/Node helper |
| `lib/data-paths.ts`, `env.ts`, `validate-dir-name.ts` | No OCaml module | Deferred |
| `lib/debounce.ts` | No OCaml module | Deferred |
| `lib/detect-links.ts` | No OCaml module | Deferred |
| `lib/extmarks.ts`, `extmarks-history.ts` | No OCaml module | Deferred with editor state |
| `lib/hast-styled-text.ts` | No OCaml module | Deferred with markup integration |
| `lib/keybinding.internal.ts` | No OCaml module | Deferred with keymap and editor integration |
| `lib/objects-in-viewport.ts`, `render-geometry.ts` | No OCaml module | Deferred with renderer geometry |
| `lib/output.capture.ts` | No OCaml module | Deferred |
| `lib/parse.keypress-kitty.ts` | No OCaml module | Deferred parser protocol extension |
| `lib/renderable.validations.ts` | No OCaml module | Deferred; validation belongs with the relevant typed module |
| `lib/scroll-acceleration.ts` | No OCaml module | Deferred |
| `lib/selection.ts` | No OCaml module | Deferred renderer selection feature |
| `lib/singleton.ts` | No OCaml module | Deferred; no global singleton boundary is introduced |
| `lib/terminal-capability-detection.ts` | No OCaml module | Deferred terminal capability feature |
| `lib/terminal-palette.ts` | No OCaml module | Deferred |
| `lib/tree-sitter-styled-text.ts`, `tree-sitter/*` | No OCaml module | Deferred parser and syntax integration |
| `lib/yoga.options.ts` | `packages/opentui-core/src/yoga.ml` style operations | Partial translation |

### Text and renderables

| Reference path | Repository-relative OCaml path | Status |
| --- | --- | --- |
| `text-buffer.ts` | `packages/opentui-core/src/text_buffer.ml` | Partial |
| `text-buffer-view.ts` | `packages/opentui-core/src/text_buffer_view.ml` | Partial |
| `edit-buffer.ts` | No OCaml module | Deferred |
| `editor-view.ts` | No OCaml module | Deferred |
| `syntax-style.ts` | No OCaml module | Deferred; the previous renderable-core target is not an implementation claim |
| `renderables/Box.ts` | `packages/opentui-core/src/renderables/box.ml` | Active slice |
| `renderables/Text.ts` | `packages/opentui-core/src/renderables/text.ml` and `text_children.ml` | Partial |
| `renderables/TextNode.ts` | `packages/opentui-core/src/renderables/text_node.ml` | Active slice |
| `renderables/TextBufferRenderable.ts` | `packages/opentui-core/src/renderables/text_buffer_renderable.ml` | Partial |
| `renderables/EditBufferRenderable.ts` | No OCaml module | Deferred |
| `renderables/FrameBuffer.ts` | No OCaml module | Deferred |
| `renderables/Input.ts`, `Textarea.ts` | No OCaml module | Deferred |
| `renderables/ScrollBox.ts`, `ScrollBar.ts` | No OCaml module | Deferred |
| `renderables/Select.ts`, `Slider.ts`, `TabSelect.ts` | No OCaml module | Deferred |
| `renderables/Code.ts`, `Diff.ts`, `Markdown.ts`, `TextTable.ts` | No OCaml module | Deferred |
| `renderables/Image.ts`, `ASCIIFont.ts` | No OCaml module | Deferred |
| `renderables/LineNumberRenderable.ts`, `TimeToFirstDraw.ts` | No OCaml module | Deferred |
| `renderables/markdown-parser.ts`, `text-table-width.ts` | No OCaml module | Deferred helpers for Markdown and TextTable |
| `renderables/composition/*` | No OCaml module | Deferred; no alternate composition framework is introduced |
| `renderables/index.ts` | `packages/opentui-core/src/renderables` namespace | Partial export correspondence |

### Independent core subsystems

| Reference path | Repository-relative OCaml path | Status |
| --- | --- | --- |
| `post/*` | No OCaml module | Deferred |
| `animation/*` | No OCaml module | Deferred |
| `plugins/*`, `runtime-plugin.ts`, `runtime-plugin-support*.ts` | No OCaml module | Deferred |
| `audio.ts`, `audio-stream/*` | No OCaml module | Deferred |
| `image.ts` | No OCaml module | Deferred |
| `console.ts` | No OCaml module | Deferred |
| `platform/*` | `packages/opentui-core/src/platform` | Translated Eio/Unix platform boundary |
| `specs/*` | Repository documentation and feature records | Support layout |

### Tests, examples, benchmarks, and generated material

| Reference path | Repository-relative OCaml path | Status |
| --- | --- | --- |
| `testing.ts`, `testing/*`, `tests/*`, root `*.test.ts` files | `packages/opentui-core/test` | Support layout; test names and source-map rows retain the reference area |
| `benchmark/*` | `packages/opentui-core/bench` | Support layout |
| `__snapshots__/*`, test fixtures, generated assets | Package-local test/reference fixtures as needed | Support material, not runtime correspondence |
| Core parser comparison harness | `packages/opentui-core/reference` | Support layout |

The raw package's ABI and link tests live in `packages/opentui-raw/test` because
they validate the separate C/Zig boundary. Repository-wide architecture,
source-mapping, planning, and performance-policy documents remain under the
repository root because they describe more than one package.
