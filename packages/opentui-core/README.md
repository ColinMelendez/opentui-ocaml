# opentui-core

`opentui-core` is the user-facing Eio-native OCaml library for terminal UI
programs. It uses `opentui-raw` for checked calls to the Zig renderer. Its
implemented source directories follow the matching directories in
`vendor/opentui/packages/core/src`; the active portable correspondence,
translated platform mechanisms, and explicit exclusions are listed in the
[core source mirror](../../docs/major-features/in-progress/core-source-mirror/feature.md).
Package-local tests, reference tools, and performance tools remain under this
package.

## Renderer and buffers

`Renderer.t` owns one native renderer, one `Render_context.t`, and the native
renderer’s current and next buffers. `Render_context.t` is the capability view
shared by the renderer and retained renderables. It observes live dimensions
and frame identity, records coalesced render requests, and provides typed
resize and frame notifications from the renderer’s one owner-local event
source.

`Buffer.t` is a checked drawing view over one renderer-owned native buffer. A
buffer does not own its native storage and cannot be destroyed independently.
Resize mutates the native buffers in place, so existing `Buffer.t` values
observe the new dimensions. Destroying the renderer closes its context and
invalidates all borrowed buffers.

`Yoga.Node.t` represents an independently owned layout node. Attaching and
detaching a node does not free it; its owner frees it explicitly. The Yoga
module exposes the style operations required by the retained-rendering
modules and returns structured native errors.

The retained renderable tree, concrete Box and Text modules, and their
text-buffer dependencies follow the source correspondence recorded in the
[renderable-core feature record](../../docs/major-features/in-progress/renderable-core/feature.md).
They use the renderer, context, buffer, and Yoga ownership boundaries defined
here rather than introducing a second tree owner. The source map records the
remaining explicit exclusions and non-applicable JavaScript/Node/Bun platform
mechanisms; it does not claim compatibility APIs for them.

## Terminal capabilities

`Terminal_capabilities.t` is an immutable Core-owned copy of the raw renderer's
typed capability snapshot. `Renderer.capabilities` and
`Render_context.capabilities` observe the same current value. A recognized
capability response passed to `Renderer.handle_input` is processed
synchronously, replaces that value, emits the shared capability event, and
requests one forced repaint. The response is consumed instead of reaching key
handlers.

`Lib.Terminal_capability_detection` owns upstream response recognition and
bounded pixel-resolution parsing. `Renderer` also exposes transport-neutral
terminal query strings, palette-response feeding, pixel-resolution state, and
split-footer/render-geometry updates. The actual output writer, terminal
setup, and asynchronous query scheduling remain application/Eio concerns; Core
does not start terminal I/O or fibers.

## Core foundations

`Lib.Terminal_palette` parses and normalizes OSC palette responses, including
special colors and legacy tmux wrapping. `Lib.Rgba` preserves RGB, indexed, and
default-color intent and bridges to the raw-backed `Color` type when a native
drawing operation requires concrete channels. `Lib.Render_geometry`,
`Lib.Objects_in_viewport`, and `Lib.Selection` are transport-neutral geometry
and selection contracts.

`Text_buffer` and `Text_buffer_view` retain native storage ownership while Core
adds metadata, native selection/local-selection forwarding, selected-text
extraction, viewport state, line-info, wrapping, tab indicators, truncation,
and style hooks. `Native_span_feed` owns the Core-facing typed wrapper;
`opentui-raw` continues to own foreign allocation and lifetime tokens.
`Edit_buffer`, `Editor_view`, `Syntax_style`, and
`Lib.Extmarks`/`Lib.Extmarks_history` form the pure OCaml editing foundation.

The portable utility layer is also explicit and owner-local. `Lib.Ansi` builds
validated terminal escapes; `Lib.Clock` supplies injectable one-shot timing;
`Lib.Debounce` and `Lib.Queue` compose that clock/scheduler seam;
`Lib.Data_paths`, `Lib.Env`, and `Lib.Validate_dir_name` keep path and
environment state out of process globals; `Lib.Clipboard` owns injected host
and OSC52 terminal backends; `Lib.Output_capture` owns bounded capture sinks;
`Lib.Renderable_validations` and `Lib.Yoga_options` provide typed result-valued
parsers; and `Renderer_theme_mode` owns theme queries through injected output
and timing. These are translations of the reference effects, not global
singletons.

## Interactive renderables

The interactive controls are composed from the retained `Renderable.t` spine
and typed domain state. `Edit_buffer_renderable` owns cursor/edit/selection
synchronization over a native `Text_buffer_renderable`; `Textarea` adds
placeholder and focus colors, while `Input` adds single-line constraints and
commit/submit events. `Scroll_box` owns a wrapper/viewport/content subtree and
composes `Scroll_bar` and `Slider`; `Select` and `Tab_select` expose typed
selection events and directional key bindings.

Pointer selection reaches selectable text controls through the renderer's
captured selection route and the native local-selection feed. The controls
keep scheduler-dependent behavior explicit: scrollbar arrow repeat and
selection auto-scroll are application-owned clock/update policies. Retained scissor
execution is also still a renderer limitation, so a `Scroll_box` render that
reaches the unsupported scissor command reports `Error.Unsupported` rather
than silently dropping clipping.

These modules use composition and explicit owner boundaries rather than
inheritance-shaped compatibility wrappers. `Frame_buffer` and `Ascii_font`
own standalone `Owned_buffer` storage, while `Text_table` owns one retained
table identity plus native cell views. `Line_number` composes an internal
gutter with a caller-provided line-info target, and
`Time_to_first_draw` records the first monotonic draw. The composition
namespace provides inert typed VNodes that instantiate ordinary retained
identities; it does not introduce a second runtime tree. Animation,
audio/audio-stream, plugins/runtime-plugin, and dynamic JavaScript proxy
behavior are explicit exclusions in the source map.

