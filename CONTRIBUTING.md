# Contributing: Porting OpenTUI to OCaml

This repository ports the terminal UI library in <code>vendor/opentui</code> to
OCaml. The checked-out reference source defines the behavior and source
correspondence to preserve; its pinned revision and native build requirements
are recorded in [<code>vendor/README.md</code>](vendor/README.md).

The port has two goals:

1. A contributor who finds a feature in the reference repository should be
   able to find the corresponding OCaml feature by following the same package
   and source directory.
2. The OCaml feature should make the same observable semantic choices as the
   reference feature: ordering, ownership, limits, timing, error behavior,
   and lifecycle. TypeScript syntax, JavaScript inheritance, and Node.js I/O
   are translated where OCaml and Eio require different mechanisms.

This document is the working guide for that translation. The
[source correspondence map](docs/upstream-map.md) is the path index, and
the [architecture document](docs/architecture.md) defines the package and
effect boundaries. Cross-cutting feature contracts are indexed in
[`docs/major-features/`](docs/major-features/). If a reference path is not in
the map, add it before or with the implementation.

## The porting rule

Mirror the reference contract and ownership boundaries first. Preserve source
correspondence where practical, but do not treat the TypeScript decomposition
as the contract.

For every feature, preserve this relationship:

    reference package/path  ->  OCaml package/path  ->  same observable contract

The source path is part of the contributor interface and is the default
placement. Do not move a feature merely because a general-purpose module would
be convenient. An intentional split or move is appropriate when it gives a
clearer ownership, typing, or effect boundary. Keep the reference directory
name where practical, use the lowercase, underscore-separated OCaml filename
when the language requires a different filename, and record material source
placement in [<code>docs/upstream-map.md</code>](docs/upstream-map.md).

The reference implementation is not a line-by-line OCaml template. It is the
behavioral and architectural reference. A necessary translation may replace
class inheritance with composition, an event emitter with owner-local typed
event channels, or JavaScript scheduling with Eio. An OCaml implementation may
also decompose a
reference component differently when that gives a clearer ownership, typing,
or effect boundary. Such a translation must retain the ownership, ordering,
lifetime, and error behavior that callers can observe. Name the decomposition
difference in the architecture or feature documentation and demonstrate
equivalence with behavior tests or a differential comparison when the
reference behavior is executable.

Do not add placeholder modules for features marked <code>deferred</code>. A
deferred feature has a map entry and no speculative API until its contract and
package owner are defined.

## Where a feature belongs

Use the following placement rules before creating a file.

| Reference location | OCaml location | Placement rule |
| --- | --- | --- |
| <code>vendor/opentui/packages/core/src/&lt;path&gt;</code> | <code>packages/opentui-core/src/&lt;path&gt;</code> | Preserve the source subdirectory by default. A deliberate split across modules or an explicitly mapped platform boundary is allowed when its ownership and observable contract are documented. |
| <code>vendor/opentui/packages/core/src/zig</code>, <code>buffer.ts</code>, or <code>NativeSpanFeed.ts</code> | <code>packages/opentui-raw</code> | Keep ABI calls, native pointers, handle validation, and foreign lifetimes below <code>opentui-core</code>. |
| Reference core tests | <code>packages/opentui-core/test</code> | Keep tests with the package they validate. Use the reference path in the test name or source-map row when the Dune layout differs. |
| Reference examples for the core API | <code>packages/opentui-core/examples</code> | Keep executable examples with the API they demonstrate. |
| Reference core benchmarks | <code>packages/opentui-core/bench</code> | Keep workloads, allocation checks, and tracing entry points with the package they measure. |
| ABI and native-link tests | <code>packages/opentui-raw/test</code> | Test the foreign boundary where its handles and link rules are owned. |
| Cross-package architecture, mapping, and performance policy | repository root <code>docs/</code> and <code>future-performance.md</code> | Keep documents that describe both packages or the whole port at repository level. |
| Cross-cutting feature contract | <code>docs/major-features/&lt;status&gt;/&lt;feature&gt;/feature.md</code> | Keep one active contract with the feature; store historical discussions and discarded alternatives under that feature's <code>context/</code>. |

