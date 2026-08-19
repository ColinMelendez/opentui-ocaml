# Architecture

This document defines the package boundaries and terminology of the OCaml
OpenTUI library. OpenTUI is a terminal user-interface framework with a
TypeScript reference implementation and a Zig renderer. The reference source
is checked out at `vendor/opentui`; the source correspondence is indexed in
the [source correspondence map](upstream-map.md). The contributor workflow
for translating a reference feature into OCaml is in
[`CONTRIBUTING.md`](../CONTRIBUTING.md).

“Active” and “translated” in the source map mean that the portable contract is
implemented within a documented ownership boundary; they do not imply a
drop-in TypeScript API or exact host-runtime parity.

## Terms

| Term | Meaning in this repository |
| --- | --- |
| Reference source | The OpenTUI source in `vendor/opentui`. It defines the behavior and source paths that the OCaml implementation follows. |
| ABI | The C-compatible function and data representation used to call the Zig renderer. |
| Retained UI tree | A tree whose nodes remain allocated and keep their identities while properties change between frames. |
| Renderer | The `opentui-core.Renderer` owner of the retained root, frame buffers, render-context capabilities, frame lifecycle, transport-neutral render geometry, explicit `Memory`/`Stdout`/feed-backed output selection, and renderer-level events. It corresponds to the portable portion of the reference `CliRenderer`; Eio application/terminal output owns terminal setup, output-flow serialization, and stream integration. |
| Render context | The capability view that gives a renderable access to renderer-owned dimensions, layout, events, input, focus, and render requests. It corresponds to the reference `RenderContext`. |
| Renderable | A retained node that contributes visual output and participates in parent-child ownership, layout, lifecycle, and rendering. `Box`, `Text`, text editors, scrolling controls, selectors, `Slider`, framebuffer/font renderables, tables, and line-number composition are concrete renderables. |
| Yoga | The layout engine used by `opentui-core` to calculate node positions and dimensions. |
| Eio | The OCaml library used for structured concurrency, terminal I/O, clocks, cancellation, and resource cleanup. |

## Packages and dependency direction

The repository contains two public OCaml packages:

| Package | Responsibility | Dependency direction |
| --- | --- | --- |
| `opentui-raw` | Calls the reference Zig renderer through C, validates ABI values, and owns foreign resource lifetimes. | Independent of `opentui-core`. |
| `opentui-core` | Provides the retained UI tree, renderer composition, renderables, terminal protocols, and Eio/Unix terminal modules. | Depends on `opentui-raw`. |

The dependency direction is:

```text
OCaml application
       │
       ▼
opentui-core
       │
       ▼
opentui-raw
       │
       ▼
reference Zig renderer in vendor/opentui
```

`opentui-raw` is a separate package because ABI calls and foreign-resource
lifetimes have different invariants from retained UI ownership and terminal
policy. The higher-level package can use checked renderer operations without
publishing packed handles, raw pointers, or C callback details.

## Package-local validation and tooling

Code that exercises one package is stored in that package directory:

| Package directory | Contents |
| --- | --- |
| `packages/opentui-core/test` | Tests for the retained renderable tree, renderer, terminal protocols, and Eio/Unix integrations. |
| `packages/opentui-core/examples` | Executable examples of the public core API. |
| `packages/opentui-core/reference` | Optional comparisons between core behavior and the TypeScript reference source. |
| `packages/opentui-core/bench` | Release-profile workloads, allocation baselines, and tracing wrappers for core behavior. |
| `packages/opentui-raw/test` | Tests for the raw ABI, C stubs, foreign ownership, and the native link seam. |

The repository-level `docs/` directory contains architecture documents,
source mapping, and cross-cutting feature records. Architecture documents
describe the relationship between both OCaml packages, the checked-out
reference source, and repository-wide implementation decisions. Feature
records describe contracts that span several modules or packages. Historical
notes remain under `docs/archive/` and are not part of the active package
contract.

## `opentui-core/src`