## Dependency-ready renderables

`Buffer.t` is the borrowed renderer-surface API. `Owned_buffer.t` is the
explicit owner for off-screen native storage and exposes the typed operations
needed by framebuffer, ASCII-font, and table rendering. `Frame_buffer` uses
the shared compositing seam; `Ascii_font_spec` uses generated cfonts data and
Unicode code-point positions; `Text_table_width` keeps proportional column
allocation deterministic; and `Text_table` uses native text-buffer views for
measurement, wrapping, drawing, updates, and selection/copy. The line-number
gutter consumes visual line sources from text-buffer/editor targets, including
signs, colors, custom numbers, hiding, and scroll offsets.

The ASCII helper intentionally indexes OCaml Unicode code points instead of
the reference JavaScript UTF-16 code units. Proportional allocation uses
checked 64-bit cross-products for normal terminal-sized inputs; extreme
integer-width arithmetic is not a supported terminal use case.

## Parser-backed content

`Renderables.Code` owns one native `Text_buffer_renderable` and accepts an
application-registered `Lib.Tree_sitter_types.parser` through
`Lib.Tree_sitter_client`. Requests are synchronous and generation-checked:
when a parser callback causes a newer request, the older result is rejected.
Syntax highlights are converted to native styled chunks with UTF-8 code-point
ranges, syntax-theme merging, concealment, source-line mapping, selection, and
plain-text fallback for missing or failing parsers.

`Renderables.Diff` parses unified hunks into typed lines and composes Code with
line-number gutters in unified or split layout. `Renderables.Markdown` uses a
typed block/inline parser and retains unchanged stable-prefix blocks across
content updates; it renders headings, paragraphs, lists, blockquotes, fenced
code, tables, links, HTML text, borders, and selection aggregation.
`Detect_links` and `Hast_styled_text` are typed supporting conversions.

The OCaml boundary intentionally does not load the reference JavaScript
worker, WASM assets, or bundled language grammars. Applications must inject
parser functions for highlighting; unknown filetypes remain visible through
Code's explicit fallback state. The Markdown lexer covers the contracts used
by these renderables, not every extension of CommonMark/`marked`.

## Images and post-processing

`Image.t` is an explicit native image owner backed by the vendored Zig
decoder. Sources are encoded bytes, caller-provided RGBA bytes, or an
`Eio.Path.t` loaded through an application-owned Eio filesystem capability;
there is no Node/Bun asset loader. Metadata, pixel copying/materialization,
resize, extraction, extension, transforms, compositing, and protocol-neutral
image ownership return structured errors. `Image.resize` accepts either
dimension or both dimensions, and `Image.take_raw` enforces the native
single-owner materialization rule before returning an explicitly owned pixel
copy and closing the image owner. `Renderables.Image` retains its source,
resolves `Auto` against the renderer's Kitty/Sixel/tmux/pixel capabilities, and
delegates clipping and protocol fallback to the typed native buffer seam.
Buffered images clear and redraw an owner-local `Owned_buffer` before copying
it to the renderer surface. Explicit Sixel requests without pixel resolution
fall back to Blocks.

`Post.Matrices` contains the reference RGBA matrices. `Post.Filters` applies
color-matrix operations or snapshot-backed effects to borrowed renderer
buffers, while `Post.Effects` keeps only reusable configuration and animation
state. `Renderer.add_post_process` registers synchronous owner-local callbacks
with opaque removal IDs and an explicit frame delta. Effects do not retain a
buffer or start a scheduler; callers apply them inside their own Eio-owned
frame loop. Deterministic procedural noise keeps tests and repeated frames
free from process-global random state.

## Diagnostic console

`Renderer.console` exposes an owner-local `Console.t`. Applications append
typed log levels, show or hide the overlay, resize/reposition it, scroll,
select and copy displayed lines, handle owner-local pointer selection, and let
the renderer draw it as the last overlay pass.
Destroying the renderer destroys the console and invalidates its operations.
The port does not replace process-global `console.log`, inspect Node values,
save files, or install stdin listeners; applications that want capture bridge
their own logger to the explicit append API.

## Terminal modules

`Lib.Stdin_parser` is the terminal input boundary. It frames input bytes and
emits typed key, mouse, paste, and response events, including Kitty event and
lock metadata when the protocol context enables it. `Lib.Key_decoder` and
`Lib.Mouse_decoder` are parsing helpers used by `Lib.Stdin_parser`; they are
not a required second input stage. `Lib.Input_coordinator` and
`Lib.Event_queue` provide deadline, backpressure, and event-handoff policies.
`Lib.Stdin_parser` can either expose its timeout to that coordinator or own a
clock-backed one-shot timer; the owner is explicit in either case.
`Platform.Eio_runtime` contains Eio flow, wakeup, output, and dispatch
modules. `Platform.Eio_unix_runtime` contains Unix terminal-size, signal, and
termios-session modules. These modules provide explicit building blocks for
an application runtime; they do not hide resource ownership in a global loop.

`Lib.Key_handler` is the keyboard dispatch boundary. It runs renderer-global
handlers before the focused renderable's handlers and carries the reference
prevention, propagation, snapshot, and handler-error semantics. Pointer
dispatch is owned by `Renderer.t` and `Renderable.t`: the renderer selects a
target from the committed hit grid, and the retained tree bubbles the typed
pointer event toward its root.

The source locations, translated platform mechanisms, and explicit excluded
reference areas are listed in the [source correspondence map](../../docs/upstream-map.md).
