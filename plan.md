# Implementation plan

This plan is ordered around reducing uncertainty at the native boundary before
adding framework ergonomics. A phase is complete only when its ownership and
observable behavior are recorded in `design.md` and its tests or measurements
support the relevant claim.

## Phase 0 — Repository foundation (complete)

- establish the Dune monorepo and package-management lock;
- provide reproducible Nix default/test shells and native Zig tooling;
- add CI on supported Linux and Apple Silicon macOS systems;
- pin the upstream OpenTUI source as `vendor/opentui`;
- record the package graph, constraints, and tentative decisions.

## Phase 1 — ABI/build seam and minimal native smoke (complete)

This is the first implementation gate. It intentionally proves a narrow,
memory-output renderer/buffer/event slice while establishing which state belongs
in Zig, which values may cross the ABI, and which runtime operations must be
serialized. Full terminal parsing, the public Yoga surface, native-owned span
views, and hard performance gates are follow-on work rather than prerequisites
for the first successful native link.

### Source and ABI audit

- map the upstream build entry points, Zig package dependencies, targets, and
  required system SDKs;
- inventory the native exports and group them into renderer, buffer, Yoga,
  terminal, event, output-feed, and deferred subsystems;
- compare the TypeScript FFI declarations with the Zig definitions without
  treating TypeScript types as an ABI specification;
- record the exact fixed-width types, `extern struct` layouts, enum values,
  booleans, pointer/length conventions, and status/error encodings;
- identify which functions return owned handles, renderer-owned borrowed
  children, raw pointers, borrowed spans, output buffers, or callback
  registrations;
- inspect destruction order, stale-handle behavior, callback reentrancy, and
  private renderer-thread behavior;
- record the native buffer SoA layout, renderer double-buffer/hit-grid model,
  Yoga pointer model, native span-feed contract, and TypeScript stdin-parser
  state machine in `design.md`;
- choose the first C ABI/build seam and document any facade needed to make the
  Zig exports safe for OCaml.

### Build/link gate

- record the exact Nix/Zig invocation, target, artifact name, and Dune link
  path for the pinned native library;
- account for the upstream dynamic-library shape, Yoga's C++ sources and
  standard-library link requirements, and any platform SDK libraries before
  choosing the root build rule;
- make the first artifact use the memory output backend with native threaded
  output disabled (`setUseThread` off);
- make the build fail clearly when the selected artifact or its ABI header is
  missing. A successful Zig build without a successful Dune link is not a
  completed Phase 1 seam.

### Data-structure decisions to settle before Phase 2

- use kind-specific abstract handle modules and an immediate OCaml-side handle
  representation where practical; keep the packed registry format private;
- keep OpenTUI's cell grid, hit grid, grapheme/link pools, renderer caches, and
  output span ring native;
- classify every cross-boundary buffer as synchronous-borrowed, reusable
  caller-owned, or native-owned-borrowed; do not expose a naked pointer or
  naked Bigarray from the raw package;
- use a reusable `Bigarray.Array1` byte buffer with one `Cstruct.t` view for
  terminal input and bounded scratch output; avoid a `Bytes`-to-`Cstruct`
  conversion in the read loop;
- keep Yoga nodes behind an owning native object or a generation-checked native
  wrapper; do not publish raw `YGNodeRef` values;
- specify stdin framing with a reusable byte queue and mutable parser state;
  implement it after the Phase 1 native smoke gate;
- define one native-owner UI fiber/domain, a bounded event handoff, and the
  policy for dropping/coalescing only high-rate motion events;
- use buffered memory for the first output smoke path. Treat
  `NativeSpanFeed`'s native-owned zero-copy lifetime/backpressure proof as
  Phase 2 work, after the initial ABI and link seam is real;
- before exposing span views or reservations, add native release/consumed and
  reservation-cancel operations. The current upstream surface has a
  `markSpanConsumed` method but no export and has reserve/commit without a
  cancel path;
- keep direct OptimizedBuffer views deferred because native resize reallocates
  its SoA arrays; choose scoped borrows, deferred reclamation, or snapshot copy
  only after a measured post-processing need;
- classify every future float-to-text use as protocol, snapshot, diagnostic, or
  display output; do not use generic `string_of_float` as an accidental wire
  format, and defer `dtoa` until a concrete OCaml-owned text boundary exists;
- use Eio only at the terminal/runtime boundary and avoid adding a general
  container or lock-free queue package without a measured need.

### First binding slice to prove

- load and link the selected native artifact from the root Dune workflow;
- create and destroy a memory-output renderer, obtain abstract current/next
  buffer handles, and prove the documented borrowed-buffer invalidation order;
- exercise a small set of batched buffer operations: clear, cell/text update,
  and caller-owned bounded resolved-character output. Raw `get*Ptr` access and
  native-owned cell views are explicitly deferred;
- create/destroy one event sink and copy one synchronous callback payload into
  an owned test packet;
- use native-threaded output off and keep all raw entrypoints on the one UI
  owner.

