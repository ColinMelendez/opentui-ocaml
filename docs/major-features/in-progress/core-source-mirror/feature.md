# Core source mirror

## Purpose

`opentui-core` is the OCaml port of `vendor/opentui/packages/core`. The source
tree is the contributor-facing index for that port. A contributor who starts
with a reference path can use the same package and directory names to locate
the OCaml correspondence, then use this record and the source map to identify
translation boundaries and coverage.

The reference core contains more than the renderer and renderables. It also
contains terminal utilities, text editing state, selection, syntax styling,
post-processing, media support, testing helpers, and native span and buffer
integration. The portable renderer, terminal, editor, buffer, utility,
renderable, image, console, and post-processing paths are implemented here.
Animation, audio/audio-stream, and plugins/runtime-plugin remain explicit
exclusions; JavaScript/Bun/Node/WASM loader mechanisms are translated as
non-applicable platform boundaries rather than represented by fake APIs.

## Status vocabulary

The source map uses these statuses:

- **Active slice** means that an OCaml module exists and its accepted boundary
  is defined by an in-progress or implemented feature record.
- **Partial** is reserved for a future audit note; no ordinary portable Core
  row should use it once its accepted boundary has been implemented.
- **Translated** means that the reference concept lives at a deliberate OCaml
  effect or native boundary, such as `opentui-raw` or the Eio platform tree.
- **Deferred** means that no public OCaml module exists for the reference area.
  Deferred areas have no placeholder API.
- **Support layout** means that tests, examples, benchmarks, or specifications
  use the repository's package-local Dune layout while retaining a direct link
  to the reference path.

These statuses describe correspondence. They do not describe release
readiness or the quality of an individual module.

## Directory contract

Reference source directories have the following OCaml locations:

| Reference directory | OCaml location | Translation rule |
| --- | --- | --- |
| `core/src/lib` | `opentui-core/src/lib` | Preserve the directory. Convert reference filenames to lowercase snake case when the OCaml filename differs. |
| `core/src/renderables` | `opentui-core/src/renderables` | Preserve the directory and one module per concrete renderable. |
| `core/src/platform` | `opentui-core/src/platform` | Preserve the directory. Eio and Unix runtime modules occupy explicit subdirectories because they own different effects. |
| `core/src/post` | `opentui-core/src/post` | Post-processing modules use this directory. |
| `core/src/animation` | `opentui-core/src/animation` | Timeline modules use this directory. |
| `core/src/plugins` | `opentui-core/src/plugins` | Plugin registration modules use this directory. |
| `core/src/testing` | `opentui-core/test` and package-local testing helpers | Use the Dune test boundary and retain the reference path in the map. |
| `core/src/benchmark` | `opentui-core/bench` | Keep benchmark programs beside the package they measure. |
| `core/src/zig` | `opentui-raw` | Keep native handles, ABI calls, and foreign lifetimes below `opentui-core`. |

Reference PascalCase, hyphenated, and dotted filenames use lowercase
underscore-separated OCaml filenames when the correspondence is direct. A
different OCaml module name is justified when the existing module represents a
different semantic boundary rather than a spelling difference.

The following names are not interchangeable:

| Reference name | Existing OCaml name | Reason the name remains distinct |
| --- | --- | --- |
| `lib/RGBA.ts` | `Lib.Rgba` and `Color` | `Lib.Rgba` owns color intent, indexed/default colors, parsing, normalization, and conversion; `Color` remains the smaller raw-backed renderer-color bridge. |
| `lib/parse.keypress.ts` | `Lib.Key_decoder` and `Lib.Kitty_keypress` | The modules separate ordinary terminal decoding from the Kitty protocol metadata boundary, including event type, base-code, lock, and keypad metadata. |
| `lib/parse.mouse.ts` | `Lib.Mouse_decoder` | The module owns stateful terminal mouse classification and keeps that state separate from byte framing. |
| `core/src/zig` | `opentui-raw` | The package split protects the native ABI and prevents raw handles from entering the core API. |
| reference renderer events | Internal `renderer_events.ml`, surfaced through `Render_context` and `Renderer` | The typed owner-local event vocabulary is an OCaml composition mechanism, not a new reference feature or public module. |
| reference base child methods | `Layout_children` and `Text_children` | Typed child capabilities replace inheritance-based dynamic child dispatch. |

