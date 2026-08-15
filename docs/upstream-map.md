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
| `packages/core` | `packages/opentui-core/src` | Active portable core; the source mirror records the explicit animation, audio, and plugin exclusions plus platform translations |
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
| `renderer.ts` (`CliRenderer`) | [`renderable-core` feature record](major-features/in-progress/renderable-core/feature.md); `packages/opentui-core/src/renderer.ml` | Active translated core owner; terminal setup/output is the Eio session boundary |
| `types.ts` (`RenderContext`) | `packages/opentui-core/src/render_context.ml`; internal `renderer_events.ml` is surfaced through `Render_context` and `Renderer` | Active translated owner-local capability view |
| `types.ts` (`TerminalCapabilities`) | `packages/opentui-core/src/terminal_capabilities.ml`; snapshot conversion remains in `renderer.ml` below the raw binding | Active slice |
| `yoga.ts` | `packages/opentui-core/src/yoga.ml`; native ownership remains in `opentui-raw` | Active slice |
| `buffer.ts` (`OptimizedBuffer`) | `packages/opentui-core/src/buffer.ml`, `owned_buffer.ml`; ABI binding in `packages/opentui-raw/buffer.ml` | Active translated ownership split; JS typed-array/pointer views are non-applicable |
| `NativeSpanFeed.ts` | `packages/opentui-core/src/native_span_feed.ml`; foreign allocation and span lifetime remain in `packages/opentui-raw/span_feed.ml` | Active slice / translated |
| `zig.ts`, `zig-structs.ts` | `packages/opentui-raw` | Translated native boundary |
| `utils.ts` | `packages/opentui-core/src/lib/utils.ml` | Active translated utility module; packed link attributes and tree visualization use typed OCaml values |
| `ansi.ts` | `packages/opentui-core/src/lib/ansi.ml` and terminal modules | Active translated ANSI constants and validated escape builders |
| `renderer-theme-mode.ts` | `packages/opentui-core/src/renderer_theme_mode.ml` | Active translated theme-query owner with injected clock/output seam |
| `types.ts` exports not represented by `Render_context` | The owning core module named by the corresponding source-map or feature-record row | Active or translated by the owning typed module |
| `index.ts` | `packages/opentui-core/src` Dune library boundary | Translated package boundary; no literal barrel module is introduced |
| `node-assets.ts`, `node-asset-target.ts` | No OCaml module | Translated/non-applicable Node native and parser-asset discovery; the Eio-native package has no Node asset manifest |
| `platform/assets.ts`, `platform/ffi.ts`, `platform/runtime.ts` | `packages/opentui-core/src/platform` and `packages/opentui-raw` | Translated Eio/Unix runtime and native boundary |
| `platform/runtime-assets.node.ts`, `platform/runtime-assets.bun.ts`, `platform/worker*.ts` | No OCaml module | Translated/non-applicable Node/Bun asset loaders and worker entry points |

### Input and library modules

