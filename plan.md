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

**Terminal timer increment:** `opentui-terminal.Input_coordinator` now owns the
parser/decoder composition and exposes one caller-clocked deadline for an
incomplete prefix. `fire_timeout` flushes only when that deadline is due and
then drains typed events; Eio fibers, flow reads, output writes, mode commits,
and dispatch remain outside the package.

**Native layout increment:** `opentui-native.Layout` now owns a raw Yoga tree
and wraps its nodes in an owner-scoped opaque domain. Validated dimensions,
calculation direction, copied layout results, and close invalidation are
composed above `opentui-raw`; measure callbacks, packed styles, retained
renderables, terminal policy, and reactive layers remain outside this
increment.

**Native text-renderable increment:** `opentui-native.Text_renderable` now
owns one copied text value and holds one opaque owner-scoped layout-node
reference, adds a caller-supplied parent origin to the copied local layout
origin, and draws through a caller-owned imperative frame. Layout remains
responsible for node lifetime. Coordinate checks, layout close errors, frame
lifetime, and text ownership remain explicit; child trees, measure callbacks,
retained scene identity, terminal policy, and reactive layers remain outside
this increment.

**Native frame-loop increment:** `opentui-native.Renderer.run_frame` now
composes one caller-owned imperative frame from `begin_frame`, a
result-returning draw callback, and `present`. A structured draw error abandons
the active token and clears the pinned transparent default into the native next
buffer so the renderer remains reusable; callback exceptions receive the same
cleanup before being re-raised. Successful callbacks return the typed native
render status. The combinator does not own a loop, clock, terminal sink, event
dispatch, retained scene, or reactive layer.

**Native resize increment:** the audited `resizeRenderer` export now crosses
the raw C/Zig boundary with its pinned `u32, u32, u32 -> void` signature.
`opentui-raw.Renderer.resize` validates dimensions and preserves borrowed buffer
handles while the native buffers resize in place. `opentui-native.Renderer`
serializes resize against its imperative frame token. The pinned upstream
export still swallows native allocation failures; the raw facade verifies both
buffer dimensions after the call and reports an observable mismatch, while
hidden hit-grid or other internal failures remain outside the pinned ABI's
visibility.

**Native frame-output increment:** `opentui-native.Renderer.Frame` now exposes
bounded resolved-character output into caller-owned `bytes`. Its all-or-nothing
byte count and insufficient-capacity error remain explicit; callers must hand
an exact-sized value or the returned prefix to `Output_flow`. The runtime
package now exposes a checked subrange write for that prefix. The frame token
checks its lifetime before writing, while output flushing remains composed by
the caller; no sink, fiber, or frame manager is introduced at this layer.

**Eio flow increment:** `opentui-terminal-eio.Input_flow` now provides a
separate optional Eio/Cstruct boundary. It owns one reusable read buffer and a
character-typed Bigarray view over that same storage, maps one `single_read`
into the pure input coordinator without a second staging copy, stamps
deadlines from the caller's monotonic clock, exposes typed events and its
deadline, and maps explicit EOF/I/O failure. It does not create parser, timer,
dispatch, mode, or output fibers.

**Eio output increment:** `opentui-terminal-eio.Output_flow` now binds the
writer-free terminal mode transitions to a caller-owned Eio sink. It writes
transition bytes before committing the remembered mode state, exposes the same
synchronous sink for arbitrary frame bytes, and maps Eio I/O failures without
creating fibers or taking ownership of sink closure/restoration. Any I/O,
cancellation, or invalid-progress failure poisons the wrapper against retries
because the sink may contain only a prefix. The focused runtime smoke uses an
Eio pipe. A PTY smoke is host-gated and skips with an explicit reason because
this workspace does not expose `/dev/pts`; it remains runnable on a
PTY-capable Unix host.

**Terminal size increment:** `opentui-terminal.Terminal_size` now validates
positive externally supplied columns and rows and provides a copied immutable
value with explicit equality. It is the payload boundary for the bounded
resize-event handoff; it does not read terminal state, install signal
handlers, dispatch events, or depend on `opentui-native`.