The naming rule prevents a cosmetic rename from claiming a semantic port. A
module moves to the reference-derived name when its public contract matches the
reference concept closely enough for the name to be truthful.

## Core correspondence

| Reference path | OCaml path | Status | Boundary |
| --- | --- | --- | --- |
| `Renderable.ts` | `src/renderable.ml`, `src/layout_children.ml` | Active slice | Heterogeneous retained nodes, typed child capabilities, layout state, lifecycle, focus, keyboard slots, and pointer routing. |
| `renderer.ts` | `src/renderer.ml`; [`scheduler` feature record](../scheduler/feature.md) | Active translated owner | Renderer ownership, explicit frames, borrowed buffers, retained-tree rendering, scoped native opacity/scissor execution, hit-grid routing, focus, input dispatch, capability/palette response processing, renderer geometry, forced repaint invalidation, post-process callbacks, console ownership, and terminal-session hooks exist. Terminal setup/output is supplied by the Eio/Unix session boundary; the renderer-owned Eio scheduler is designed but not implemented. |
| `types.ts` (`RenderContext`) | `src/render_context.ml`, with internal `src/renderer_events.ml` | Active translated capability owner | Renderer-owned dimensions, copied terminal capabilities, typed owner-local event sources, lifecycle, focus, input, and render-request state are composed through the context. |
| `types.ts` (`TerminalCapabilities`) | `src/terminal_capabilities.ml`, populated by `src/renderer.ml` from `opentui-raw` | Active slice | Immutable typed snapshots, copied terminal strings, and renderer/context sharing are implemented. |
| `yoga.ts` | `src/yoga.ml` | Active slice | Independent node ownership, non-destructive detach, explicit free, style operations, and layout readback exist. |
| `buffer.ts` | `src/buffer.ml`, `src/owned_buffer.ml`, `opentui-raw/buffer.ml` | Active translated ownership split | `Buffer.t` is a borrowed renderer surface and `Owned_buffer.t` owns standalone storage. The reference JS typed-array/pointer views are non-applicable mechanisms below the typed raw boundary. |
| `text-buffer.ts` | `src/text_buffer.ml`, `opentui-raw/text_buffer.ml` | Active translated native owner | Native text storage plus Core metadata for styled text, defaults, syntax style, tab width, highlights, and text queries are exposed; the C/Zig allocation remains raw-owned. |
| `text-buffer-view.ts` | `src/text_buffer_view.ml` and `opentui-raw/text_buffer_view.ml` | Active translated native view | View ownership, native char/word wrapping, viewport, line-info, selection/local-selection, selected text, tab indicators, truncation, and measurement are connected through checked int32 boundaries. |
| `NativeSpanFeed.ts` | `src/native_span_feed.ml` and `opentui-raw/span_feed.ml` | Active slice / translated | Core exposes typed options, spans, reservations, stats, draining, and ownership; raw keeps the foreign feed lifetime and ABI token ownership. |
| `zig.ts`, `zig-structs.ts` | `opentui-raw` | Translated native boundary | Native loading, ABI records, and foreign callbacks live below the core package. |
| `index.ts` | `opentui-core/src` Dune library boundary | Translated package boundary | Dune's wrapped library and package modules provide the public export boundary; no literal barrel module is introduced. |
| `lib/index.ts` | `opentui-core/src/lib` qualified namespace | Translated package boundary | The qualified source directory provides the library namespace. |
| `renderables/index.ts` | `opentui-core/src/renderables` qualified namespace | Translated package boundary | The qualified source directory provides the renderables namespace. |
| `lib/KeyHandler.ts` | `src/lib/key_handler.ml` | Active slice | Global/local keyboard dispatch, prevention, propagation, cleanup, handler errors, and the decoded Kitty event metadata used by handlers exist. |
| `lib/stdin-parser.ts` | `src/lib/stdin_parser.ml` | Active translated parser owner | Framing, protocol context, Kitty selection, Kitty metadata, paste ownership, mouse events, key events, responses, bounded prefixes, lifecycle, and caller- or clock-owned timeouts exist. |
| `lib/parse.keypress.ts` | `src/lib/key_decoder.ml`, `src/lib/kitty_keypress.ml` | Active translated decoders | Common terminal forms and Kitty Unicode/special forms decode into typed OCaml values with source/event/lock/base-code metadata. |
| `lib/parse.mouse.ts` | `src/lib/mouse_decoder.ml` | Active translated decoder | SGR/X10 decoding, modifiers, scrolling, drag classification, and resettable pressed-button state exist; event dispatch remains owned by the renderer. |
| `lib/border.ts` | `src/lib/border.ml` | Active slice | Border geometry and native drawing translation exist. |
| `lib/styled-text.ts` | `src/lib/styled_text.ml` | Active translated value layer | Styled chunks, style attributes, links, hidden/reverse/common style helpers, typed interpolation values, and template rendering are exposed without JavaScript object coercion. |
| `lib/clock.ts` | `src/lib/clock.ml`; Eio adapters under `src/platform/eio_runtime` | Active translated clock layer | One-shot scheduling and cancellation are injected into Core; Eio supplies the system clock and the manual clock supports deterministic tests. |
| `lib/terminal-capability-detection.ts` | `src/lib/terminal_capability_detection.ml` | Active slice | Upstream response families are recognized synchronously; pixel-resolution parsing is bounded to Core's signed 32-bit geometry. |
| `lib/paste.ts` | `src/lib/paste.ml` | Active slice | Paste decoding and ANSI stripping are reusable control utilities; framing and payload ownership remain in the parser boundary. |
| `lib/keybinding.internal.ts` | `src/lib/keybinding.ml` | Active translated binding layer | Typed aliases and first-match bindings support the core controls; Kitty modifier metadata is carried by the parser/key decoder boundary. |
| `lib/scroll-acceleration.ts` | `src/lib/scroll_acceleration.ml` | Active slice | Linear and platform-aware policies preserve the reference reset, history, and sub-cell accumulation inputs. |
| `platform/*` | `src/platform/*` | Translated | Eio runtime and Unix terminal-session modules replace the reference Bun/Node runtime adapters. |
| `renderables/Box.ts` | `src/renderables/box.ml` | Active slice | Box construction, style mutation, child capability, layout, and drawing exist. |
| `renderables/Text.ts` | `src/renderables/text.ml` | Active slice | Text composition, styled content, native measurement, lifecycle integration, and selection forwarding are present; style values use the typed `Styled_text` vocabulary. |
| `renderables/TextNode.ts` | `src/renderables/text_node.ml` | Active slice | Text-node ownership and style state exist. |
| `renderables/TextBufferRenderable.ts` | `src/renderables/text_buffer_renderable.ml` | Active slice | Native measurement ownership, line-info, char/word wrapping, viewport, selection, scrolling, pointer selection, and text-buffer rendering integration are present. |
| `lib/extmarks.ts`, `extmarks-history.ts` | `src/lib/extmarks.ml`, `src/lib/extmarks_history.ml` | Active foundation | Offset adjustment, virtual marks, metadata, snapshots, undo, and redo are implemented as a pure Core controller. |
| `lib/objects-in-viewport.ts` | `src/lib/objects_in_viewport.ml` | Active slice | Viewport culling, binary-search helpers, and z-order sorting are implemented generically. |
| `lib/render-geometry.ts` | `src/lib/render_geometry.ml` | Active slice | Screen mode, footer, and clamped render dimensions are represented independently of terminal I/O. |
| `lib/selection.ts` | `src/lib/selection.ml` | Active foundation | Generic anchors, bounds, selectable objects, local/global conversion, and selected-text grouping are implemented without a Renderable dependency cycle. |
| `lib/terminal-palette.ts` | `src/lib/terminal_palette.ml`, `src/renderer.ml` | Active foundation | OSC palette parsing, normalization, query strings, tmux wrapping, renderer state, and typed palette events exist; session scheduling/output remains outside Core. |
| `lib/RGBA.ts` | `src/lib/rgba.ml` | Active foundation | RGB/indexed/default intent, parsing, conversion, and ANSI256 normalization exist. |
| `edit-buffer.ts` | `src/edit_buffer.ml` | Active translated controller | Text editing, cursor movement, history, highlights, syntax-style ownership, change callbacks, and extmark adjustment exist in a pure Core module; `EditBufferRenderable` projects that state into its raw-owned native text child. |
| `editor-view.ts` | `src/editor_view.ml` | Active translated view | Wrapping, visual-line calculations, viewport, selection conversion, cursor movement, line information, and the shared edit-buffer extmark owner exist. |
| `syntax-style.ts` | `src/syntax_style.ml` | Active foundation | Style registration, theme resolution, merging, base-name lookup, caching, and destruction exist. |
| `renderables/EditBufferRenderable.ts` | `src/renderables/edit_buffer_renderable.ml` | Active slice | Edit-buffer/editor-view composition, cursor and viewport synchronization, keyboard editing, selection, paste, pointer selection, and native text rendering exist. |
| `renderables/Input.ts` | `src/renderables/input.ml` | Active slice | Single-line constraints, focus/blur change semantics, paste sanitization, submit validation, and input/change/enter events exist. |
| `renderables/Textarea.ts` | `src/renderables/textarea.ml` | Active slice | Multi-line editing wrapper, placeholder/focus styling, submit event, selection, undo/redo, and viewport/line-info forwarding exist. |
| `renderables/ScrollBox.ts` | `src/renderables/scroll_box.ml` | Active slice | Composed root/wrapper/viewport/content ownership, culling, sticky positions, scroll accumulation, child scrolling, and scrollbar ownership exist. |
| `renderables/ScrollBar.ts` | `src/renderables/scroll_bar.ml` | Active slice | Slider-backed scroll range, visibility, arrows, scroll units, keyboard input, and change events exist. Arrow repeat is an application-owned clock/update policy, not hidden renderable state. |
| `renderables/Select.ts` | `src/renderables/select.ml` | Active slice | Vertical option navigation, fast movement, descriptions, selection indicators, scrolling, wrapping, typed events, and the optional ASCII-font composition path exist. |
| `renderables/TabSelect.ts` | `src/renderables/tab_select.ml` | Active slice | Horizontal tab navigation, dynamic rows, underline/description/arrows, wrapping, pointer translation, and typed events exist. |
| `renderables/Slider.ts` | `src/renderables/slider.ml` | Active slice | Virtual track/thumb rendering, value clamping, keyboard/pointer input, focusability, and change events exist; ScrollBar composes it for range scrolling. |
| `renderables/FrameBuffer.ts` | `src/renderables/frame_buffer.ml`, `src/owned_buffer.ml`, and borrowed draw additions in `src/buffer.ml` | Active slice | Explicit off-screen buffer ownership, resize, alpha-aware compositing, clipping through the native draw path, and destruction are connected. |
| `lib/ascii.font.ts`, `lib/fonts/*.json` | `src/ascii_font_spec.ml`, generated `src/lib/ascii_font_data.ml` | Active slice / translated data | Measurement, character positions, color-tag parsing, clipped rasterization, and selectable ASCII-font rendering are typed around Unicode code points; the reference JavaScript UTF-16 indexing is intentionally not reproduced. |
| `renderables/ASCIIFont.ts` | `src/renderables/ascii_font.ml` | Active slice | Retained framebuffer-backed font rendering, color/background updates, resizing, and selection/copy exist. |
| `renderables/LineNumberRenderable.ts` | `src/renderables/line_number.ml`, `src/line_info.ml` | Active slice | Gutter composition consumes native visual line sources, measures line/sign widths, renders colors/signs/numbers, tracks scrolling, and owns only its internal gutter identity. |
| `renderables/TimeToFirstDraw.ts` | `src/renderables/time_to_first_draw.ml` | Active slice | Monotonic first-draw capture, precision formatting, centered/clipped drawing, mutation, and reset exist. |
| `renderables/text-table-width.ts` | `src/text_table_width.ml` | Active slice | Square-root water-fill proportional allocation and hard minimum/intrinsic-cap behavior are translated to typed integer inputs. |
| `renderables/TextTable.ts` | `src/renderables/text_table.ml` | Active slice | Native cell views provide measurement/wrapping/drawing; retained table layout, typed per-column alignment, borders, updates, and alignment-aware pointer selection/copy are implemented. Styled cell chunks are represented by `Lib.Styled_text`. |
| `renderables/composition/*` | `src/renderables/composition/{vnode,v_renderable,constructs}.ml` | Translated composition boundary | Typed inert VNodes instantiate ordinary `Renderable.t` identities; `VRenderable` supplies a typed draw callback, and constructors cover the implemented renderables including Code plus typed styled-text conveniences. Dynamic JavaScript method/property proxies are non-applicable to the typed OCaml API. |
| `renderables/Code.ts` | `src/renderables/code.ml` | Active parser-backed slice | Code owns a native text-buffer renderable, injected synchronous parser client, generation-checked result application, syntax-theme conversion, conceal/source-line mapping, selection, and explicit plain-text fallback. JavaScript workers and bundled WASM grammars are intentionally not claimed. |
| `renderables/Diff.ts` | `src/renderables/diff.ml`, `src/renderables/diff_parser.ml` | Active parser-backed slice | Unified and split views compose Code and line-number children, validate unified hunks, preserve selection/copy, render parse errors, and synchronize split scrolling through the retained pointer route. Rebuilds replace changed side children. |
| `renderables/Markdown.ts`, `renderables/markdown-parser.ts` | `src/renderables/markdown.ml`, `src/renderables/markdown_parser.ml` | Active parser-backed slice | Typed Markdown blocks/inlines, stable-prefix content reconciliation, syntax styles, concealment, link detection, code blocks, tables with parsed column alignment, borders/layout, selection aggregation, and lifecycle cleanup are present. The parser is an explicit OCaml subset rather than a claim of full `marked`/CommonMark parity. |
| `image.ts` | `src/image.ml`, `opentui-raw/image.ml`, `opentui-raw/image_stubs.c` | Active native-boundary slice | Encoded, Eio-path, and explicit RGBA sources use the vendored decoder through typed status/handle bindings. Metadata, materialization/copy, proportional or explicit resize, copy-transfer raw pixels, extraction, extension, transforms, compositing, and structured errors are exposed; Node/Bun asset discovery is not claimed. |
| `renderables/Image.ts` | `src/renderables/image.ml`, `src/owned_buffer.ml` | Active slice | Retained image sources resolve Kitty/Sixel/Blocks from explicit request and renderer capabilities, compute cell-aware fit/cover/fill geometry, pass source rectangles/pixel sizes through the clipping-aware native draw seam, optionally clear/draw through an owner-local off-screen buffer, and close retained images and buffers on replacement/destruction. |
| `post/matrices.ts` | `src/post/matrices.ml` | Active translated slice | All reference 4x4 RGBA matrices are immutable typed `floatarray` constants. |
| `post/filters.ts` | `src/post/filters.ml` | Active translated slice | Filters target borrowed renderer buffers through typed color-matrix and snapshot/restore operations; deterministic noise replaces process-global randomness and failures are structured. |
| `post/effects.ts` | `src/post/effects.ml`, `src/renderer.ml` | Active translated slice | Stateful distortion, vignette, cloud, flame, CRT, rainbow, and bloom effects preserve reference configuration/update contracts without retaining a buffer or hiding a scheduler; renderer post-process callbacks use owner-local IDs and explicit frame deltas. |
| `console.ts` | `src/console.ml`, integrated by `src/renderer.ml` | Active translated slice | Explicit log append/level storage, wrapping, scrolling, pointer selection/copy, position/size, visibility/focus, overlay drawing, resize, and destruction are renderer-owned. Process-global console capture, Node inspection, file saving, and stdin listener mutation are intentionally absent. |
| `lib/tree-sitter-styled-text.ts`, `lib/tree-sitter/{client,default-parsers,index,parsers-config,resolve-ft,types}.ts` | `src/tree_sitter_styled_text.ml`; `src/lib/tree_sitter_client.ml`, `tree_sitter_types.ml`, `tree_sitter_resolve_filetype.ml` | Active typed boundary | An injectable parser registry, filetype resolver, generation-ordered synchronous requests, highlight metadata, UTF-8 codepoint ranges, conceal/injection styling, and fallback errors replace the reference JS/WASM worker boundary. |
| `lib/tree-sitter/{assets,download-utils,parser.worker,update-assets,default-parser-assets.bun}.ts`; `platform/runtime-assets.*.ts` | [`background` feature record](../background/feature.md); no OCaml module yet | Translated platform boundary | Bundled JS/WASM assets, download/update tooling, and Bun/Node loaders remain non-applicable. Worker CPU isolation is planned as an application-owned Eio executor pool around injected parser implementations. |
| `lib/detect-links.ts`, `lib/hast-styled-text.ts` | `src/detect_links.ml`, `src/hast_styled_text.ml` | Active supporting utilities | Plain/syntax link ranges and typed HAST-to-styled-text conversion are used by content renderables; host parsers and JavaScript HAST loading remain outside Core. |

