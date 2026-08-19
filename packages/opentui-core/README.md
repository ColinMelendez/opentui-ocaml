# opentui-core

`opentui-core` is the user-facing Eio-native OCaml library for terminal UI
programs. It uses `opentui-raw` for checked calls to the Zig renderer. Its
source directories follow the matching directories in
`vendor/opentui/packages/core/src`; the active portable correspondence,
translated platform mechanisms, and explicit exclusions are listed in the
[core source mirror](../../docs/major-features/in-progress/core-source-mirror/feature.md).
An active correspondence is not a claim of drop-in TypeScript API parity.
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
render geometry that can describe a split footer. The reference split-footer
replay, external-output capture, and scrollback-surface APIs are intentionally
not Core APIs: the Eio application and terminal-output layer owns that
boundary. Core does expose the renderer's explicit `Memory`, `Stdout`, and
feed-backed sink targets; the Eio application normally connects the sink to its
serialized `Output_flow`. Terminal setup, output-flow ownership, and
asynchronous query scheduling remain application/Eio concerns; Core does not
start terminal I/O or fibers. Applications that own those boundaries can call
`Renderer.start_capability_detection` explicitly; it emits the native
reference probe phase but leaves parser protocol context, timeout policy, and
terminal-mode cleanup to the application.

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
and style hooks. `Native_span_feed` is a reduced synchronous, copy-first
wrapper over the raw ABI: it exposes copied payloads, reservations, draining,
and explicit release, with no asynchronous `onData`/`onError`, backpressure, or
`idle` surface. `opentui-raw` continues to own foreign allocation and lifetime
tokens.
`Edit_buffer`, `Editor_view`, `Syntax_style`, and
`Lib.Extmarks`/`Lib.Extmarks_history` form the pure OCaml editing foundation.

The portable utility layer is also explicit and owner-local. `Lib.Ansi` builds
validated terminal escapes; `Lib.Clock` supplies injectable one-shot timing;
`Lib.Debounce` and `Lib.Queue` compose that clock/scheduler seam;
`Lib.Data_paths`, `Lib.Env`, and `Lib.Validate_dir_name` keep path and
environment state out of process globals; `Lib.Clipboard` owns an injected
synchronous host/OSC52 policy seam rather than upstream's asynchronous native
host service; `Lib.Output_capture` owns bounded capture sinks;
`Lib.Renderable_validations` and `Lib.Yoga_options` provide typed result-valued
parsers; and `Renderer_theme_mode` owns theme queries through injected output
and timing. These are translations of the reference effects, not global
singletons.

The optional Eio renderer scheduler attaches one owner-domain frame loop to a
renderer. It checks clock/switch affinity, preserves the coalesced request
after a failed frame, emits a typed render-error event, and retries at the
configured cadence. Closing the scheduler detaches frame driving without
closing the clock; the Eio switch that created the clock owns its lifetime.
Public close operations reject wrong-domain mutation with structured errors.
Render-error handlers return typed results, so recoverable handler failures do
not block later handlers; unexpected exceptions retain the surrounding Eio
failure policy.

## Interactive renderables

The interactive controls are composed from the retained `Renderable.t` spine
and typed domain state. `Edit_buffer_renderable` owns cursor/edit/selection
synchronization over a native `Text_buffer_renderable`; `Textarea` adds
placeholder and focus colors, while `Input` adds single-line constraints and
commit/submit events. `Scroll_box` owns a wrapper/viewport/content subtree and
composes `Scroll_bar` and `Slider`; `Select` and `Tab_select` expose typed
selection events and directional key bindings, and `Select` can rasterize
option labels with the shared ASCII-font data.

Pointer selection reaches selectable text controls through the renderer's
captured selection route and the native local-selection feed. The renderer
context owns scheduler-dependent behavior: scrollbar arrow repeat uses
cancel-safe one-shot clock chains, while selection auto-scroll uses one
idempotent live contribution and frame deltas. Retained opacity and scissor
commands execute through the typed native buffer stacks,
so `Scroll_box` clipping composes with nested retained content and propagates
native failures as structured Core errors.

