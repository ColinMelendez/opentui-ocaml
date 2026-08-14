# Core source mirror

## Purpose

`opentui-core` is the OCaml port of `vendor/opentui/packages/core`. The source
tree is the contributor-facing index for that port. A contributor who starts
with a reference path can use the same package and directory names to locate
the OCaml correspondence, then use this record and the source map to identify
translation boundaries and coverage.

The reference core contains more than the renderer and renderables. It also
contains terminal utilities, text editing state, selection, syntax styling,
post-processing, animation, plugins, media support, testing helpers, and
native span and buffer integration. The port records each area instead of
describing the present implementation as a complete core.

## Status vocabulary

The source map uses these statuses:

- **Active slice** means that an OCaml module exists and its accepted boundary
  is defined by an in-progress or implemented feature record.
- **Partial** means that an OCaml module exists but its reference API or
  observable behavior is incomplete.
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
| `lib/RGBA.ts` | `Color` | `Color` is a small raw-backed renderer color wrapper. It does not implement the reference RGBA color-intent, indexed-color, default-color, parsing, and conversion model. The full reference feature uses an `Rgba`-shaped module. |
| `lib/parse.keypress.ts` | `Lib.Key_decoder` | The existing module exposes a smaller key decoding boundary and does not carry Kitty event type, base-code, lock, or keypad metadata. The reference parser correspondence is partial. |
| `lib/parse.mouse.ts` | `Lib.Mouse_decoder` | The existing module owns stateful terminal mouse classification. The name describes that state boundary; the reference parser correspondence is partial. |
| `core/src/zig` | `opentui-raw` | The package split protects the native ABI and prevents raw handles from entering the core API. |
| reference renderer events | Internal `renderer_events.ml`, surfaced through `Render_context` and `Renderer` | The typed owner-local event vocabulary is an OCaml composition mechanism, not a new reference feature or public module. |
| reference base child methods | `Layout_children` and `Text_children` | Typed child capabilities replace inheritance-based dynamic child dispatch. |

The naming rule prevents a cosmetic rename from claiming a semantic port. A
module moves to the reference-derived name when its public contract matches the
reference concept closely enough for the name to be truthful.

## Core correspondence

### Active slices and partial modules