### Explicitly excluded runtime areas

The following reference areas are intentionally outside this tranche. Their
source-map entries remain explicit so a contributor can distinguish an
accepted exclusion from an unmapped feature:

| Reference area | Scope |
| --- | --- |
| `animation/*` | Timeline and animation scheduling; see the [animation feature record](../animation/feature.md). |
| `plugins/*` | Plugin registration and render slots; see the [plugins feature record](../plugins/feature.md). |
| `runtime-plugin*` | Bun-specific runtime module loading; see the [plugins feature record](../plugins/feature.md) for the boundary assessment. |
| `audio.ts`, `audio-stream/*` | Audio stream ownership, demuxing, buffering, reconnects, and metadata; see the [audio-stream feature record](../audio-stream/feature.md). |
| `node-assets.ts`, `node-asset-target.ts` | Translated/non-applicable Node native and parser-asset discovery. The Eio-native package has no corresponding Node asset manifest. |

### Active utility and platform translations

The reference `lib` directory contains utilities beyond framing and decoding.
The portable portions are implemented as small typed modules with explicit
owners and effect seams:

`ansi.ts`, `utils.ts`, `renderer-theme-mode.ts`, `clipboard.ts`,
`data-paths.ts`, `debounce.ts`, `env.ts`, `output.capture.ts`,
`parse.keypress-kitty.ts`, `queue.ts`, `renderable.validations.ts`,
`validate-dir-name.ts`, and `yoga.options.ts` correspond to active modules in
`src/lib` or `src/renderer_theme_mode.ml`.