**Bounded event-handoff increment:** `opentui-terminal.Event_queue` now owns a
pure bounded FIFO for decoded input events and externally supplied terminal
sizes. Lossless input reports `Full` rather than being silently dropped;
pending resize and mouse-motion (`Move`/`Drag`) values coalesce to their
latest payload while preserving the pending slot's position. The queue
allocates its ring once and does not own Eio fibers, signal sources, wakeups,
dispatch, or native resources. The runtime packages compose those policies
around this pure queue rather than moving Eio or process-global state into it.

**Push-driven input/backpressure increment:** `Input_coordinator` now offers
decoded events synchronously to a caller-owned sink instead of accumulating an
unbounded decoded-event queue. A sink that reports `Full` leaves the blocked
event owned by the coordinator and returns the exact accepted source prefix;
source processing is chunked at 4096 bytes so a large direct push cannot create
an unbounded transient event queue. `Input_flow` keeps an unread suffix in its
reusable Cstruct/Bigarray storage and returns `Backpressured count` without
reading again until the sink accepts earlier input; `count` is zero when no
new source read occurred. An `Event_queue` sink preserves
lossless key/paste/opaque/button/scroll events and applies only its documented
resize and pointer-motion coalescing. This replaces the old coordinator-to-
queue transfer helper; no fiber, wakeup, signal source, dispatcher, or output
ownership moved into either input layer.

**Eio wakeup and dispatch increment:** `opentui-terminal-eio.Wakeup` now owns
a single-domain revision condition. `Wakeup.push` notifies only after the
bounded queue accepts or coalesces an event, and
the caller's input sink can notify the same wakeup after its queue accepts an
event. `Dispatch.run` drains available events, snapshots the wakeup revision,
rechecks the queue, and only then waits; a producer cannot leave an event
behind while the dispatcher sleeps. The caller provides the fiber, switch, and
handler, and handler exceptions remain visible.

**PTY/native composition increment:** the host-gated
`test_native_terminal_pty` smoke now composes the caller-owned mode, input,
resize, native frame, and output seams through a Unix PTY. It verifies raw
termios entry/restoration, ANSI mode restoration, input transfer into
`Event_queue`, validated window sizes, native resize, and two frame flushes.
The test remains the acceptance boundary; signal sourcing and event dispatch
are covered separately so the PTY composition does not become a hidden
terminal manager.

**Unix terminal-size increment:** `opentui-terminal-eio-unix` now provides a
caller-invoked `Eio_unix` window-size probe. It copies positive columns and
rows into the pure `Terminal_size` value and maps OS query failures without
installing `SIGWINCH`, creating wakeups, pushing events, or owning a file
descriptor. The PTY smoke uses this probe before handing the size to
`Event_queue`.

**Unix resize-source increment:** `Resize_source` now installs at most one
process-global, single-domain `SIGWINCH` handler, refuses to replace a
non-default handler, coalesces pending signals into an Eio condition
notification, and restores the previous default/ignored behavior on close or
switch release. It does not query dimensions or push events; the caller waits, invokes
`Terminal_size_source.get`, and uses `Wakeup.push` for the bounded handoff.

**Terminal restoration increment:** `Terminal_session` now saves the exact
`Unix.terminal_io` record, enters a raw input configuration, and restores the
saved record plus the `Output_flow` ANSI state. Restoration attempts both
parts, retains successful component cleanup for retries, and reports a
structured combined error when both fail. A never-entered session performs no
ANSI write. The session never closes the caller's descriptor or sink; its
switch hook is a best-effort fallback, while explicit `restore` is the
observable cleanup operation.

**Phase 3 runtime-policy exit (2026-08-10):** the Eio wakeup/dispatch seam,
Unix resize source, and switch-scoped terminal restoration are now checked in
above the pure terminal queue and below any retained or reactive framework.
The PTY acceptance remains host-gated because this workspace has no
`/dev/pts`; the signal, wakeup, dispatcher, and structured non-terminal
boundaries run on the current host.

## Pre-Phase-4 performance and design review