The `opentui-core/src` tree follows `vendor/opentui/packages/core/src`. This
tree lists the primary package modules and the internal modules that define
current boundaries. The source map is the exhaustive path inventory, and it
lists every deliberate directory, module-name, effect, and platform difference.

```text
src/
├── renderer.ml              CliRenderer ownership, frame lifecycle, geometry, output
├── render_context.ml        capabilities supplied to renderables
├── terminal_capabilities.ml capability snapshots and response state
├── native_span_feed.ml       synchronous copy-first feed wrapper for renderer sinks
├── edit_buffer.ml            pure editing, cursor, history, and extmark state
├── editor_view.ml            visual-line and selection view over Edit_buffer
├── syntax_style.ml           syntax-style registration and resolution
├── buffer.ml                renderable-facing buffer operations
├── color.ml                 raw-backed renderer color values
├── error.ml                 structured core errors
├── event_kernel.ml          internal synchronous event dispatch
├── event_subscription.ml    owner-local notification cancellation
├── layout_children.ml       typed layout-child capability
├── native_measure.ml        internal text measurement seam
├── yoga.ml                  private layout-node ownership and readback
├── renderer_events.ml        internal renderer event vocabulary
├── lib/                     terminal protocol and input support
│   ├── styled_text.ml
│   ├── ansi.ml                  validated ANSI escape builders
│   ├── clock.ml                 injected one-shot time/cancellation
│   ├── clipboard.ml             injected synchronous host/OSC52 policy seam
│   ├── data_paths.ml            owner-local application paths
│   ├── debounce.ml              clock-backed one-shot debounce
│   ├── env.ml                   owner-local environment/config state
│   ├── kitty_keypress.ml        Kitty keyboard protocol
│   ├── output_capture.ml        explicit bounded capture sink
│   ├── queue.ml                 injected-scheduler process queue
│   ├── renderable_validations.ml typed renderable option validation
│   ├── utils.ml                 typed text/link/tree utilities
│   ├── validate_dir_name.ml     structured directory-name validation
│   ├── yoga_options.ml          typed Yoga option parsing
│   ├── rgba.ml                  color intent and conversion
│   ├── stdin_parser.ml
│   ├── byte_queue.ml
│   ├── input_coordinator.ml
│   ├── event_queue.ml
│   ├── key_decoder.ml
│   ├── mouse_decoder.ml
│   ├── terminal_palette.ml
│   ├── render_geometry.ml       transport-neutral, including split-footer geometry
│   ├── objects_in_viewport.ml
│   ├── selection.ml
│   ├── extmarks.ml
│   ├── extmarks_history.ml
│   ├── text_attributes.ml
│   ├── text_metrics.ml
│   ├── terminal_modes.ml
│   └── ...
├── renderables/               retained renderable modules
│   ├── box.ml
│   ├── text.ml
│   ├── text_children.ml
│   ├── text_node.ml
│   ├── text_buffer_renderable.ml
│   ├── edit_buffer_renderable.ml
│   ├── textarea.ml
│   ├── input.ml
│   ├── scroll_box.ml
│   ├── scroll_bar.ml
│   ├── select.ml
│   ├── tab_select.ml
│   ├── slider.ml
│   ├── frame_buffer.ml
│   ├── ascii_font.ml
│   ├── line_number.ml
│   ├── time_to_first_draw.ml
│   ├── text_table.ml
│   ├── code.ml             injected syntax/highlight text
│   ├── diff.ml             unified/split diff composition
│   ├── diff_parser.ml      typed unified-hunk parser
│   ├── markdown.ml         retained Markdown block composition
│   ├── markdown_parser.ml  typed Markdown block/inline lexer
│   └── composition/       typed VNode/VRenderable construction boundary
├── owned_buffer.ml         explicit off-screen buffer ownership
├── image.ml                synchronous native image owner and bounded path reader
├── console.ml              renderer-owned diagnostic overlay
├── post/                   typed matrices, filters, and stateful effects
├── line_info.ml             shared visual-line metadata
├── ascii_font_spec.ml       generated-font measurement/raster helpers
├── text_table_width.ml      deterministic column allocation
├── tree_sitter_styled_text.ml  highlight-to-styled-text conversion
├── detect_links.ml           syntax/plain URL ranges and link chunks
├── hast_styled_text.ml       typed HAST-style conversion
├── text_buffer.ml             text-buffer state
├── text_buffer_view.ml        text-buffer viewport state
├── platform/                Eio and operating-system integration
│   ├── eio_runtime/         Eio flows, output, wakeups, and dispatch
│   └── eio_unix_runtime/    termios, SIGWINCH, and terminal-size support
└── native/                  OCaml errors for native composition
```