`singleton.ts` is translated through owner composition: renderer/session,
context, data-path, environment, clipboard, output-capture, and parser owners
are passed explicitly. The port does not add a process-global singleton.

The following reference mechanisms are translated/non-applicable platform
details rather than missing Core APIs:

- `lib/bunfs.ts` provides Bun-specific embedded-file path handling and has no
  Eio runtime equivalent.
- `lib/fonts/*.json` is checked in as generated typed data for the active
  ASCII-font feature.
- tree-sitter JS/WASM assets, download/update scripts, and default Bun parser
  assets are not runtime mechanisms in the Eio port; parser clients are
  injected as typed OCaml functions, while the reference worker's CPU
  isolation role is covered by the [`background` feature
  record](../background/feature.md).
- `node-assets.ts`, `node-asset-target.ts`, and Node/Bun runtime asset loaders
  have no Eio runtime equivalent.

The existing `terminal_modes.ml`, `terminal_size.ml`, `clock.ml`, terminal
session, and Eio runtime modules cover the terminal-session and runtime
portions of that area. Capability response recognition,
palette parsing/normalization, renderer geometry, generic selection
calculations, native text-view selection, editor state, and the utility
modules above are active. Actual terminal output setup and asynchronous query
scheduling remain Eio/application responsibilities; scrollbar repeat and
selection auto-scroll likewise remain explicit application-owned scheduling
seams.