The first slice does not include the full stdin parser, terminal mode setup,
the public Yoga API, or `NativeSpanFeed` zero-copy reservations. Those are
audited in Phase 1 but implemented only after this smoke path has established
the build and ownership conventions.

### Phase 1 acceptance tests

- source inventory points to the relevant pinned files and names all deferred
  subsystems;
- Zig/C ABI declarations are checked against a generated header or equivalent
  compile-time probe rather than inferred from TypeScript alone;
- the Nix/Dune workflow produces and links the selected native artifact, with
  the required Yoga C++ and platform-library dependencies accounted for;
- create/destroy tests prove renderer-owned buffer handles become invalid in
  the documented order and stale handles do not resolve;
- invalid dimensions, oversized lengths, null/empty spans, and native failure
  statuses have deterministic OCaml results;
- native writes into caller-owned output storage are visible in OCaml without
  an intermediate string allocation;
- callback tests prove native bytes are copied before callback return and no
  arbitrary renderer call occurs from the callback;
- a small baseline records allocations and native-call counts for repeated
  buffer updates, without making an unmeasured allocation number a Phase 1
  correctness gate.

The following are deliberately deferred from this gate: chunk-shape-invariant
stdin parsing, Yoga layout readback and custom measurement, native-owned span
aliasing/release, reserve/commit/cancel, terminal integration, and a hard frame
allocation budget.

**Exit:** a reviewed ABI inventory, low-level ownership/scheduling decision,
build/link seam, and minimal smoke layer are checked in. An OCaml integration
test can create/destroy a memory-output renderer, use abstract buffer handles,
draw a cell or text span, write into caller-owned output storage, and observe a
copied callback payload without exposing raw pointers or requiring a second
external data-structure library.

**Exit record (2026-08-10):** The pinned revision is covered by
`packages/opentui-raw/native/ABI.md`, the source-importing Zig probe, and the
fixed-width C header. The root Dune workflow builds and links the ReleaseSafe
memory-output artifact with native threaded output disabled. The native smoke
proves renderer-owned buffer invalidation, deterministic invalid and empty
inputs, bounded output failure, synchronous callback copying, direct writes
into OCaml-owned bytes, and a non-gating repeated-update allocation baseline.
The packed `u32` handles remain confined to the test shim; the public
placeholder handle module and all higher-level layers remain unchanged.

## Phase 2 — Complete typed raw boundary and native protocol proofs

The first Phase 2 increment extends the typed raw facade with structured
status/error results, kind-specific renderer and borrowed-buffer domains,
caller-owned resolved-character output, a bounded copied event queue, owned
Yoga/layout tokens, copied terminal capability snapshots, and the
copy-first NativeSpanFeed ownership protocol. It stays in `opentui-raw`; native
zero-copy span views, terminal parsing, `opentui-native`, Lwd, and widgets
remain later layers.

- reuse the root development workflow and existing Dune/Zig artifact seam while
  extending the typed raw boundary for the host target;
- complete the minimal OCaml-oriented C-compatible facade: fixed-width
  booleans and lengths, explicit output structs, and typed status/error
  conversion rather than raw Zig `bool`, `usize`, or borrowed string fields;
- implement raw handle creation/destruction and status/error conversion for
  the selected renderer, buffer, and event domains;
- add the owned Yoga wrapper and exact layout output (the current upstream
  layout struct contains six `f32` values), without publishing `YGNodeRef`;
- add the capability facade with copied strings and fixed-width lengths;
- add native span-consumed/release and reservation-cancel operations, then
  prove copied payload release, reserve/commit, cancellation, and close
  behavior without exposing native pointers;
- test the complete native artifact independently of the UI framework.

**Current increment acceptance:** black-box tests create and close a Yoga tree,
read the six-field layout, reject invalid dimensions and cross-tree parents,
and observe owner invalidation. They process an XTVERSION response, verify
typed enum decoding, and observe copied terminal strings. They also drain a
copied output span, observe typed rendered/skipped/failed frame status, prove
release-driven chunk reuse, and exercise reservation
busy/cancel/commit behavior. No raw Yoga pointer, packed style value, native
span view, parser state, Lwd value, or widget API crosses this increment.

**Phase 2 exit:** an OCaml test can load/link the native artifact, create and
destroy renderer/buffer/layout resources, exercise the documented copy-first
output-feed ownership protocol, and prove that failure paths do not leak or
silently reuse an invalid handle. A native zero-copy view remains a separate
follow-on decision with its own lifetime and benchmark acceptance.

## Phase 3 — Native and terminal foundations

- build `opentui-native` around renderer, buffers, Yoga, native renderables,
  and frame lifecycle;
- build `opentui-terminal` around terminal mode transitions, input decoding,
  resize, capabilities, and output flushing;
- port only the input/event behavior needed by the native OCaml path;
- add deterministic byte-stream tests and pseudo-terminal integration tests;
- establish a frame loop that can run without Lwd or widgets.