Retained renderables and text-buffer modules occupy the reference directories
recorded in the renderable-core feature record. The portable runtime paths
marked active are implemented within their documented boundaries; that status
does not claim every reference option or host service. The [core source
mirror](major-features/in-progress/core-source-mirror/feature.md) records the
active portable animation, audio-stream, and plugin slices, the still-deferred
runtime-plugin and Node/Bun/JavaScript/WASM mechanisms, and the deliberate
portable reductions.

Parser-backed content stays below the retained renderable identity: `Code`
owns one `Text_buffer_renderable`, `Diff` composes ordinary Code and gutter
children, and `Markdown` owns a layout-children list whose stable prefix can
be retained across content updates. `Lib.Tree_sitter_client` is an injectable,
owner-domain parser registry and pure runner; `Code` can submit explicitly
`Worker_safe` parser snapshots through `Platform.Eio_runtime.Background`,
while `Owner_only` parsers remain synchronous. It does not load JavaScript
workers, WASM grammars, or claim a language parser that the application has
not registered; unresolved filetypes become explicit Code fallback states.
Code's streaming mode applies initial visibility through `draw_unstyled_text`,
retains the last settled highlighted buffer across later streaming updates,
and keeps at most one latest pending snapshot. Non-streaming generations apply
the visibility policy independently. Its current-generation settlement is an
Eio promise that also resolves when work is superseded or Code is destroyed;
callback contexts remain owner-domain direct-style records, and typed callback
errors fall back to plain text while unexpected exceptions follow Eio failure
semantics. Markdown forwards the inverse streaming flag as the fenced Code
draw policy.

Images and post-processing stay below the same retained identity boundary.
`Image.t` is a synchronous, callback-free owner of native decoder handles. It
copies encoded/RGBA admission bytes, bounds path reads to 64 MiB, and preserves
the distinction between read, decode, and native-operation errors.
`Renderables.Image` owns retained references and, when requested, an owner-local
`Owned_buffer.t`. Its optional Eio switch is required only for Path sources:
the owner fiber performs cooperative path I/O and generation/cancellation
delivery, while native decode, retain, direct-style callbacks, drawing, and
close remain on the owner domain. The port intentionally omits the reference
URL/Blob/Response source shapes and `loadPromise`; thus a large decode can
still occupy a frame, and no native image handle enters the background
executor. It passes capability-selected protocol placement through the borrowed
`Buffer.t` seam. `Post.Filters` and
`Post.Effects` never own a buffer; they operate on a borrowed renderer surface
through typed matrices or snapshots. Renderer post-process registrations are
owner-local and removed by opaque IDs. `Console.t` is owned by `Renderer.t`, so
its overlay, scroll/selection state, and log state have renderer lifetime and
do not require process-global output replacement.

The names `eio_runtime` and `eio_unix_runtime` avoid a Dune namespace conflict:
with qualified subdirectories, a directory named `eio` or `unix` would shadow
the external OCaml modules `Eio` or `Unix`. Both directories remain under
`src/platform`. The source map records the reference `platform/*` directory
and explains this OCaml-specific split; `eio_runtime` and `eio_unix_runtime`
are not directories in the reference source.

## Effect boundary

The application-facing runtime is Eio-native. One Eio switch can own terminal
setup, input, output, clocks, cancellation, and cleanup. `opentui-core` keeps
rendering, parsing, and native image decode synchronous: `Renderer`,
`Renderable`, Yoga, renderable setters, the byte parser, and the bounded event
queue do not start fibers. `Renderer` may synchronously hand complete native
frame chunks to the caller-provided output sink; it does not own an Eio flow or
terminal session. The one image exception is
the explicit `Renderables.Image` Path mode, whose owner-domain fiber performs
cooperative file I/O before handing bytes to that synchronous decoder.