## Port sequence

The port sequence follows reference dependency boundaries rather than the
current size of the OCaml tree:

1. Maintain the source map and directory correspondence as upstream changes
   arrive.
2. Audit renderer-facing terminal session, native geometry, parser, editor,
   buffer, utility, and renderable contracts against the pinned reference.
3. Keep Eio/application scheduling, Node/Bun/WASM loaders, and raw ABI
   ownership at their documented boundaries.
4. Port `packages/keymap` as a separate package after the core host seams are
   stable. The keymap package does not require every optional media or plugin
   feature, but it does require stable renderer, focus, target-destruction,
   key-release, capability, and raw-input boundaries.

The only remaining Core `Deferred` rows are the explicit animation,
audio/audio-stream, and plugins/runtime-plugin exclusions above. No excluded
area receives a speculative public module. A feature record and a
reference-backed contract precede each future port unit.

## Acceptance criteria

This feature record is accepted when:

- every non-generated reference `core/src` runtime path appears in the source
  map with a status and an OCaml destination or an explicit intentional
  boundary;
- `packages/opentui-core/README.md` describes the active portable Core
  correspondence, translated platform mechanisms, and explicit exclusions;
- new OCaml modules use the matching reference directory by default;
- translation names such as `Color`, `Key_decoder`, `Renderer_events`, and
  `Layout_children` have an explicit semantic explanation;
- tests, examples, benchmarks, and native code have explicit package-local
  placement rules;
- any future excluded or non-applicable row is explicit rather than a fake
  compatibility API.