The package boundary is not a reason to lose source correspondence. It is the
explicit exception for the native seam: a reader following the reference
renderer into Zig should arrive at <code>opentui-raw</code>, while a reader
following a core renderable, parser, or platform module should arrive at the
analogous <code>packages/opentui-core/src</code> path.

## Major architectural translations

The following table is the short architectural map. The full path index is in
the [source correspondence map](docs/upstream-map.md).

| Reference feature | OCaml feature | Contract that must remain stable |
| --- | --- | --- |
| <code>core/src/Renderable.ts</code> | <code>docs/major-features/in-progress/renderable-core/feature.md</code>; target <code>packages/opentui-core/src/renderable.ml</code> and <code>packages/opentui-core/src/renderables/</code> | Nodes have stable identity, parent/child order, dirty state, layout participation, and explicit, idempotent destruction. Public child operations are typed capabilities, not a universal <code>Renderable.add</code>. |
| <code>core/src/renderer.ts</code> | <code>docs/major-features/in-progress/renderable-core/feature.md</code>; target <code>packages/opentui-core/src/renderer.ml</code> and <code>packages/opentui-core/src/platform/</code> | Keep invalidation, frame requests, explicit rendering, presentation, and any scheduler or output-backpressure policy distinct. Eio may replace the scheduling mechanism, but an explicit render boundary must not be described as the reference scheduler itself. |
| <code>core/src/types.ts</code> <code>RenderContext.requestRender</code> and renderer scheduling | <code>packages/opentui-core/src/render_context.ml</code> and renderer-owned coalesced request state | A mutation marks the retained tree dirty and records a coalesced future-frame request. An explicit frame/presentation operation is a separate immediate boundary, not the semantic replacement for <code>requestRender()</code>. The higher-level scheduler that consumes the request is still a separate integration boundary. |
| <code>core/src/yoga.ts</code> | <code>packages/opentui-core/src/yoga.ml</code> and <code>opentui-raw</code> Yoga bindings | Each retained renderable owns a private Yoga node. Parent insert/remove do not free the child; destruction frees that one node. Layout is calculated before readback. |
| <code>core/src/buffer.ts</code> | <code>packages/opentui-core/src/buffer.ml</code> over <code>packages/opentui-raw/buffer.ml</code> | Native cell storage stays native. The public OCaml layer does not invent a second cell grid with different copying or lifetime rules. Renderer current/next buffers are borrowed views. |
| <code>core/src/lib/border.ts</code> | <code>packages/opentui-core/src/lib/border.ml</code> | Border styles, side normalization, border code-point arrays, and packed draw flags remain one core-owned vocabulary above the raw buffer ABI. |
| <code>core/src/NativeSpanFeed.ts</code> | <code>packages/opentui-raw/span_feed.ml</code> | Borrowed native spans are never exposed without a lifetime proof. The OCaml boundary copies drained payloads and makes release, reservation, commit, and cancel explicit. |
| <code>core/src/lib/stdin-parser.ts</code> | <code>packages/opentui-core/src/lib/stdin_parser.ml</code> | The parser frames arbitrary input chunks and emits typed key, mouse, paste, and response events with owned byte payloads. |
| <code>core/src/lib/parse.keypress.ts</code> | <code>packages/opentui-core/src/lib/key_decoder.ml</code> | The helper recognizes complete key frames for <code>Stdin_parser</code>; unsupported or malformed frames remain responses. |
| <code>core/src/lib/parse.mouse.ts</code> | <code>packages/opentui-core/src/lib/mouse_decoder.ml</code> | The helper recognizes SGR and X10 frames; <code>Stdin_parser</code> owns mouse-button state and emits coordinates, modifiers, and move/drag classification. |
| <code>core/src/lib/queue.ts</code> | <code>deferred</code> | The reference <code>ProcessQueue</code> is an unbounded FIFO microtask work queue. It is not the parser byte queue or the OCaml event handoff; do not add a placeholder module while its port is deferred. |
| Private <code>ByteQueue</code> in <code>core/src/lib/stdin-parser.ts</code> | <code>packages/opentui-core/src/lib/byte_queue.ml</code> | The parser's pending-prefix storage keeps its bounded capacity, growth, compaction, and copy semantics. |
| OCaml input handoff with no direct reference file | <code>packages/opentui-core/src/lib/input_coordinator.ml</code> and <code>packages/opentui-core/src/lib/event_queue.ml</code> | These adapters receive typed events from <code>Stdin_parser</code>, retain the claimed event order, and never turn backpressure into loss. |
| <code>core/src/lib/KeyHandler.ts</code> (<code>KeyHandler</code> and <code>InternalKeyHandler</code>) | <code>docs/major-features/in-progress/keyboard-dispatch/feature.md</code>; <code>packages/opentui-core/src/lib/key_handler.ml</code> | <code>Lib.Key_handler</code> replaces <code>EventEmitter</code> mechanics while preserving global-before-local dispatch, prevention, propagation, snapshot iteration, cleanup, and handler-error reporting. Kitty press/repeat/release distinctions and their metadata are decoded at the parser boundary; malformed frames and future protocol extensions remain parser work. |
| Reference renderable and renderer pointer dispatch | <code>docs/major-features/in-progress/pointer-dispatch/feature.md</code> and <code>docs/major-features/in-progress/native-hit-grid/feature.md</code>; <code>packages/opentui-core/src/renderer.ml</code>, <code>packages/opentui-core/src/render_context.ml</code>, and <code>packages/opentui-core/src/renderable.ml</code> | <code>Renderer.handle_input</code> uses the native renderer's committed layout hit grid and routes typed mouse events through the retained tree. Hover, capture, derived drag/drop, focus-on-down, selection, and handler-error policy are renderer-owned; native storage, clipping, commit, and lookup remain below the typed raw capability. |
| <code>core/src/platform/*</code> | <code>packages/opentui-core/src/platform</code> | The reference platform directory contains runtime, FFI, worker, and asset support. The OCaml package splits Eio flow logic from Unix terminal setup into <code>eio_runtime</code> and <code>eio_unix_runtime</code>; the map records this as an OCaml-specific boundary rather than inventing reference subdirectories. |
| <code>core/src/testing</code>, <code>core/src/tests</code>, and <code>core/src/benchmark</code> | <code>packages/opentui-core/test</code>, <code>packages/opentui-core/reference</code>, and <code>packages/opentui-core/bench</code> | Behavior checks, reference comparisons, and performance workloads remain package-local and discoverable beside the implementation. |
| <code>packages/react</code> and <code>packages/solid</code> | No OCaml package selected | Any future reactive bridge must update the existing retained tree. It must not introduce a second required render tree or change the imperative core contract. |

The reference <code>StdinParser</code> is the typed-event boundary. The OCaml
<code>Stdin_parser</code> has the same responsibility: it owns byte framing,
protocol recognition, key and mouse helper state, and typed key, mouse, paste,
and response event production. <code>Key_decoder</code> and
<code>Mouse_decoder</code> correspond to the reference parse helpers; they do
not form a required public two-stage pipeline. <code>Input_coordinator</code>
adds Eio deadlines and lossless sink backpressure after typed event production.
Differential vectors cover bytes, event kinds, order, ownership, and timing.

## Input and event flow

The input path has a fixed responsibility order:

    Eio source
      -> Input_flow reusable read buffer
      -> Input_coordinator (deadlines and lossless backpressure)
      -> Stdin_parser (framing and typed event production)
      -> caller-owned event sink or Event_queue
         (coordinator retains blocked events; Input_flow retains unread suffixes)
      -> application and retained-renderer dispatch

The output path has a corresponding boundary:

    retained-renderer mutations
      -> dirty/layout state
      -> Yoga calculation
      -> frame drawing
      -> native render status
      -> caller-owned output bytes
      -> Eio sink

Each stage has one job:

- <code>Stdin_parser</code> recognizes protocol boundaries, incomplete escape
  prefixes, bracketed paste, keys, mouse events, and opaque responses. It
  emits typed events and does not decide which renderable handles a key.
- <code>Key_decoder</code> and <code>Mouse_decoder</code> are parser helpers for
  complete frames. A helper must not consume bytes that the parser has not
  framed.
- <code>Input_coordinator</code> owns the blocked typed event and reports how
  many source bytes were accepted. <code>Full</code> means retry later; it does
  not mean discard.
- <code>Platform.Eio_runtime.Input_flow</code> retries unread input before
  reading a new chunk. This is the backpressure point that prevents user input
  from being lost while the consumer is full.
- <code>Event_queue</code> is a caller-owned FIFO handoff. Its default capacity
  is 64; pending resize and mouse-motion events may replace an event of the same
  coalescing class. Keys, paste, responses, button events, and scroll events are
  not coalesced and report <code>Full</code> instead of being dropped.
- Pointer input decoded by <code>Stdin_parser</code> reaches
  <code>Renderer.handle_input</code>, which hit-tests the native renderer's
  committed layout grid and routes typed mouse events from the target toward
  the root. A handler may stop that route; otherwise dispatch continues.
  Hover, capture, focus-on-down, and derived drag/drop policy belong to the
  renderer, while selection remains renderer/renderable policy and native
  hit-grid storage is specified by the <code>native-hit-grid</code> feature.
- <code>Renderer</code> frame and presentation operations do not start fibers.
  The application may choose when to drain events and when to present a frame.
  Do not describe that explicit presentation as the equivalent of reference
  <code>requestRender()</code>; a scheduler above it must own invalidation,
  coalescing, timing, and retry semantics.

When porting another event family, inspect the reference dispatch code and
tests for the exact priority. Do not infer priority from the variant order or
from the order in which callbacks were registered. Record answers to these
questions in the feature's test and map entry:

| Question | Required decision |
| --- | --- |
| Which event is delivered first? | Preserve reference FIFO and explicit priority. |
| Which events may be coalesced? | Preserve the reference class and replacement position. Never coalesce text input, paste, button, scroll, or opaque protocol data without a reference-equivalent rule. |
| What does <code>preventDefault</code> do? | Stop the same downstream default action as the reference, while preserving any earlier handlers that already ran. |
| What does propagation stop? | Stop the same listener scopes and no others. |
| What happens when a sink is full? | Apply backpressure and retain the blocked event. Do not read more input if doing so could overwrite or lose it. |
| What is cleaned up, and when? | Tie registrations and state to the owning renderer, runtime switch, or decoder; destroy/close must make later use fail in the documented way. |

## Semantic decisions are part of the port

Performance concerns do not justify silently changing a reference policy. When
the reference answers one of the following questions, use that answer unless
the OCaml runtime makes the mechanism impossible. If a different boundary is
necessary, document the difference and preserve its observable safety
property.

### Queues

First identify which reference queue is being ported. OpenTUI has more than
one queue-like structure: <code>ProcessQueue</code> is a FIFO asynchronous work
queue, while the stdin parser has bounded pending bytes and an emitted-event
list. They do not have the same overflow policy.

For a queue, record:

- bounded or unbounded status;
- initial capacity, maximum capacity, and growth rule;
- FIFO or priority ordering;
- whether replacement occurs in place or at the tail;
- which event classes may be coalesced;
- whether a full queue blocks, returns an error, or drops a value; and
- who owns an item while it waits.

The reference parser uses a 256-byte initial pending buffer, grows up to a
64 KiB pending-prefix limit, and uses a 20 ms timeout for an incomplete escape
prefix. The OCaml <code>Byte_queue</code> and <code>Stdin_parser</code> keep
those parser values. <code>Input_coordinator</code> retains a blocked typed
event, while <code>Platform.Eio_runtime.Input_flow</code> retains the unread
source suffix and retries it when a downstream sink reports <code>Full</code>.
A bracketed paste is
accumulated in chunks outside the pending-prefix queue and emitted as one
owned payload, so the 64 KiB pending-prefix limit does not truncate a large
paste. Paste contents are not event-coalescing material and must not be
dropped to enforce a newly invented whole-paste limit.

These are standalone parser defaults, not necessarily the effective defaults
at an integration boundary. In the pinned reference, <code>CliRenderer</code>
constructs the parser with a 64 MiB pending-prefix limit while the parser's own
default remains 64 KiB. Record component defaults and enclosing renderer or
runtime overrides separately, and test the effective public configuration.

The bounded OCaml <code>Event_queue</code> is a handoff boundary, not permission
to lose input. Its capacity and coalescing policy are part of its interface. If
a new producer cannot make progress, it must return or await backpressure at
the boundary that owns the queue. Do not “solve” growth by dropping the oldest
event, truncating a paste, or treating a full queue as success.

<code>Event_queue</code> is an OCaml adapter, not a replacement for the
reference <code>ProcessQueue</code> or for the reference renderer's immediate
dispatch loop. Because it coalesces resize and pointer-motion events, it is not
automatically transparent. Tests for an integration that claims reference
equivalence must compare event order, replacement position, non-coalesced event
multiplicity, blocked-event ownership, and the observable handoff timing. If
the adapter intentionally changes one of those properties, state that as an
OCaml boundary instead of calling it a direct correspondence.

### Buffers and copies

For every byte buffer, state all four properties:

1. who allocates it;
2. who may mutate it;
3. when its contents become invalid; and
4. whether a consumer receives a copy, a borrowed view, or a reusable staging
   area.

The input path uses a reusable 4096-byte Eio read buffer, copies
accepted bytes into bounded parser storage, and emits owned <code>bytes</code>
values. The raw span-feed boundary copies drained native payloads and uses
explicit release tokens. These are correctness boundaries. Do not replace them
with Bigarray or Cstruct views merely to remove a copy; a zero-copy change
requires an ownership proof, an invalidation rule, and a measurement. Candidates
belong in [<code>future-performance.md</code>](future-performance.md) until that
contract is implemented.

### Timing and scheduling

Preserve whether work is synchronous, deferred to a microtask, scheduled at a
frame boundary, or driven by a timer. In OCaml:

- keep parser, decoder, Yoga, renderable mutation, and native frame operations
  synchronous;
- use Eio fibers and clocks for terminal I/O, deadlines, cancellation, and
  resource cleanup;
- keep dirty-state invalidation and a coalesced future-frame request separate
  from an explicit <code>flush</code>, <code>render_now</code>, or
  <code>present</code> operation;
- do not create a hidden fiber or implicit application loop inside a pure
  module.

The 20 ms escape timeout is a protocol decision, not an arbitrary scheduler
default. A replacement clock must be injectable so tests can exercise the
same deadline without sleeping.

The pinned reference renderer has separate continuous-rendering and immediate
rerender policies: <code>targetFps</code> defaults to 30 and
<code>maxFps</code> defaults to 60. Its <code>requestRender()</code> coalesces
requests, respects renderer control state, avoids competing with an in-flight
frame or output-feed retry, and schedules the next attempt according to those
policies. Preserve those observable choices when porting the scheduler, even
if Eio replaces process ticks and JavaScript timers.

### Rendering and layout

The retained tree is a stateful owner, not a transient value graph. A property
setter must update the existing node, maintain the same dirty/layout
invalidation behavior, and preserve child order and identity. A mutation
requests a future frame; it does not itself imply immediate presentation. An
explicit renderer frame/presentation operation is a separate immediate
boundary. A frame follows the reference order: apply pending state, calculate
layout when required, draw the retained tree, present the native frame, and
report the render status.

If a native render fails, keep the tree dirty when the reference permits a
retry. If a render is <code>Skipped</code>, preserve the distinction between
an unchanged frame and <code>Failed</code>; callers may use those statuses to
decide whether to schedule another frame.

## TypeScript and JavaScript patterns in OCaml

Use the smallest OCaml mechanism that preserves the reference relationship.

| Reference pattern | OCaml translation | Review for |
| --- | --- | --- |
| Base class and subclass | A retained <code>Renderable.t</code> owns identity, tree ownership, lifecycle, and private behavior hooks. Concrete renderable modules compose typed state and a preallocated behavior record. | Stable identity, parent ownership, child order, one invalidation path, replacement semantics at virtual-method boundaries, and idempotent destruction. Do not use a closed <code>Box \| Text</code> variant, <code>Obj</code>, or a per-frame dispatch table. |
| Constructor options object | Labelled arguments; a typed record only when the option group is reused or has a meaningful invariant. | Defaults, required values, validation, and distinction between omitted and explicit values. |
| Mutable public property | Typed accessor and setter preserving the reference validation, clamping, equality/no-op, invalidation, and error behavior. Use <code>result</code> when the corresponding failure is part of the public contract or an explicitly documented OCaml boundary. | Dirty/layout/render-list invalidation and whether equal values avoid unnecessary work. |
| <code>EventEmitter</code> | Owner-local typed event channels composed into the renderer, render context, or component. | Synchronous registration-order dispatch, snapshot semantics, reentrancy, duplicate subscriptions, one-shot removal, callback exceptions, cleanup, and producer-owned scheduling. Keyboard priority, pointer propagation, queueing, and backpressure remain separate dispatch systems. |
| <code>null</code> or <code>undefined</code> | <code>option</code> for absence; a result or explicit variant when absence is an error or state. | Do not collapse “not supplied,” “cleared,” and “invalid.” |
| <code>Promise</code>, microtask, or timer | Eio fiber, switch, clock, or deadline at the platform edge. | Cancellation, exception propagation, resource ownership, and whether the reference is actually asynchronous. |
| <code>Uint8Array</code>, <code>Buffer</code>, or native pointer | <code>bytes</code>, Bigarray/Cstruct, or an abstract raw owner chosen by the lifetime contract. | Copy/borrow semantics, mutation, empty values, bounds, and close invalidation. |
| <code>Map</code> or <code>Set</code> | A typed map/set or an array/queue selected for the reference access and ordering pattern. | Insertion order, duplicate behavior, mutation during iteration, and hot-path allocation. |
| Global registry or numeric handle | An owner-scoped abstract type and, at the ABI boundary, generation-checked tokens. | Cross-owner use, stale values, close order, and whether the numeric representation leaks. |
| Catch-all exception handling | Structured errors at input/config/resource boundaries; callback exceptions may propagate when the API says they do. | Unexpected failures must not be converted into success or silently discarded. |
| <code>RenderContext</code> / renderer reference | Explicit render-context capabilities retained by nodes; Eio capabilities remain at runtime/platform boundaries. | Preserve the explicit context parameter and keep parent/tree ownership separate from runtime capabilities. |
| <code>requestRender()</code> | Dirty-state invalidation plus a coalesced future-frame request; distinct from an explicit renderer frame/presentation operation. | Preserve continuous versus immediate scheduling, throttling, in-flight coalescing, output backpressure, cancellation, and control-state behavior. |

Do not introduce a manager, registry, wrapper, or compatibility layer merely to
make a dynamic pattern look familiar. First try a narrow module and explicit
composition. A new abstraction must own a real invariant and have a reference
path or a documented OCaml boundary that explains why it exists.

## A feature-porting playbook

### 1. Locate the reference contract

Start with the exact file or directory under <code>vendor/opentui/packages</code>.

- Read the implementation and its nearest tests together.
- Read the package README or development notes if they define lifecycle or
  configuration.
- Read the benchmark when the feature is on a frame, parser, or allocation
  hot path.
- Search the renderer and callers for dispatch order, cleanup, and error
  handling; a local file rarely contains the whole contract.
- Find or add the corresponding row in <code>docs/upstream-map.md</code>.

Tests are behavioral evidence, not only regression protection. A reference
test that checks a sequence split across two reads, a full queue, a destroyed
node, or an insufficient output buffer is specifying a contract that the
OCaml port must preserve.

### 2. Write down the semantic decisions

Before implementation, fill out this short record in the change description
or the feature documentation:

    Reference path:
    OCaml path:
    Reference inputs and outputs:
    Reference ownership and lifetime:
    Reference ordering, priority, and cleanup:
    Reference component and integration limits, defaults, and timing:
    OCaml representation:
    Necessary language/runtime difference:
    Invariant preserved by the difference:
    Behavior tests or reference comparison:
    Performance workload, if applicable:

The “necessary difference” must name the observable invariant it preserves.
“OCaml style” or “fewer allocations” is not sufficient by itself. An internal
decomposition difference may be intentional when it gives a clearer ownership,
typing, or effect boundary, but it still needs behavior evidence. If the
answer is not known, leave the feature deferred rather than inventing a policy.

### 3. Place the narrowest owning module

Use the reference directory as the default location. Keep pure protocol or
rendering logic independent of Eio. Put Eio resource acquisition, blocking
reads/writes, clocks, cancellation, and terminal setup under
<code>packages/opentui-core/src/platform/eio_runtime</code> or
<code>packages/opentui-core/src/platform/eio_unix_runtime</code>.

Put ABI calls and native lifetime code in <code>opentui-raw</code>. Do not make
<code>opentui-core</code> know about C pointers, packed native handle bits, or
callback calling conventions. Do not make <code>opentui-raw</code> know about
retained-rendering ownership, widgets, or terminal policy.

### 4. Implement ownership before convenience behavior

Define the owner and close path before adding optional features:

- what creates the value;
- what may retain it;
- what invalidates it;
- what happens to children and pending callbacks on destruction;
- which operations return an error after close; and
- whether a callback runs synchronously or later.

Then implement the smallest behaviorally complete slice. Keep a feature
visible as <code>deferred</code> in the map rather than exposing a partial
convenience API that suggests unsupported semantics.

### 5. Test at the owning boundary

Add the primary behavior test under the owning package:

- parser and decoder tests exercise arbitrary input chunking, timeout flush,
  malformed/unknown sequences, paste preservation, and event order;
- queue tests exercise capacity, coalescing, full delivery, retry, and
  ownership of blocked events;
- retained-renderable tests exercise identity, child order, dirty state, layout,
  destruction, hit-testing, and propagation;
- raw tests exercise ABI layouts, stale handles, close order, copied spans,
  and native-link behavior;
- Eio tests exercise partial reads/writes, cancellation, cleanup, and
  backpressure without requiring a real terminal unless the test is explicitly
  host-gated.

When the reference behavior is executable in both implementations, add or
update a comparison under <code>packages/opentui-core/reference</code>. Keep the
shared vectors and comparison command beside that package. A comparison may
cover a smaller OCaml feature subset, but the difference must be stated rather
than silently ignored.

### 6. Update the map and handoff docs

The source-map row should identify the reference path and the OCaml destination.
Keep the map path-oriented. Explain a deliberate adapter or decomposition in
the architecture or feature documentation: name the reference boundary it
translates and the ownership and observable-behavior invariants it must
preserve. Update architecture documentation when the package owner, effect
boundary, or translation rule changes. Update the package README when a
user-facing module or package-local tool becomes available. Avoid development
chronology such as “initial” or “next”; describe what exists and what it
guarantees.

For a cross-cutting feature, create or update the matching record under
[`docs/major-features/`](docs/major-features/). Keep `feature.md` declarative
and present-tense. Store design discussions, rejected alternatives, and older
wording under the feature's `context/` directory. The context is evidence, not
the active contract.

## Review checklist

Before asking for review, verify the following.

- The reference file and the OCaml file have an explicit map entry.
- Tests, examples, comparisons, and benchmarks are in the owning package.
- The package dependency direction is still <code>opentui-core</code> to
  <code>opentui-raw</code>, never the reverse.
- No native pointer, packed handle, or foreign callback escaped the raw
  boundary.
- Queue boundedness, growth, event priority, and full behavior are stated.
- Input and paste bytes cannot be lost through an allocation or backpressure
  decision.
- Buffer copies, borrowed views, mutation, and invalidation are stated.
- Sync/async behavior and Eio resource ownership are stated.
- Invalidation, frame requests, presentation, and scheduling are not conflated.
- Node identity, dirty state, layout invalidation, and destruction match the
  reference feature.
- Destruction and close behavior are explicitly checked for idempotency.
- Errors at runtime boundaries are structured and unexpected exceptions are
  not hidden.
- A deferred feature has no speculative compatibility API.
- The source-map path and package documentation describe the resulting
  behavior without relying on undocumented context.

Use the repository's documented Dune commands from inside the Nix development
shell for validation. A docs-only change still needs link and Markdown review;
a code change also needs the owning package's behavior checks and any
applicable reference comparison or benchmark.