The repository now has `bench/profile.exe`, a deliberately small
repeatable profile for 80x24 native frame updates, Eio input reads, and Eio
output writes. It reports monotonic elapsed nanoseconds and OCaml GC words;
the values are diagnostic baselines, not absolute host-independent gates.
The benchmark is kept below the retained core so it can measure the
imperative seams before identity and reactive scheduling are introduced.

The review removed the Eio input staging copy: one reusable Cstruct buffer and
one character-typed Bigarray view now feed the pure parser, which performs its
single ownership copy into the parser queue. The output boundary now has
`Output_flow.write_subbytes` with checked ranges, so native resolved-output
counts cannot accidentally flush undefined trailing scratch bytes.
`opentui-native.Color` is the caller-facing color module; raw color
representation remains behind the native package's private conversion.

The zero-copy and pooling ideas that may follow this review are recorded in
[`future-performance.md`](future-performance.md). They are intentionally a
deferred parking lot, not a Phase 4 prerequisite: the current copy-first
seams remain the reference while retained-core correctness is established.

The current host-local Dune release-profile run (`dune --profile release`)
was captured on 2026-08-10 with macOS 14.7.6 arm64, OCaml 5.5.0, Dune 3.23.1,
Zig 0.16.0, and the pinned OpenTUI revision
`de64d210e4f0163720fc1fbfa838d4d1aad47d53`:

```text
retained_text iterations=64 elapsed_ns=2352500 minor_words=0 major_words=0 minor_collections=0 major_collections=0
retained_layout iterations=128 elapsed_ns=4631541 minor_words=524281 major_words=196 minor_collections=2 major_collections=0
retained_reorder iterations=128 elapsed_ns=6752083 minor_words=524281 major_words=262 minor_collections=2 major_collections=0
retained_teardown iterations=64 elapsed_ns=3502125 minor_words=0 major_words=0 minor_collections=0 major_collections=0
frames iterations=64 elapsed_ns=7319250 minor_words=4718546 major_words=385 minor_collections=18 major_collections=0
input iterations=32768 elapsed_ns=3484791 minor_words=1048569 major_words=26039 minor_collections=4 major_collections=0
output iterations=4096 elapsed_ns=438959 minor_words=0 major_words=0 minor_collections=0 major_collections=0
```

The retained-core cases were repeated three times on that same macOS host.
Their elapsed ranges were 2,352,500–2,408,625 ns for retained text,
4,631,541–4,803,083 ns for retained layout, 6,608,792–6,898,417 ns for
retained reorder, and 3,502,125–3,602,250 ns for retained teardown. The
allocation and collection counters were stable across those runs; the ranges
are diagnostic rather than a hard gate.

These values are a diagnostic sample from one supported host, not a portable
performance gate. A second run on 2026-08-10 used the same compiler, Dune,
Zig, pinned OpenTUI revision, and benchmark parameters inside a 4-vCPU/8-GiB
Colima `aarch64-linux` VM (Linux 6.8.0-64-generic aarch64):

```text
retained_text iterations=64 elapsed_ns=6655593 minor_words=0 major_words=0 minor_collections=0 major_collections=0
retained_layout iterations=128 elapsed_ns=15551913 minor_words=524282 major_words=197 minor_collections=2 major_collections=0
retained_reorder iterations=128 elapsed_ns=7429516 minor_words=524282 major_words=263 minor_collections=2 major_collections=0
retained_teardown iterations=64 elapsed_ns=4525618 minor_words=0 major_words=0 minor_collections=0 major_collections=0
frames iterations=64 elapsed_ns=10307695 minor_words=4718547 major_words=386 minor_collections=18 major_collections=0
input iterations=32768 elapsed_ns=4131145 minor_words=1048570 major_words=26040 minor_collections=4 major_collections=0
output iterations=4096 elapsed_ns=2030240 minor_words=0 major_words=0 minor_collections=0 major_collections=0
```

The VM sample is useful for checking cross-host output scale and compiler
diagnostics, but it is not a direct hardware or operating-system comparison
with the macOS sample. The Linux build also exposed a GCC
`-Wmaybe-uninitialized` warning in the Yoga calculation shim; initializing the
validated dimensions before status checking removes that portability warning
without changing the accepted-argument path. An x86_64-linux comparison
remains open; future runs must keep the compiler, native revision, host, and
benchmark parameters visible alongside the values.