An application fiber calls the synchronous renderer and parser operations. The
renderer exposes explicit frame execution and presentation boundaries, so an
application may either present explicitly or attach the owner-domain Eio
scheduler. That scheduler is the semantic adapter for coalesced frame
requests, live pacing, and recoverable render-error retries; it does not own
the renderer's clock or terminal resource. Eio `Output_flow` is the serialized
sink used when terminal setup, queries, frames, and shutdown must share one
owner. This boundary keeps scheduling and terminal resource lifetime out of
per-cell rendering operations while allowing Eio to own the surrounding
application runtime. Clock and scheduler mutation
is owner-domain checked, including closure; portable clock callbacks fail
loudly on affinity misuse because their callback shape cannot return a
structured error. Render-error subscriptions instead expose typed callback
results, isolating expected handler failures while leaving programmer
exceptions to the owner/Eio failure policy. Capability and palette
response recognition, query-string construction, geometry updates, and native
text-view selection forwarding, and the portable utility services are
synchronous Core operations. Split-footer geometry is transport-neutral; the
reference external-output, replay, and scrollback surfaces are not Core APIs.
Terminal setup and output writing remain Eio/application responsibilities;
`Renderer.Output.Stdout` is an explicit low-level escape hatch for applications
that already own fd 1.
`Lib.Clock` makes one-shot timing
injectable for debounce, queues, theme queries, and parser timeouts.

Capability probing is the deliberate exception to the otherwise application-
owned terminal setup boundary. The reference `CliRenderer.setupTerminal`
bundles its capability probes with alternate-screen entry, terminal-mode
changes, feature enabling, and cleanup. The Eio harness already owns those
mode transitions and the serialized output flow, so calling the complete
reference setup would duplicate ownership. The native `queryTerminalCapabilities`
adapter exposes only the reference probe phase instead of reimplementing its
XTVERSION ordering, multiplexer wrapping, and pending-query retries in OCaml;
`Renderer.start_capability_detection` is the explicit Core entry point, while
the application still owns parser framing, timeout policy, and cleanup.

## Translating TypeScript concepts

The OCaml API follows OpenTUI behavior and source organization without copying
TypeScript class syntax or JavaScript runtime mechanisms.