**Exit:** a small imperative OCaml program can enter terminal mode, render a
known frame, receive an input/resize event, update a persistent native node,
flush the next frame, and restore terminal state on shutdown.

**First native increment:** `opentui-native.Renderer` now composes the raw
renderer behind an opaque single-owner frame token. `begin_frame` opens the
next native buffer, `Frame.clear`/`set_cell`/`draw_text` apply the basic raw
mutations, and `present` consumes the token while returning the typed native
render status. Native handles, raw buffer pointers, retained renderables,
Yoga composition, terminal modes, and output flushing remain outside this
increment.

**Terminal mouse increment:** `opentui-terminal.Mouse_decoder` now composes
above complete framing events without importing the renderer. It decodes the
pinned SGR and X10 mouse encodings, retains high X10 coordinate bytes, tracks
SGR pressed buttons for drag classification, and returns no event for
non-mouse or malformed frames. Terminal mode negotiation, timer coordination,
event dispatch, and output flushing remain outside this increment.

**Terminal mode increment:** `opentui-terminal.Terminal_modes` now represents
the pinned alternate-screen, cursor, mouse-tracking, and bracketed-paste
transitions without owning a writer. Every operation returns an owned ANSI
sequence and an immutable next state; a runtime can commit that state only
after its output sink accepts the sequence. Idempotence and reset ordering are
covered, while Eio flow ownership, raw-mode toggling, capability probes, and
event dispatch remain outside this increment.

**Input composition increment:** `opentui-terminal.Input_decoder` now tries
the stateful mouse decoder before the common key decoder and returns one typed
terminal event family while preserving copied opaque sequences and paste
payloads. Its reset boundary clears only mouse decoder state; timers, flow
reads, mode commits, output writes, and event dispatch remain outside this
increment.

## Phase 4 — Retained `opentui-core`

- define the retained scene/renderable model and ownership tree;
- connect Yoga/layout results to persistent native nodes;
- define event propagation, hit testing, focus, and teardown boundaries;
- batch native mutations before a controlled render flush;
- test that ordinary updates preserve node identity and do not recreate the
  native tree.

**Exit:** the imperative core supports a small static and interactive scene with
stable identities, deterministic teardown, and frame/update benchmarks.

## Phase 5 — Solid-like Lwd bindings

- add `opentui-lwd` over the retained core rather than over a rebuilt virtual
  tree;
- introduce mount/component scopes, cleanup, context, and keyed children;
- connect Lwd invalidation to a frame scheduler and batch boundary;
- add equality/cutoff policy for native property updates;
- measure allocation and frame behavior for signal updates, list changes, and
  event bursts;
- document the cases where an explicit mutable model is preferable to a
  reactive value.

**Exit:** a reactive example mounts once, updates only affected native state,
cleans up all resources, and meets an agreed allocation/frame budget under a
repeatable benchmark.

## Phase 6 — Widgets and application ergonomics

- add a small set of useful widgets over stable core contracts;
- define styling, focus, keyboard/mouse, scrolling, and accessibility-shaped
  conventions only as supported by the native core;
- provide examples that exercise both imperative and Lwd APIs;
- keep widget state and rendering allocations measurable.

**Exit:** examples are expressive without exposing raw handles or requiring
callers to manage native lifetime manually.

## Phase 7 — Portability, packaging, and upstream feedback

- test supported Linux and macOS targets, including terminal differences;
- add package-level documentation and installation examples;
- define the supported compiler/Zig matrix and submodule update procedure;
- upstream generally useful Zig fixes rather than accumulating a permanent
  private fork;
- publish only the packages whose ownership and ABI contracts are stable.

**Exit:** a clean checkout can reproduce the native build, run the integration
suite, and consume the stable packages without the JavaScript runtime.

## Immediate next tasks

Phase 1 is complete. The first typed Phase 2 increment now includes the owned
Yoga/layout, copied-capability, and copy-first output-feed boundaries described
above. The remaining implementation sequence is:

1. decide whether profiling justifies a separately scoped native chunk view;
2. add terminal timer coordination around the now-complete framing, input
   composition, semantic key/mouse, and mode layers; and
3. extend `opentui-native` with the smallest Yoga/renderable composition before
   adding terminal, core, Lwd, or widget layers.

The reusable stdin queue and framing parser are now implemented as
`opentui-terminal.Byte_queue` and `opentui-terminal.Stdin_parser`. Their
acceptance contract is a reusable `Bigarray.Array1`-backed queue that compacts
consumed prefixes before growing, enforces a configured maximum atomically,
preserves split UTF-8 and protocol units across pushes, flushes incomplete
prefixes only when the caller invokes `flush_timeout`, and copies paste/event
payloads before returning them. `Key_decoder` now composes above that framing
boundary for common semantic keys and copies its character/unknown/paste
payloads. `Mouse_decoder` now adds stateful SGR/X10 semantics while leaving
terminal output lifecycle outside this increment. `Terminal_modes` now adds
writer-free mode transitions without taking ownership of an output flow.