These modules use composition and explicit owner boundaries rather than
inheritance-shaped compatibility wrappers. `Frame_buffer` and `Ascii_font`
own standalone `Owned_buffer` storage, while `Text_table` owns one retained
table identity plus native cell views. `Line_number` composes an internal
gutter with a caller-provided line-info target, and
`Time_to_first_draw` records the first monotonic draw. The composition
namespace provides inert typed VNodes that instantiate ordinary retained
identities, including `Code` descriptions and typed styled-text convenience
constructors; it does not introduce a second runtime tree. Animation,
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

`Text_table` accepts typed per-column left, center, and right alignment.
Propagating Markdown pipe-table alignment markers into that policy is an OCaml
extension; it is not behavior provided by the reference Markdown renderable.

The ASCII helper intentionally indexes OCaml Unicode code points instead of
the reference JavaScript UTF-16 code units. Proportional allocation uses
checked 64-bit cross-products for normal terminal-sized inputs; extreme
integer-width arithmetic is not a supported terminal use case.

## Parser-backed content

`Platform.Eio_runtime.Background` provides one application-owned Eio executor
pool for selected CPU-heavy work. Submitters are bound to an owner domain and
switch: only the typed work closure crosses to a reusable executor domain, and
completion returns to the owner. Cancellation suppresses callback delivery but
does not claim to interrupt CPU work already running. Tree-sitter-backed Code
uses this capability only for parser records marked `Worker_safe`; Code owns
per-instance generations, one running plus one latest pending snapshot, stale
completion rejection, and destruction lifetime checks. Its public `Pending`
state is entered only after worker admission or while the current snapshot is
queued behind admitted work; failed admission does not claim progress.
Destroying either Code or its exposed renderable identity runs the same
one-shot cancellation and internally owned syntax-style cleanup. Consumers
remain responsible for their retained-object ownership.

Although `Background.submit` is generically typed over a function, that
function is not an arbitrary-closure escape hatch. The contract admits only
isolated worker-safe work over owned snapshots; renderer, Eio resource,
foreign-handle, callback, and concurrently mutated application state must stay
on the owner domain.

`Renderables.Code` owns one native `Text_buffer_renderable` and accepts an
application-registered `Lib.Tree_sitter_types.parser` through
`Lib.Tree_sitter_client`. The client is only a registry and pure parser runner;
Code resolves an immutable parser/content snapshot, uses the optional
Background submitter for `Worker_safe` parsers, and keeps conversion,
callbacks, and native styled-buffer mutation on its owner domain. Syntax
highlights are converted to native styled chunks with UTF-8 code-point ranges,
syntax-theme merging, concealment, source-line mapping, selection, and
plain-text fallback for missing or failing parsers. Markdown, Diff, and
composition constructors can propagate the same optional submitter to Code;
Markdown parsing itself remains synchronous.
If the latest queued snapshot cannot be re-admitted from a completion, Code
runs that resolved worker-safe snapshot synchronously on the owner rather than
losing the current generation.

Code's `streaming` option is behavioral: the initial parser generation shows
`initial_styled_text` or raw content only when `draw_unstyled_text` permits it;
with that option disabled and no settled result, the buffer stays empty while
highlighting runs. After a streaming result settles, later updates retain the
last settled highlighted buffer while the current parse and one latest pending
snapshot run. Non-streaming generations apply the draw policy independently.
`highlighting_done` is a read-only promise for the current generation;
superseded, synchronous, fallback, and destroyed generations all settle it.
`on_highlight` and `on_chunks` receive typed owner-domain context records
containing content, filetype, syntax style, and final highlights where
applicable. Typed callback errors use Code's plain-text fallback; unexpected
callback exceptions remain Eio switch failures. Markdown forwards
`draw_unstyled_text = not streaming` to fenced Code children.