| Reference path | Repository-relative OCaml path | Status |
| --- | --- | --- |
| `lib/KeyHandler.ts` (`KeyHandler`, `InternalKeyHandler`) | [keyboard-dispatch feature record](major-features/in-progress/keyboard-dispatch/feature.md); `packages/opentui-core/src/lib/key_handler.ml` | Active slice |
| `lib/index.ts` | `packages/opentui-core/src/lib` namespace | Translated package boundary; no literal barrel module is introduced |
| `lib/stdin-parser.ts` | `packages/opentui-core/src/lib/stdin_parser.ml` | Active translated parser owner; protocol context, Kitty metadata, paste ownership, lifecycle, and caller/Eio timeout seams are explicit |
| `lib/parse.keypress.ts` | `packages/opentui-core/src/lib/key_decoder.ml` and `kitty_keypress.ml` | Active translated key decoders, including Kitty event/lock/base-code metadata |
| `lib/parse.mouse.ts` | `packages/opentui-core/src/lib/mouse_decoder.ml` | Active translated stateful SGR/X10 decoder |
| `lib/paste.ts` | `packages/opentui-core/src/lib/paste.ml` | Active slice; decoding and ANSI stripping are separate from parser framing |
| Private `ByteQueue` in `lib/stdin-parser.ts` | `packages/opentui-core/src/lib/byte_queue.ml` | Active slice |
| `lib/queue.ts` | `packages/opentui-core/src/lib/queue.ml` | Active translated process queue with injected scheduling and structured error handoff |
| OCaml input handoff | `packages/opentui-core/src/lib/input_coordinator.ml` and `event_queue.ml` | Translated integration |
| `lib/border.ts` | `packages/opentui-core/src/lib/border.ml` | Active slice |
| `lib/styled-text.ts` | `packages/opentui-core/src/lib/styled_text.ml` | Active translated styled-chunk/value/template surface; unsupported JavaScript object coercions are represented by typed values |
| `lib/RGBA.ts` | `packages/opentui-core/src/lib/rgba.ml`; `packages/opentui-core/src/color.ml` remains the smaller raw-backed renderer-color bridge | Active slice |
| `lib/ascii.font.ts` | `packages/opentui-core/src/ascii_font_spec.ml`; generated definitions in `packages/opentui-core/src/lib/ascii_font_data.ml` | Active slice; cfonts measurement, positions, color tags, clipping, and rasterization are typed around `Owned_buffer` |
| `lib/bunfs.ts` | No OCaml module | Translated/non-applicable Bun embedded-file path handling; the Eio-native package has no Bun filesystem boundary |
| `lib/fonts/*.json` | Generated into `packages/opentui-core/src/lib/ascii_font_data.ml` | Translated support data; the JSON asset boundary is replaced by a checked-in typed OCaml data module |
| `lib/clipboard.ts`, `lib/host-clipboard.internal.ts`, `lib/host-clipboard.native.ts` | `packages/opentui-core/src/lib/clipboard.ml` | Active translated clipboard policy/OSC52 service with injected host/terminal backends |
| `lib/clock.ts` | `packages/opentui-core/src/lib/clock.ml`; Eio clock adapters under `packages/opentui-core/src/platform/eio_runtime` | Active translated one-shot clock/cancellation capability; Eio owns the system implementation |
| `lib/terminal-capability-detection.ts` | `packages/opentui-core/src/lib/terminal_capability_detection.ml` | Active slice; response recognition and bounded pixel-resolution parsing feed `Renderer.handle_input` |
| `lib/data-paths.ts`, `env.ts`, `validate-dir-name.ts` | `packages/opentui-core/src/lib/data_paths.ml`, `env.ml`, `validate_dir_name.ml` | Active translated owner-local path, environment, and validation services |
| `lib/debounce.ts` | `packages/opentui-core/src/lib/debounce.ml` | Active translated one-shot debounce over `Lib.Clock` |
| `lib/detect-links.ts` | `packages/opentui-core/src/detect_links.ml` | Active slice; syntax ranges and plain URLs are applied without losing existing chunk styles |
| `lib/extmarks.ts`, `extmarks-history.ts` | `packages/opentui-core/src/lib/extmarks.ml`, `extmarks_history.ml` | Active slice; pure offset/history foundation |
| `lib/hast-styled-text.ts` | `packages/opentui-core/src/hast_styled_text.ml` | Active typed HAST/styled-text conversion; no JavaScript HAST parser is included |
| `lib/keybinding.internal.ts` | `packages/opentui-core/src/lib/keybinding.ml` | Active translated typed aliases and first-match bindings; Kitty modifier metadata is carried by `Key_decoder` |
| `lib/objects-in-viewport.ts`, `render-geometry.ts` | `packages/opentui-core/src/lib/objects_in_viewport.ml`, `render_geometry.ml` | Active slice |
| `lib/output.capture.ts` | `packages/opentui-core/src/lib/output_capture.ml` | Active translated explicit capture sink; process-stream replacement remains an application boundary |
| `lib/parse.keypress-kitty.ts` | `packages/opentui-core/src/lib/kitty_keypress.ml` | Active translated Kitty protocol parser and flag sequences |
| `lib/renderable.validations.ts` | `packages/opentui-core/src/lib/renderable_validations.ml` | Active typed result parsers and option validation |
| `lib/scroll-acceleration.ts` | `packages/opentui-core/src/lib/scroll_acceleration.ml` | Active slice; linear and platform-aware acceleration policies |
| `lib/selection.ts` | `packages/opentui-core/src/lib/selection.ml` | Active slice; generic selection geometry and text grouping |
| `lib/singleton.ts` | Owner composition in `Renderer.t`, `Render_context.t`, `Data_paths.t`, `Env.t`, and injected services | Translated/non-applicable; no process-global singleton is introduced |
| `lib/terminal-palette.ts` | `packages/opentui-core/src/lib/terminal_palette.ml`; renderer feed/query helpers in `src/renderer.ml` | Active slice; transport-neutral session seam |
| `lib/tree-sitter-styled-text.ts`, `tree-sitter/*` | `packages/opentui-core/src/tree_sitter_styled_text.ml`; `packages/opentui-core/src/lib/tree_sitter_client.ml`, `tree_sitter_types.ml`, `tree_sitter_resolve_filetype.ml` | Active typed seam; parser registration/injection is synchronous and OCaml-owned, with no JS/WASM asset loader |
| `lib/yoga.options.ts` | `packages/opentui-core/src/lib/yoga_options.ml` and `yoga.ml` | Active typed option parsers; invalid runtime strings return structured errors rather than silently defaulting |