| Reference path | OCaml path | Status | Boundary |
| --- | --- | --- | --- |
| `Renderable.ts` | `src/renderable.ml`, `src/layout_children.ml` | Active slice | Heterogeneous retained nodes, typed child capabilities, layout state, lifecycle, focus, keyboard slots, and pointer routing. |
| `renderer.ts` | `src/renderer.ml` | Partial | Renderer ownership, frames, borrowed buffers, retained-tree rendering, hit-grid routing, focus, and input dispatch exist. Selection, native scissor-aware hit-grid writes, and several renderer services remain separate correspondence work. |
| `types.ts` (`RenderContext`) | `src/render_context.ml`, with internal `src/renderer_events.ml` | Partial | Renderer-owned capabilities and typed owner-local event sources exist. The reference capability and lifecycle vocabulary is broader. |
| `yoga.ts` | `src/yoga.ml` | Active slice | Independent node ownership, non-destructive detach, explicit free, style operations, and layout readback exist. |
| `buffer.ts` | `src/buffer.ml`, `opentui-raw/buffer.ml` | Partial / translated | Core drawing views and the raw native seam exist. The complete reference buffer surface is not present. |
| `text-buffer.ts` | `src/text_buffer.ml` | Partial | The text-buffer state and native-backed operations exist. The full reference editing and selection surface is not present. |
| `text-buffer-view.ts` | `src/text_buffer_view.ml` | Partial | View ownership and native calls exist. The complete reference view API is not present. |
| `NativeSpanFeed.ts` | `opentui-raw/span_feed.ml` | Partial / translated | The foreign span-feed boundary exists in the raw package. Core-facing integration and the complete reference surface remain incomplete. |
| `zig.ts`, `zig-structs.ts` | `opentui-raw` | Translated native boundary | Native loading, ABI records, and foreign callbacks live below the core package. |
| `index.ts` | `opentui-core/src` Dune library boundary | Translated package boundary | Dune's wrapped library and package modules provide the public export boundary; no literal barrel module is introduced. |
| `lib/index.ts` | `opentui-core/src/lib` qualified namespace | Translated package boundary | The qualified source directory provides the library namespace. |
| `renderables/index.ts` | `opentui-core/src/renderables` qualified namespace | Translated package boundary | The qualified source directory provides the renderables namespace. |
| `lib/KeyHandler.ts` | `src/lib/key_handler.ml` | Active slice | Global/local keyboard dispatch, prevention, propagation, cleanup, and handler-error reporting exist. Parser delivery of Kitty release and repeat events remains incomplete. |
| `lib/stdin-parser.ts` | `src/lib/stdin_parser.ml` | Partial | Framing, paste ownership, mouse events, key events, responses, bounded prefixes, and timeouts exist. The reference parser's complete key event metadata is not present. |
| `lib/parse.keypress.ts` | `src/lib/key_decoder.ml` | Partial | Common terminal key forms decode into typed OCaml values. Kitty protocol event typing and the full reference metadata surface remain absent. |
| `lib/parse.mouse.ts` | `src/lib/mouse_decoder.ml` | Partial | SGR and X10 decoding, modifiers, scrolling, and drag classification exist. The full reference mouse lifecycle is owned by the renderer and renderable modules. |
| `lib/border.ts` | `src/lib/border.ml` | Active slice | Border geometry and native drawing translation exist. |
| `lib/styled-text.ts` | `src/lib/styled_text.ml` | Partial | Styled text values and renderable text composition exist. The complete reference style vocabulary is not present. |
| `lib/clock.ts` | Eio `Clock` capability supplied at `src/platform/eio_runtime` | Translated | The Eio runtime supplies time and cancellation capabilities; no standalone clock module mirrors the Bun/Node helper. |
| `lib/paste.ts` | `src/lib/stdin_parser.ml` | Translated | Paste framing and payload ownership are part of the parser boundary. |
| `platform/*` | `src/platform/*` | Translated | Eio runtime and Unix terminal-session modules replace the reference Bun/Node runtime adapters. |
| `renderables/Box.ts` | `src/renderables/box.ml` | Active slice | Box construction, style mutation, child capability, layout, and drawing exist. |
| `renderables/Text.ts` | `src/renderables/text.ml` | Partial | Text composition and lifecycle integration exist. Native measurement and the full text surface remain incomplete. |
| `renderables/TextNode.ts` | `src/renderables/text_node.ml` | Active slice | Text-node ownership and style state exist. |
| `renderables/TextBufferRenderable.ts` | `src/renderables/text_buffer_renderable.ml` | Partial | Native measurement ownership and text-buffer rendering integration are present. |

### Deferred runtime areas

The following reference areas have no public OCaml module. Their source-map
entries remain explicit so a contributor can distinguish absence from an
unmapped feature:

| Reference area | Scope |
| --- | --- |
| `edit-buffer.ts`, `editor-view.ts` | Text editing state, history, and editor view. |
| `syntax-style.ts` | Syntax style registration and text-buffer style lookup. |
| `post/*` | Post-processing effects, filters, and matrices. |
| `animation/*` | Timeline and animation scheduling. |
| `plugins/*`, `runtime-plugin*` | Plugin registration and runtime plugin support. |
| `audio.ts`, `audio-stream/*` | Audio capture, playback, demuxing, and metadata. |
| `image.ts` | Terminal image loading and rendering support. |
| `console.ts` | Renderer-backed diagnostic console. |
| `renderables/EditBufferRenderable.ts`, `FrameBuffer.ts`, `Input.ts`, `Textarea.ts` | Editor and framebuffer renderables. |
| `renderables/ScrollBox.ts`, `ScrollBar.ts`, `Select.ts`, `Slider.ts`, `TabSelect.ts` | Interactive container and selection renderables. |
| `renderables/Code.ts`, `Diff.ts`, `Markdown.ts`, `TextTable.ts` | Higher-level text renderables and parsers. |
| `renderables/Image.ts`, `ASCIIFont.ts` | Image and font renderables. |
| `renderables/LineNumberRenderable.ts`, `TimeToFirstDraw.ts` | Supporting renderables for line numbers and first-draw timing. |
| `renderables/markdown-parser.ts`, `text-table-width.ts` | Helpers used by the deferred Markdown and TextTable renderables. |
| `renderables/composition/*` | Virtual renderable and composition helpers. |
| `node-assets.ts`, `node-asset-target.ts` | Node native and parser-asset discovery. The Eio-native package has no corresponding Node asset manifest. |