`Renderables.Diff` parses unified hunks into typed lines and composes Code with
line-number gutters in unified or split layout. It retains the portable
syntax/default line styling but does not expose the reference's full mutable
Diff styling option surface. `Renderables.Markdown` uses a typed block/inline
parser and retains unchanged stable-prefix blocks across content updates; it
renders headings, paragraphs, lists, blockquotes, fenced code, tables, links,
HTML text, borders, and selection aggregation. Markdown pipe-table alignment
is additionally projected into `Text_table` by this OCaml port; it is an
extension rather than upstream parity.
`Detect_links` and `Hast_styled_text` are typed supporting conversions.

The OCaml boundary intentionally does not load the reference JavaScript
worker, WASM assets, or bundled language grammars. Applications must inject
parser functions for highlighting; unknown filetypes remain visible through
Code's explicit fallback state. The Markdown lexer covers the contracts used
by these renderables, not every extension of CommonMark/`marked`.

## Images and post-processing

`Image.t` is a synchronous, callback-free native image owner backed by the
vendored Zig decoder. Encoded and RGBA source bytes are copied at admission;
path reads are bounded to 64 MiB and report structured `Read` errors for I/O
or oversized input, while native decode failures remain exact `Decode` errors.
`Image.load` can read an `Eio.Path.t` synchronously under Eio, but
`Renderables.Image` Native admission and Core encoded/RGBA use do not require
an Eio runtime. There is no Node/Bun asset loader. Metadata, pixel
copying/materialization, resize, extraction,
extension, transforms, compositing, and protocol-neutral image ownership
return structured errors. `Image.resize` accepts either dimension or both
dimensions, and `Image.take_raw` enforces the native single-owner materialization
rule before returning an explicitly owned pixel copy and closing the image
owner.

This deliberately omits the reference `ImageSource` URL, `Blob`, and
`Response` shapes and the renderable's `loadPromise`. Path loading uses Eio
direct style, and `Renderables.Image` reports through direct-style callbacks
with immutable `Image.info` and structured load errors.

`Renderables.Image` retains its source and exposes the truthful
`Empty`/`Loading`/`Ready`/`Failed` state. A Path source is read asynchronously
and cooperatively by an owner-domain Eio fiber only when `~sw` is supplied;
native decode, retain, callbacks, drawing, and close remain on that owner
domain. A very large encoded image can therefore still consume a frame during
decode. Each request is generation-checked and cancel-safe: stale completions
are inert, failed replacements preserve the displayed image, and clearing or
destroying closes it immediately. `on_load` receives immutable `Image.info`,
while `on_error` receives the structured load error. The renderable resolves
`Auto` against Kitty/Sixel/tmux/pixel capabilities and delegates clipping and
protocol fallback to the typed native buffer seam. Buffered images clear and
redraw an owner-local `Owned_buffer` before copying it to the renderer surface.
Explicit Sixel requests without pixel resolution fall back to Blocks.

`Post.Matrices` contains the reference RGBA matrices. `Post.Filters` applies
color-matrix operations or snapshot-backed effects to borrowed renderer
buffers, while `Post.Effects` keeps only reusable configuration and animation
state. `Renderer.add_post_process` passively registers synchronous owner-local
callbacks with opaque removal IDs and an explicit frame delta. During a frame,
retained content is followed by post processes, the diagnostic console, and
native presentation. Effects do not retain a buffer or start a scheduler;
callers request frames or hold an explicit live contribution when an effect
needs ongoing updates. Deterministic procedural noise keeps tests and repeated
frames free from process-global random state.

## Diagnostic console

`Renderer.console` exposes an owner-local `Console.t`. Applications append
typed log levels, show or hide the overlay, resize/reposition it, scroll,
select and copy displayed lines, handle owner-local pointer selection, and let
the renderer draw it after post processes as the last overlay pass before
native presentation.
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