### Text and renderables

| Reference path | Repository-relative OCaml path | Status |
| --- | --- | --- |
| `text-buffer.ts` | `packages/opentui-core/src/text_buffer.ml` and `packages/opentui-raw/text_buffer.ml` | Active translated native text owner plus Core metadata/highlight ownership |
| `text-buffer-view.ts` | `packages/opentui-core/src/text_buffer_view.ml` and `packages/opentui-raw/text_buffer_view.ml` | Active translated native wrapping, viewport, line-info, selection, tab indicators, truncation, and measurement |
| `edit-buffer.ts` | `packages/opentui-core/src/edit_buffer.ml` | Active translated editing controller; the portable edit model owns text/cursor/history in Core, while `EditBufferRenderable` projects it into the raw-owned native text child |
| `editor-view.ts` | `packages/opentui-core/src/editor_view.ml` | Active translated visual view over `Edit_buffer`, including wrapping, viewport, selection, cursor, line info, and extmark ownership |
| `syntax-style.ts` | `packages/opentui-core/src/syntax_style.ml` | Active foundation; registration/resolution/cache surface |
| `renderables/Box.ts` | `packages/opentui-core/src/renderables/box.ml` | Active slice |
| `renderables/Text.ts` | `packages/opentui-core/src/renderables/text.ml` and `text_children.ml` | Active for styled content, native measurement, composition, lifecycle, and selection forwarding |
| `renderables/TextNode.ts` | `packages/opentui-core/src/renderables/text_node.ml` | Active slice |
| `renderables/TextBufferRenderable.ts` | `packages/opentui-core/src/renderables/text_buffer_renderable.ml` | Active slice; native measurement, line-info, word-wrap, viewport, selection, scrolling, and pointer selection are connected |
| `renderables/EditBufferRenderable.ts` | `packages/opentui-core/src/renderables/edit_buffer_renderable.ml` | Active slice; composed edit-buffer/editor-view state, cursor, editing, selection, input, and native text child |
| `renderables/FrameBuffer.ts` | `packages/opentui-core/src/renderables/frame_buffer.ml`; owned raw storage in `packages/opentui-core/src/owned_buffer.ml` and borrowed draw seams in `src/buffer.ml` | Active slice; explicit buffer ownership, resize, clipping/compositing, and lifecycle cleanup |
| `renderables/Input.ts`, `Textarea.ts` | `packages/opentui-core/src/renderables/input.ml`, `textarea.ml` | Active slice; constrained single-line input, placeholder/focus styling, editing, paste, submit, and change events |
| `renderables/ScrollBox.ts`, `ScrollBar.ts` | `packages/opentui-core/src/renderables/scroll_box.ml`, `scroll_bar.ml` | Active slice; composed viewport/content ownership, culling, scrolling, bars, sticky positioning, and acceleration |
| `renderables/Select.ts`, `TabSelect.ts` | `packages/opentui-core/src/renderables/select.ml`, `tab_select.ml` | Active slice; directional navigation, wrapping, descriptions, indicators, tabs, and typed selection events |
| `renderables/Slider.ts` | `packages/opentui-core/src/renderables/slider.ml` | Active slice; virtual track/thumb rendering, clamped value state, keyboard/pointer input, focusability, and change events |
| `renderables/Code.ts` | `packages/opentui-core/src/renderables/code.ml` | Active translated slice; injectable synchronous parser, generation ordering, styled chunks, conceal/source-line mapping, selection, and fallback |
| `renderables/Diff.ts` | `packages/opentui-core/src/renderables/diff.ml`, `diff_parser.ml` | Active translated slice; unified/split layout, validated hunk parsing, line-number composition, selection, error view, and split scroll synchronization |
| `renderables/Markdown.ts`, `renderables/markdown-parser.ts` | `packages/opentui-core/src/renderables/markdown.ml`, `markdown_parser.ml` | Active translated slice; typed block/inline parser, stable-prefix updates, styled links, code blocks, tables, borders, selection aggregation, and explicit parser injection |
| `renderables/TextTable.ts` | `packages/opentui-core/src/renderables/text_table.ml` | Active slice; measured/wrapped grid layout, borders, native cell views, updates, and pointer selection/copy |
| `renderables/Image.ts` | `packages/opentui-core/src/renderables/image.ml`, `packages/opentui-core/src/owned_buffer.ml` | Active slice; capability-driven Kitty/Sixel/Blocks selection, cell-aware fit/cover/fill sizing, clipping/fallback, optional retained off-screen buffering, source replacement, and lifecycle |
| `renderables/ASCIIFont.ts` | `packages/opentui-core/src/renderables/ascii_font.ml` | Active slice; retained framebuffer rasterizer and selectable text |
| `renderables/LineNumberRenderable.ts` | `packages/opentui-core/src/renderables/line_number.ml` | Active slice; visual line sources, gutter measurement, colors, signs, offsets, hiding, and target composition |
| `renderables/TimeToFirstDraw.ts` | `packages/opentui-core/src/renderables/time_to_first_draw.ml` | Active slice; first-draw monotonic timing, formatting, clipping, and reset |
| `renderables/markdown-parser.ts` | `packages/opentui-core/src/renderables/markdown_parser.ml` | Active helper; hand-written typed Markdown subset covers the rendered block/inline contracts, with unsupported CommonMark extensions intentionally absent |
| `renderables/text-table-width.ts` | `packages/opentui-core/src/text_table_width.ml` | Active slice; deterministic square-root water-fill allocation with typed integer inputs |
| `renderables/composition/*` | `packages/opentui-core/src/renderables/composition/{vnode,v_renderable,constructs}.ml` | Translated composition descriptions and constructors; instantiation mounts ordinary retained identities, with no dynamic proxy identity |
| `renderables/index.ts` | `packages/opentui-core/src/renderables` namespace | Translated package boundary; qualified Dune modules replace the barrel export |