| Reference mechanism | OCaml representation |
| --- | --- |
| Base class and inheritance | `Renderable.t` owns identity, tree ownership, lifecycle, and the private behavior hooks that concrete renderable modules compose with their typed state. Behavior hooks preserve replacement semantics at reference virtual-method boundaries. |
| Child attachment methods | Concrete modules expose typed `Layout_children.t` or `Text_children.t` capabilities. `Renderable.t` has no universal public `add`, `remove`, or `insertBefore` operation. |
| Constructor option bag | Labelled arguments and typed records for reusable groups of values. |
| Public mutable property | A typed accessor and setter that preserve reference validation, clamping, equality/no-op, invalidation, and error behavior. |
| `EventEmitter` | Owner-local typed event channels composed into the renderer, render context, or component. Synchronous registration-order dispatch, snapshot semantics, reentrancy, duplicate subscriptions, one-shot removal, callback exceptions, cleanup, and producer-owned scheduling remain explicit. Keyboard priority, pointer propagation, queueing, and backpressure remain separate dispatch systems. |
| Render invalidation and command-list reuse | Separate renderable dirty state, Yoga layout generation, and render-list revision. The root stores a reuse decision when it rebuilds a list; later frames reuse it only while that decision and both recorded generations remain valid. |
| Reference input handoff | `Stdin_parser` emits typed events. `Input_coordinator` and `Event_queue` are explicit OCaml adapters. Backpressure and coalescing require tests for order, replacement position, multiplicity, ownership, and handoff behavior. |
| `RenderContext` / renderer reference | Explicit render-context capabilities retained by nodes; Eio capabilities remain at runtime/platform boundaries. |
| Terminal capability snapshot and response | `Terminal_capabilities.t` is a copied Core value populated through `opentui-raw`; `Lib.Terminal_capability_detection` filters parser responses before synchronous renderer updates and shared notifications. |
| Reference `RGBA` intent | `Lib.Rgba` is a pure intent-preserving value; `Color` is the separate raw-backed drawing bridge. |
| Reference native span feed | `Native_span_feed` remains a synchronous copy-first wrapper for the public span API, and is also the renderer-owned feed lifetime seam for `Renderer.Output.Sink`; complete copied spans are delivered to the sink before `Renderer.render` returns. The reference async data/error/backpressure/idle surface is not exposed. |
| Reference text editor state | `Edit_buffer`, `Editor_view`, `Lib.Extmarks`, and `Syntax_style` are small composed domain modules; they do not inherit from renderables. |
| Reference editor controls | `Edit_buffer_renderable` owns the edit/view/native-text synchronization; `Textarea` and `Input` add typed focus, placeholder, constraint, submit, and change contracts. |
| Reference scrolling controls | `Scroll_box` owns the physical wrapper/viewport/content subtree and composes `Scroll_bar` and `Slider`; scroll acceleration remains a policy value rather than a hidden scheduler. |
| Reference selection controls | `Select` and `Tab_select` use typed option records, directional keymaps, owner-local selection/item event channels, and the active optional ASCII-font composition path. |
| Reference terminal palette and geometry services | `Lib.Terminal_palette` parses/normalizes palette responses and `Render_context` owns current palette, pixel resolution, and transport-neutral `Lib.Render_geometry`; split-footer output/replay and actual terminal I/O remain outside Core. |
| Reference `Slider` renderable | `Renderables.Slider` composes a normal `Renderable.t` with typed value state and event channels. |
| Reference `OptimizedBuffer` ownership | `Owned_buffer.t` owns standalone native storage; `Buffer.t` remains the borrowed renderer-surface view. Framebuffer/font/table renderables compose the two through checked draw seams. |
| Reference ASCII font assets and renderable | `Ascii_font_spec` and generated `Lib.Ascii_font_data` provide typed measurement/raster helpers; `Renderables.Ascii_font` owns its retained framebuffer and translates JavaScript UTF-16 indexing to OCaml Unicode-codepoint indexing. |
| Reference line-number and timing renderables | `Renderables.Line_number` consumes unified `Line_info` providers and owns only its internal gutter; `Renderables.Time_to_first_draw` records a monotonic first-draw timestamp. |
| Reference `TextTable` and width helper | `Renderables.Text_table` owns native cell views plus one retained table identity, applies typed per-column alignment, and keeps aligned selection coordinates in cell-local space; `Text_table_width` implements the deterministic water-fill allocator. Markdown pipe-table alignment propagation is an OCaml extension, not reference `TextTable` behavior. |
| Reference composition VNodes | `Renderables.Composition.Vnode` is an inert typed description. Instantiation attaches ordinary `Renderable.t` identities, so composition does not create a competing runtime tree; `V_renderable` supplies typed drawing callbacks, while `Constructs` includes Code and typed styled-text conveniences. |
| Reference parser-backed content | `Renderables.Code`, `Renderables.Diff`, and `Renderables.Markdown` compose the existing text/style/line-number seams. Markdown's parsed pipe-table alignment propagation is an OCaml extension; Diff's styling surface is narrower than the reference's full mutable option set. `Lib.Tree_sitter_client` accepts typed parser functions and leaves per-Code generation/coalescing to the consumer; `Code` optionally uses the owner-bound Eio background executor for `Worker_safe` parsers. `Tree_sitter_styled_text`, `Detect_links`, and `Hast_styled_text` are typed conversion utilities. |
| Reference utility singletons and host services | Owner composition in `Renderer`, `Render_context`, `Data_paths`, `Env`, `Clipboard`, `Output_capture`, `Stdin_parser`, and `Renderer_theme_mode`; injected clocks, schedulers, and sinks carry effects without a process-global singleton. `Clipboard` is a synchronous injected policy seam, not the reference asynchronous native host service. |
| Reference JavaScript/Bun/Node/WASM loaders | Translated/non-applicable platform mechanisms. Typed parser, filesystem, terminal, and raw-ABI capabilities are injected by the Eio-native application boundary. |
| `requestRender()` | Dirty-state invalidation plus a coalesced future-frame request, distinct from an explicit renderer frame/presentation operation. |