Native span-feed views, per-cell OCaml views, Lwd bindings, and widgets remain
intentionally deferred. They require separate ownership contracts or
measurements rather than being inferred from this baseline. The retained core
now keeps its dirty state after layout, drawing, or native-present errors;
parser invariant traps remain review items for the retained-frame contract and
are not silently widened into this performance pass.

## Phase 4 — Retained `opentui-core`

- define the retained scene/renderable model and ownership tree;
- connect Yoga/layout results to persistent native nodes;
- define event propagation, hit testing, focus, and teardown boundaries;
- batch native mutations before a controlled render flush;
- test that ordinary updates preserve node identity and do not recreate the
  native tree.

**Exit:** the imperative core supports a small static and interactive scene with
stable identities, deterministic teardown, and frame/update benchmarks.

**First retained-core increment (2026-08-10):** `opentui-core.Scene` now owns
one `opentui-native.Renderer` and one owner-scoped Yoga tree. Its persistent
container and text nodes have stable IDs, validated dimensions, dirty/layout
invalidation, layout-before-render traversal, caller-owned resolved output, and
recursive teardown. A controlled flush skips clean scenes, leaves failed
frames dirty, and does not own a terminal sink. Synthetic pointer events hit
the deepest laid-out node and bubble through parent handlers until `Stop`.
The increment intentionally does not include terminal-event adaptation, rich
Yoga styles, keyboard/focus policy, custom renderables, Lwd, or widgets.

**Child-ordering increment (2026-08-10):** the raw and native layout seams now
support moving an attached same-parent Yoga child to a final zero-based index
without freeing its native subtree. `opentui-core.Scene.Node.move_to_index`
keeps its retained child list synchronized with that native order, rejects
invalid/root moves without dirtying the scene, and leaves rendering deferred
until the existing controlled `flush` boundary. Black-box acceptance covers
layout order, stable identities, invalid-operation preservation, replacement
placement, nested descendant movement, pointer-hit retargeting, and teardown
after a move.

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

Phase 3 is complete and the first Phase 4 retained-core increment is now
checked in. The remaining implementation sequence is:

1. compare the checked-in profile across the supported compiler/native hosts,
   retaining the macOS sample as the reference and the aarch64-linux Colima
   sample as a caveated VM diagnostic; add x86_64-linux when a matching host
   is available;
2. run retained-core update benchmarks and keep expanding `opentui-core`
   acceptance around retained containers, layout changes, pointer propagation,
   and teardown without widening into terminal or reactive ownership; the
   optional pinned-reference behavior and contextual performance harnesses now
   cover terminal byte framing, while the Bun timing includes its typed-event
   normalization beyond the OCaml framing layer;
3. extend `opentui-native` only where a measured renderable contract remains
   missing; and
4. keep the deferred output, pooling, and native-view candidates in
   [`future-performance.md`](future-performance.md) until the core profile
   identifies a specific material hotspot, then design Lwd and widgets over
   the stable imperative boundary.

The reusable stdin queue and framing parser are now implemented as
`opentui-terminal.Byte_queue` and `opentui-terminal.Stdin_parser`. Their
acceptance contract is a reusable `Bigarray.Array1`-backed queue that compacts
consumed prefixes before growing, enforces a configured maximum atomically,
preserves split UTF-8 and protocol units across pushes, flushes incomplete
prefixes only when the caller invokes `flush_timeout`, and copies paste/event
payloads before returning them. `Key_decoder` now composes above that framing
boundary for common semantic keys and copies its character/unknown/paste
payloads. `Mouse_decoder` now adds stateful SGR/X10 semantics while leaving
terminal output lifecycle to the separate runtime boundary. `Terminal_modes`
now adds writer-free mode transitions without taking ownership of an output
flow. The optional Eio package now provides the corresponding caller-owned
output sink seam; pseudo-terminal integration remains separate.