### Independent core subsystems

| Reference path | Repository-relative OCaml path | Status |
| --- | --- | --- |
| `post/matrices.ts` | `packages/opentui-core/src/post/matrices.ml` | Active translated slice; reference RGBA matrices are typed `floatarray` values |
| `post/filters.ts` | `packages/opentui-core/src/post/filters.ml` | Active translated slice; color-matrix, snapshot-backed, and deterministic filter operations return structured errors |
| `post/effects.ts` | `packages/opentui-core/src/post/effects.ml` | Active translated slice; stateful effects retain configuration and clocks but never retain renderer buffers; procedural noise is deterministic and owner-local |
| `animation/*` | [animation feature record](major-features/in-progress/animation/feature.md); no OCaml module yet | Deferred; design in progress |
| `plugins/*` | [plugins feature record](major-features/in-progress/plugins/feature.md); no OCaml module yet | Deferred; design in progress |
| `runtime-plugin.ts`, `runtime-plugin-support*.ts` | No OCaml module | Deferred Bun-specific runtime module loading; separate platform design if required |
| `audio.ts`, `audio-stream/*` | [audio-stream feature record](major-features/in-progress/audio-stream/feature.md); no OCaml module yet | Deferred; design in progress |
| `image.ts` | `packages/opentui-core/src/image.ml`; typed native seam in `packages/opentui-raw/image.ml` and `image_stubs.c` | Active translated slice; Eio path/encoded/RGBA sources, vendored decoder metadata, proportional/explicit resizing, copy-transfer raw pixels, transforms, compositing, and structured errors |
| `console.ts` | `packages/opentui-core/src/console.ml`; renderer integration in `packages/opentui-core/src/renderer.ml` | Active translated slice; owner-local log buffering, wrapping, scrolling, pointer selection/copy, layout, overlay rendering, resize, and lifecycle without process-global console replacement |
| `platform/*` | `packages/opentui-core/src/platform` | Translated Eio/Unix platform boundary; Node/Bun workers/assets are non-applicable mechanisms |
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