### Deferred library areas

The reference `lib` directory contains several utilities beyond framing and
decoding. These areas are separate port units:

`ansi.ts`, `utils.ts`, `renderer-theme-mode.ts`, `RGBA.ts`, `ascii.font.ts`,
`clipboard.ts`, `data-paths.ts`, `debounce.ts`,
`detect-links.ts`, `env.ts`, `extmarks.ts`, `extmarks-history.ts`,
`hast-styled-text.ts`, `keybinding.internal.ts`, `objects-in-viewport.ts`,
`output.capture.ts`, `parse.keypress-kitty.ts`, `queue.ts`,
`render-geometry.ts`, `renderable.validations.ts`, `scroll-acceleration.ts`,
`selection.ts`, `singleton.ts`, `terminal-capability-detection.ts`,
`terminal-palette.ts`, `tree-sitter-styled-text.ts`, `tree-sitter/*`,
`validate-dir-name.ts`, and `yoga.options.ts`.

The following deferred assets and helpers retain their reference locations in
the source map:

- `lib/bunfs.ts` provides Bun-specific embedded-file path handling and has no
  Eio runtime equivalent.
- `lib/fonts/*.json` supplies data for the deferred ASCII-font feature.
- `renderables/markdown-parser.ts` and `renderables/text-table-width.ts`
  support the deferred Markdown and TextTable renderables.
- `node-assets.ts` and `node-asset-target.ts` describe Node package assets and
  have no Eio runtime equivalent.

The existing `terminal_modes.ml`, `terminal_size.ml`, and Eio runtime modules
cover only the terminal-session and runtime portions of that area. They do not
stand in for terminal capability detection, palette state, selection, or the
other deferred modules.

## Port sequence

The port sequence follows reference dependency boundaries rather than the
current size of the OCaml tree:

1. Maintain the source map and directory correspondence.
2. Complete renderer-facing terminal capabilities, palette, geometry,
   selection, and native span integration.
3. Port syntax style, edit-buffer state, and editor-view dependencies.
4. Port the reference renderables in `src/renderables`, keeping their
   reference-specific child and lifecycle policies.
5. Port independent core subsystems such as post-processing, animation,
   plugins, media, image support, and the diagnostic console as separate
   feature records.
6. Port `packages/keymap` as a separate package after the core host seams are
   stable. The keymap package does not require every optional media or plugin
   feature, but it does require stable renderer, focus, target-destruction,
   key-release, capability, and raw-input boundaries.

No deferred area receives a speculative public module. A feature record and a
reference-backed contract precede each new port unit.

## Acceptance criteria

This feature record is accepted when:

- every non-generated reference `core/src` runtime path appears in the source
  map with a status and an OCaml destination or an explicit intentional
  boundary;
- `packages/opentui-core/README.md` describes the implemented coverage without
  implying complete core parity;
- new OCaml modules use the matching reference directory by default;
- translation names such as `Color`, `Key_decoder`, `Renderer_events`, and
  `Layout_children` have an explicit semantic explanation;
- tests, examples, benchmarks, and native code have explicit package-local
  placement rules;
- each missing core slice has a feature record before implementation.