Each non-literal translation must have a corresponding source-map path and
architecture or feature documentation. The documentation must state the
ownership invariant and observable test behavior. The source map remains
path-oriented; detailed adapter and decomposition rationale belongs in the
longer documentation.

## Major feature records

Cross-cutting contracts are recorded under
[`docs/major-features/`](major-features/). The directory separates in-progress
and implemented features. Each feature record has one active `feature.md`
document and may have non-normative context records alongside it.

The [event-system feature record](major-features/in-progress/event-system/feature.md)
defines the typed channel, renderer-context, lifecycle, keyboard, pointer, and
input-boundary relationships that the translation table summarizes.

The [renderable-core feature record](major-features/in-progress/renderable-core/feature.md)
defines the retained tree, renderer, render context, buffer, Yoga ownership,
and concrete Box and Text relationships.

The interactive controls in this tranche remain on that same retained tree:
the editor controls compose the pure edit/view state with native text
rendering, while scrolling and selection controls compose ordinary renderable
children with typed event channels. Their scheduler-dependent repeat and
auto-scroll behavior is owned by the renderer context: ScrollBar uses
cancel-safe clock chains and ScrollBox uses a guarded live contribution for
frame updates.

The [core source mirror feature record](major-features/in-progress/core-source-mirror/feature.md)
defines the complete `core/src` inventory, correspondence statuses, directory
placement rules, explicit exclusions, and non-applicable platform translations.

The specialized dispatch contracts are recorded separately in the
[keyboard-dispatch feature record](major-features/in-progress/keyboard-dispatch/feature.md)
and the
[pointer-dispatch feature record](major-features/in-progress/pointer-dispatch/feature.md).

The [background feature record](major-features/in-progress/background/feature.md)
defines the application-owned Eio executor pool used for selected CPU-heavy
work. `Platform.Eio_runtime.Background` binds submissions to an owner domain
and Eio switch, runs only an explicitly worker-safe work closure over owned
snapshots on a reusable executor domain, and returns completion to the owner.
Its generic closure type is not an arbitrary-OCaml-closure safety guarantee.
Tree-sitter-backed `Code` uses that
boundary for explicitly `Worker_safe` parsers, with per-Code generations,
coalesced latest snapshots, and owner-domain conversion/application; Markdown,
Diff, and composition constructors only propagate the capability to their Code
children. It does not make retained or native state concurrently mutable.

The [scheduler feature record](major-features/in-progress/scheduler/feature.md)
defines the separate renderer-owned Eio clock, timer, render-request wakeup,
and paced frame loop. Scheduler callbacks remain on the renderer domain and do
not use the background executor pool.

## Contribution workflow

The detailed translation rules, semantic decision checklist, and feature-porting
playbook are in [`CONTRIBUTING.md`](../CONTRIBUTING.md). The short workflow
below identifies the repository records that every implementation must update.

For a new feature:

1. Locate the analogous path under `vendor/opentui/packages`.
2. Place a core implementation under the corresponding `opentui-core/src`
   directory, unless the feature is an ABI adapter owned by `opentui-raw`.
3. Add or update its row in the [source correspondence map](upstream-map.md).
4. Add a behavior test under the owning package's `test/` directory and,
   where the behavior is comparable, a reference comparison under the core
   package's `reference/` directory.
5. Record any change in ownership, effects, events, or class-to-module
   translation.

The map marks only explicit exclusions, non-applicable platform mechanisms, or
separate packages that do not belong to this terminal-only OCaml library.
Those entries do not require placeholder modules.
