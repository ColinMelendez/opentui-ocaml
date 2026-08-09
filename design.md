# Design

Status: working design, updated 2026-08-10.

This document records the decisions that are currently intentional and keeps
the unresolved decisions visible. It describes the native OCaml side of
[OpenTUI](https://github.com/anomalyco/opentui), not a JavaScript port.

## Goal

Build an OCaml terminal UI framework directly on OpenTUI's Zig native core:

```text
OCaml application
    │
    ├── widgets and application components       (later)
    ├── Lwd reactive bindings                   (later)
    ├── retained scene and event model          (later)
    ├── native renderer, buffers, Yoga bindings  (later)
    ├── typed raw ABI and ownership boundary     (being built)
    │
    └── OpenTUI Zig core                         (vendor/opentui)
```

JavaScript is not an intermediate runtime. TypeScript sources are reference
material for behavior and conventions; the implementation path is OCaml →
native ABI → Zig.

The first useful target is a small, reliable TUI subset. OpenTUI contains
additional editor, audio, image, and text-processing systems; binding all of
them before the renderer/terminal path is understood would make the boundary
larger and less auditable.

## Decisions we are keeping

### One Dune monorepo

Local OCaml packages live under `packages/` and share one Dune workspace.
External OCaml dependencies are resolved and locked by Dune package
management. The upstream OpenTUI source is a Git submodule under
`vendor/opentui`, because it is an independently maintained native project,
not an OCaml dependency to copy into the tree.

Nix supplies the compiler and development tools. The pinned upstream revision
currently requires Zig 0.16.0; the Nix shell and the submodule revision must be
updated together when that contract changes.

### A narrow native boundary

`opentui-raw` is the bottom package. It will own:

- foreign declarations and the native library build/link seam;
- opaque native handles and typed handle domains;
- ABI structs, fixed-width values, pointer/length spans, and error results;
- explicit destruction and ownership rules.

The Phase 1 `Handle.t` module was only a package-wiring scaffold. The first
Phase 2 typed slice removes it rather than preserving a generic compatibility
handle: `Renderer.t`, `Buffer.t`, and `Event_sink.t` are distinct abstract
domains, and the packed native representation remains private to the C
facade. The exact invalid value, generation behavior, and thread/domain
restrictions come from the pinned Zig source and smoke tests.

The raw layer will expose a small typed subset of the upstream exports first:
renderer lifecycle, optimized/frame buffers, Yoga/layout primitives, terminal
capabilities, event delivery, and the native-renderable bridge where it is
needed. It will not expose raw integer handles throughout the higher layers.

Native resources have explicit owners. Finalizers may be a last-resort leak
guard, but normal programs will use explicit lifecycle operations and scoped
helpers. Invalid runtime state crossing the boundary is represented as a
structured result or status, not as a process-wide exception policy.

### Layered packages

The package graph is intentionally based on independently useful dependency
layers, not one package per Zig file:

| Package | Responsibility | Status |
| --- | --- | --- |
| `opentui-raw` | ABI values, generation-checked handles, foreign calls, ownership | current |
| `opentui-native` | higher-level renderer, buffers, Yoga integration, native renderables, native lifecycle | foundation increment |
| `opentui-terminal` | byte queue, protocol framing, terminal modes, input decoding, resize, output lifecycle | foundation |
| `opentui-core` | retained scene tree, layout/render traversal, events | proposed |
| `opentui-lwd` | Lwd-based fine-grained bindings and component scope | chosen direction; API tentative |
| `opentui-widgets` | reusable controls and application-facing conveniences | later |

The raw package may contain small ABI-level renderer, buffer, Yoga, and
capability wrappers because they are the narrow ownership boundary. Higher-level
buffers, Yoga/renderable composition, frame lifecycle, and native integration
remain modules of `opentui-native` initially. They become separate packages
only if an independent consumer and stable ownership boundary justify the split.

### Retained, render-once UI structure

The framework should keep native nodes and their bindings alive across updates.
A component or mount function establishes persistent native identity once;
reactive changes update properties, layout inputs, text, or event handlers on
those existing objects.

The hot path must not rebuild an entire `Lwd.t<Ui>` tree, allocate a fresh
virtual tree, or recreate native nodes for ordinary state changes. Keyed child
identity and explicit teardown are part of the design, not an optimization to
add later.

### Lwd as the reactive kernel

We are choosing to build the reactive framework directly on Lwd rather than
adopting Bonsai and its Jane Street dependency graph. Lwd provides the
incremental dependency graph, variables, sampling, invalidation, sequences,
and resource primitives; the OpenTUI layer supplies UI policy around it.

The intended shape is Solid-like fine-grained reactivity:

- component setup runs once to create persistent native structure;
- signals/derived values update the smallest affected native properties;
- child collections have explicit keyed identity;
- scopes own native resources and cleanup actions;
- effects are batched at the frame boundary;
- equality/cutoff policy prevents redundant native calls.

This does not commit us to copying Solid's API or runtime. The OCaml API,
effect scheduler, equality interface, context mechanism, and scope types are
still tentative.

### Allocation and frame-time discipline

GC churn is a first-class design constraint. The implementation should prefer:

- persistent node/binding identity;
- immutable values at configuration boundaries and mutable state in long-lived
  runtime objects;
- reusable arrays, buffers, and span encodings for FFI calls;
- batched property updates and one controlled frame flush;
- no per-frame list/closure/string construction unless profiling justifies it;
- benchmark evidence for allocation rate, frame time, and native-call volume.

The goal is not to eliminate all allocation. It is to keep transient allocation
off the render/input hot paths and make unavoidable ownership transitions
visible in profiles.

## Phase 1: native structures and first smoke gate

The audit of the pinned OpenTUI source makes the following structures and
invariants concrete enough to guide the first implementation. These are
low-level design constraints, not all final public APIs.

The inventory is based on `vendor/opentui/packages/core/src/zig/handles.zig`,
`renderer.zig`, `buffer.zig`, `yoga.zig`, `event-bus.zig`, and
`native-span-feed.zig`, together with the TypeScript FFI in
`vendor/opentui/packages/core/src/zig.ts` and the input reference
implementation in
`vendor/opentui/packages/core/src/lib/stdin-parser.ts`.

### Critical data structures

| Area | OpenTUI representation | OCaml-side decision for the first implementation |
| --- | --- | --- |
| Native handles | A `u32` bit pattern containing a 16-bit slot index, a 12-bit generation, and a 4-bit object kind. Slot zero is invalid. The fixed registry tracks vacant, alive, and destroying states, plus owner/borrowed-child relationships. | Keep handles abstract and kind-specific. Prefer an immediate OCaml representation in long-lived nodes, with conversion to the C ABI at the shim, rather than storing boxed `int32` values everywhere. Do not expose the packed fields or let callers mix renderer, buffer, and event-sink handles. |
| Resource ownership | Destroy begins by marking the object destroying; renderer destruction invalidates its borrowed buffer children before deinitializing the renderer. Generation exhaustion prevents unsafe slot reuse. | Treat renderer buffers returned by `getCurrentBuffer`/`getNextBuffer` as borrowed views owned by the renderer. Explicit close is primary; a finalizer can only be a leak guard. All calls touching the registry use one serialized native-entry policy. |
| Renderer frame state | The renderer keeps current/next optimized buffers, current/next hit grids, cursor/output caches, dirty state, and backend state. Hit testing observes the committed/current grid while the next frame is being built. | Do not mirror the cell grid or hit grid in OCaml. The retained core tracks node identity and dirty regions; the native renderer owns frame buffers, diffing, hit-grid storage, and output framing. |
| Optimized buffer | A structure-of-arrays grid: `u32` encoded characters, four-lane `RGBA` values, and `u32` attributes, plus native grapheme/link pools and clipping/opacity stacks. `RGBA` is `[4]u16`; low bytes hold channels and high bytes carry color metadata. | Keep cells native. Bind batched operations such as clear, text, cell, fill-rectangle, resize, and resolved-character output. Do not expose a per-cell OCaml record or raw pointer view in the initial API. |
| Yoga layout | `YGNodeRef`/`YGConfigRef` are raw C pointers. Layout results are caller-provided `extern struct`s of six `f32`s (`left`, `top`, `right`, `bottom`, `width`, and `height`); style values include enums, floats, and a packed `u64`. Native renderables currently install synchronous native measure callbacks. | The raw package now owns a config and Yoga tree behind a C-side generation-checked registry. `Yoga_tree.t` and `Yoga_node.t` are abstract, owner-scoped tokens; layout readback copies the six fields into OCaml. The current wrapper binds point width/height only. Measurement callbacks, packed style values, and renderable integration stay in native code until callback lifetime/reentrancy is designed. |
| Terminal capabilities | `ExternalCapabilities` is an `extern struct` with one-byte booleans/enums, two borrowed terminal string pointers with `usize` lengths, and terminal state codes. `getTerminalCapabilities` returns pointers into the renderer's terminal state. | The raw package asserts the 64-byte supported-host layout, checks lengths, copies the two strings, and decodes the pinned enum values into a typed snapshot. Capability responses consume caller-owned bytes synchronously; terminal querying and mode lifecycle remain in `opentui-terminal`. |
| Native event sink | A C-callable callback receives borrowed name/data pointers and lengths synchronously. Event names are dynamic byte strings. | The raw package callback copies bytes into a bounded native queue before returning; OCaml polls owned packets and receives an explicit overflow error. It does not invoke arbitrary handlers or re-enter the renderer from the callback. Background callbacks still require a separate OCaml runtime-lock and queue design. |
| Stdin parser | The TypeScript reference has a mutable byte queue with start/end offsets and amortized compaction, a tagged protocol state machine, a bounded 64 KiB pending prefix, a 20 ms ESC timeout, an event queue, a bracketed-paste collector, and mouse-button state. | `opentui-terminal` owns the reusable queue and a framing parser with scalar cursors. It emits owned ground `Key` bytes, raw `Sequence` frames for CSI/SS3/OSC/DCS/APC/unknown units, and owned `Paste` bodies. A timeout-flushed lone ESC has a narrow delayed SGR/X10 mouse recovery path; it reconstructs valid continuations as owned CSI frames without decoding mouse state. `Key_decoder` is a pure layer above framing for common control, UTF-8, meta, CSI, SS3, modifier, and modifyOtherKeys keys; unknown sequences remain copied protocol events. `Mouse_decoder` is a stateful semantic layer for complete SGR/X10 frames: it preserves high X10 bytes, tracks SGR buttons for drag classification, and returns no event for non-mouse frames. The caller's timer coordinator invokes `flush_timeout`; protocol-context probes, terminal modes, and Eio flow integration remain later modules. Preserve chunk-shape invariance, split UTF-8 handling, ESC timeout behavior, split paste markers, delayed mouse recovery, bounded overflow behavior, and byte-accurate X10 decoding. Do not allocate a fresh parser-state variant for every byte. |
| Native output feed | `NativeSpanFeed` owns fixed-size chunks, a span ring, reserve/commit operations, chunk reference counts, and an optional callback. A span remains borrowed until the consumer marks it consumed. | The first Phase 2 raw seam copies drained payloads into OCaml bytes and pairs them with an idempotent native release token. Reservations use an OCaml-owned staging buffer with explicit commit/cancel; the native reserve pointer stays private. Native chunk views through Bigarray/Cstruct remain a later, separately benchmarked API. |
| Foreign buffer view | OCaml Bigarrays can hold external/native storage and `Cstruct` can provide zero-copy subviews, but the underlying address can become invalid when a Zig owner resizes or destroys it. | Keep the Bigarray/Cstruct value behind an abstract `Native_view.t` containing the owner and generation/borrow token. Initially reject resize/destroy while views are active; deferred reclamation is a later optimization. Do not publish raw pointers or naked Bigarrays from `opentui-raw`. |
| Cross-fiber handoff | The UI state and native entrypoints need a single owner, while terminal reads may need to wait independently. | Use a bounded event/command handoff at the runtime boundary. Its items own their bytes and policy distinguishes lossless key/paste/resize events from coalescible mouse motion. The handoff is not part of the per-cell render path. |

The first raw handle representation should therefore be a small immediate value
with distinct abstract modules such as `Renderer.t`, `Buffer.t`, and
`Event_sink.t`. The C-facing conversion may use `uint32_t`; the representation
chosen for an OCaml node must be measured, but a boxed `int32` in every
retained node is an avoidable default allocation.

Yoga deserves special caution. OpenTUI's Yoga exports are C-compatible, but
their pointer values are not entries in the OpenTUI generation-checked handle
registry. A direct pointer binding would create a second lifetime system and
would make use-after-free easy to express. The raw binding therefore owns the
Yoga config/tree and uses a separate generation-checked registry for abstract
tree/node tokens. `opentui-native` will compose this resource into persistent
renderables; it will not bypass the raw owner with a pointer API.

### Implementation cruxes

1. **The ABI seam must be explicit.** The Zig exports already use C calling
   conventions, but there is no reason to make OCaml depend on guessed layout
   rules for Zig arrays, booleans, tagged unions, or raw pointers. The first
   build seam should either consume a generated C header or provide a very thin
   C-compatible facade with fixed-width arguments, explicit output structs, and
   status returns. The pinned build currently produces a dynamic library and
   pulls in Yoga C++ sources, so the selected Zig target, C++ runtime, and Dune
   link rule are part of this ABI seam rather than later packaging work.
   `ctypes`/dynamic symbol lookup is useful for a probe, not as the hot
   production call path.

2. **Native entry must have one owner.** The handle registry is documented by
   the upstream source as serialized; renderer output may additionally have a
   private native thread when `setUseThread` is enabled. Phase 1 should leave
   that option disabled and make one UI fiber/domain the owner of all raw calls.
   Eio fibers can coordinate around that owner, but an Eio domain pool must not
   receive renderer, buffer, registry, or Yoga pointers. Use the memory output
   backend for the first smoke path so a synchronous render cannot unexpectedly
   block the whole Eio domain on terminal output; choose a feed or dedicated
   output owner only after measuring the real output behavior.

   The initial callback contract follows the same rule: native callbacks are
   synchronous, UI-owner-only, and copy-in before return. They may not retain a
   Zig pointer, call arbitrary OCaml handlers, or re-enter raw renderer APIs.
   Any callback-side OCaml exception is converted to a reported status/error;
   callbacks from a future native thread require an explicit runtime-lock and
   owned-queue design.

3. **The frame needs a transaction boundary.** The intended sequence is:

   ```text
   input/commands → application state → dirty native properties
                    → Yoga calculation → next-buffer mutation
                    → native render/commit → output and hit-grid swap
   ```

   Reactive invalidation and imperative commands should accumulate before the
   native render call. The first imperative runtime should make this ordering
   visible before Lwd is connected to it. Native renderer double buffering is
   the frame transaction; an OCaml shadow grid would duplicate both memory and
   synchronization work.

4. **Borrowed memory needs a boundary rule.** Event callback data, buffer
   pointers, Yoga output pointers, and output-feed spans are all only valid for
   a documented interval. The default OCaml rule is copy-in/copy-out at the
   boundary. Zero-copy access is a later, explicitly scoped API backed by a
   benchmark and a lifetime token.

   The zero-copy work now has an explicit shape. Reusable OCaml-owned byte
   storage uses a one-dimensional `Bigarray` and a `Cstruct.t` view at the Eio
   boundary; native-owned storage may be exposed only through a view that also
   retains an owner and release token. A naked pointer, `bytes`, or `Cstruct.t`
   must never outlive the operation or token that keeps its storage valid. The
   [OCaml C interface](https://ocaml.org/manual/latest/intfc.html) supports
   both accessing OCaml Bigarray storage from C and wrapping an existing native
   pointer as a Bigarray, but wrapping the pointer does not solve native
   resize, destruction, or refcounting by itself.

5. **Layout callbacks cannot be an accidental OCaml callback path.** Yoga can
   call a measure function synchronously and non-reentrantly during layout. A
   callback into OCaml would need a rooted owner, a no-allocation or controlled
   allocation contract, exception conversion, and a rule for callbacks during
   teardown. The first path uses OpenTUI's native measure targets and postpones
   custom OCaml measurement until those rules are tested.

6. **Input parsing is a protocol implementation, not a line reader.** Eio's
   byte flow should be read with a reusable `Cstruct.t` view into the parser's
   buffer; `Buf_read.line` and whole-stream parsing are the wrong abstraction
   for terminal protocol framing. The parser consumes bytes and emits complete
   events. A timer coordinator should wake a pending parser prefix for the ESC
   ambiguity without creating a timer fiber per byte. The parser should be
   tested with arbitrary chunk splits, not only with complete terminal
   sequences.

7. **Allocation policy must be structural.** Persistent records are acceptable
   for renderer, parser, layout, and component state. Per-frame/per-cell
   lists, strings, closures, and boxed numeric tuples are not the default.
   Reusable color/layout scratch storage, grow-on-demand arrays, and a local
   byte queue are enough for Phase 1; a general collection dependency should
   not be introduced before measurements identify a need.

8. **Sizes and failure paths are part of the ABI.** Width/height products,
   pointer lengths, UTF-8 input, output-frame sizes, and event payload lengths
   need checked conversions at the boundary. A zero handle, stale handle,
   invalid dimension, full output feed, or destroyed parser must have a typed
   result/status path rather than silently becoming an empty successful value.

### First binding slice

The smallest useful native slice should contain the following operations. The
exact OCaml names and error types remain open, but this is deliberately smaller
than the eventual raw surface:

- the selected native artifact loaded and linked by the root Dune workflow;
- renderer create/destroy, current/next buffer lookup, and a deterministic
  memory-output path with native-threaded output disabled;
- optimized-buffer clear, text/cell update, and bounded caller-owned output;
  raw `get*Ptr` access and native-owned cell views are explicitly deferred;
- event-sink create/destroy plus one copy-and-queue callback smoke test.

The full stdin parser, terminal mode setup, public Yoga ownership/layout API,
and `NativeSpanFeed` reservation/view protocol are audited here but are not
Phase 1 acceptance requirements. They become the next native protocol work
after the artifact can be linked and the basic ownership rules are executable.

The editor, audio, image, Ghostty, syntax, and high-level text-buffer exports
remain outside this slice. Text rendering should use OpenTUI's native grapheme
and width logic rather than duplicate Unicode width calculations in OCaml.

### Phase 1 exit record

Phase 1 is complete for the pinned OpenTUI revision. The checked-in seam now
has a source-backed Zig/C ABI probe, a reproducible Dune/Zig link rule, and a
black-box native smoke that covers renderer/buffer ownership, invalid and
empty boundary inputs, bounded caller-owned output, synchronous callback byte
copying, direct writes into OCaml-owned bytes, and a diagnostic repeated-update
allocation baseline. The test-only C shim owns every raw `u32` handle and
destroys renderer children before their owner; the public raw package still
does not expose those handles.

The exit is deliberately narrow. Native zero-copy span views, terminal
integration, the stdin parser, and all reactive or widget layers remain
follow-on work under the Phase 2 and later boundaries below. The first typed
Phase 2 raw extension now covers the owned Yoga/layout, copied capability, and
copied output-feed ownership boundaries without changing that separation.

### Phase 2 typed raw progress

The current raw extension keeps the package layers explicit. `opentui-raw`
contains only the C ABI declarations, status conversion, token registries, and
small typed operations needed to establish ownership. `Yoga.Node.layout`
returns an OCaml record copied from the six-`f32` native output,
`Capabilities.snapshot` copies terminal name/version bytes and decodes the
source-defined enum codes, and `Span_feed.drain` copies native payloads before
returning an explicit release token. `Renderer.render` maps the pinned
rendered/skipped/failed byte status to an OCaml variant. Neither module exposes
a pointer, packed native handle, callback, or borrowed string; native zero-copy
views remain deferred.

Black-box tests cover layout values, invalid dimensions, cross-tree rejection,
close invalidation, XTVERSION copying, enum decoding, closed-renderer errors,
copied output spans, release-driven chunk reuse, reservation
busy/cancel/commit behavior, and the reusable terminal byte queue/framing
parser. Semantic parser policy, native zero-copy views, `opentui-native`, Lwd,
and widgets remain later layers.

The terminal-side foundation is `opentui-terminal`. Its `Byte_queue` owns a
bounded reusable `Bigarray.Array1` and logical start/end cursors, compacts a
consumed prefix before growing, and makes an over-limit append fail without
changing the queue. The package is independent of `opentui-raw`; `Key_decoder`
adds common semantic key naming/modifiers above `Stdin_parser` while preserving
unknown protocol events. `Mouse_decoder` adds SGR/X10 semantic events and owns
only the pressed-button state needed to classify SGR drag motion. Terminal
modes are represented by writer-free `Terminal_modes` transitions: an owned
ANSI byte sequence is paired with an immutable next state, so a caller can
commit the state only after its output sink accepts the sequence. Eio flow
integration and output lifecycle remain separate follow-on modules.

`opentui-terminal.Stdin_parser` is the framing layer above that queue. It does
not decode semantic key names or mouse state. `Key` and `Sequence` payloads are
copied before they enter the parser event queue, and paste bodies bypass the
bounded pending queue through chunked owned storage so a large paste does not
turn the protocol prefix bound into a paste-size limit. `Key_decoder.decode`
maps only the common key subset currently needed by the imperative terminal
path; it copies character, unknown-sequence, and paste payloads at its own
boundary. `Mouse_decoder.decode` examines only complete CSI sequence events and
leaves non-mouse frames to the caller's other decoders. `Terminal_modes` does
not write to a flow or mutate global terminal state.

`Input_decoder` is the terminal composition boundary: it tries mouse semantics
before common key semantics, then returns copied opaque sequence or paste
events. Resetting it clears only decoder-owned mouse state; mode, timer, flow,
and dispatch ownership stay outside the package.

`Input_coordinator` is the pure timer seam above that composition. It owns one
parser, one input decoder, and an output event queue; each successful push
refreshes a single deadline when framing leaves an incomplete prefix. The
caller supplies monotonic milliseconds and invokes `fire_timeout` only when the
deadline is due. It does not create Eio fibers, own a flow, commit terminal
modes, or write output.

`opentui-native.Layout` is the first higher-level Yoga composition. It owns one
raw Yoga tree and wraps its nodes in an owner-scoped opaque domain. Dimension
updates are validated before raw mutation, calculation maps the small native
direction type, and layout readback is copied into a native-package record.
Closing the layout invalidates every node; measure callbacks, packed styles,
native renderable state, and retained scene identity remain later contracts.

### Eio and external data structures

Eio is a good fit for the runtime boundary, not for the raw ABI or the native
render hot path. Its current API provides fibers, switches, byte `Flow`s,
buffered readers/writers, time, and bounded `Stream` queues. A `Switch` gives
the terminal runtime a natural lifetime for the input reader, timer
coordinator, and output resources. A bounded `Stream` is a reasonable first
implementation for handing owned input events from an input fiber to the UI
fiber, provided that overflow/coalescing policy is explicit. See the [Eio
module overview](https://ocaml.org/p/eio/latest/doc/eio/Eio/index.html),
[switch documentation](https://ocaml.org/p/eio/1.4/doc/eio/Eio/Switch/index.html),
and [stream documentation](https://ocaml.org/p/eio/1.4/doc/eio/Eio/Stream/index.html).

The proposed dependency policy is:

| Dependency | Use | Phase 1 decision |
| --- | --- | --- |
| `eio`, `eio_main`, and platform support | Terminal byte I/O, cancellation, timers, fibers, and runtime lifetime | Adopt at `opentui-terminal`/runtime level. Keep `opentui-raw` independent. |
| `Eio.Stream`/`Eio.Promise` | Waiting and handoff between runtime fibers | Candidate for the boundary queue and wake-up path, not the parser's pending-byte queue or render command buffer. Benchmark the event-burst behavior. |
| OCaml `Array`, `Bytes`, `Queue`, `Hashtbl`, `Map`, and `Set` | Local state, keyed lookup, scratch storage, and small registries | Use first. Add a small growable ring/dirty-set module only where the access pattern is known and a profile justifies it. |
| `Bigarray` or `cstruct` | Reusable byte storage, typed bulk buffers, and bounded views | Use `Bigarray.Array1` as the raw storage contract and `Cstruct` at the Eio flow boundary. A native-owned view must remain behind an owner/release token; neither library solves pointer lifetime or resize invalidation by itself. |
| `uutf`/`uucp` | OCaml-side Unicode decoding or width logic | Defer for rendering; OpenTUI already owns grapheme and width behavior. Add only if the input/parser API needs a separately validated Unicode layer. |
| `ctypes` | ABI exploration or a diagnostic loader | Acceptable for a probe; do not make it the stable per-cell or per-layout call path. |
| `dtoa` | Deterministic OCaml `float`-to-text conversion | Do not add to `opentui-raw` in Phase 1. If OCaml later emits canonical text, hide the selected formatter behind a project-owned module, test special values and `f32`/`f64` semantics, and keep it off the render hot path because its API returns an allocated string. |
| Saturn, lock-free queues, Kcas, Domainslib, or a general container package | Alternative concurrent/collection implementations | No Phase 1 dependency. The native side already owns the renderer/output rings, and the OCaml side initially has one native owner. Revisit only if a measured multi-domain requirement appears. |
| Lwd | Reactive invalidation and later component bindings | Keep for the later `opentui-lwd` layer. It is not a Phase 1 native data-structure dependency. |

The resulting recommendation is deliberately conservative: adopt Eio for
structured terminal runtime work, but do not bring in a separate external data
structure library yet. The first custom structures should be small, local,
and shaped by the audited protocols: a byte queue, an event handoff policy,
and a dirty/native-command accumulator. The renderer's cell grid, hit grid,
grapheme pools, and output span ring should remain in Zig.

### Zero-copy options and boundaries

Zero-copy is not one mechanism. We should choose the mechanism according to
which side owns the storage and how long the native code may retain it.

1. **Synchronous OCaml-owned input.** A `bytes` or `string` pointer can be used
   for a call that consumes it before returning, but it must not be retained by
   Zig or used across a released-runtime section. The explicit long-lived
   representation is a `Bigarray.Array1` with the exact element kind and C
   layout required by the ABI. `Cstruct.t` is a zero-copy view over that
   Bigarray and is the right shape for Eio byte-flow reads. The backing
   Bigarray should be allocated once and reused for stdin, parser input, and
   other bounded byte I/O. If Zig retains the pointer, the OCaml owner must
   retain the Bigarray as an ordinary OCaml field or root; a custom block's C
   payload is not scanned by the GC and cannot secretly hold that OCaml value.

2. **Reusable caller-provided output.** Functions such as resolved-character
   output and layout readback should accept caller-owned scratch storage when
   the native operation has a known maximum or a two-call size/query protocol.
   The native function writes directly into the Bigarray; OCaml then consumes
   that storage without creating an intermediate string. This still copies from
   a native renderer-owned buffer into caller-owned storage, but avoids a second
   allocation and makes ownership unambiguous.

3. **Native-owned borrowed views.** A C shim can wrap an existing native
   pointer as an external Bigarray, after which Cstruct can provide subviews.
   The Bigarray wrapper alone is not a lifetime model. The public value must
   retain a native owner and a generation/borrow token, and native destruction
   must either reject while views exist or defer reclamation until the last
   token is released. The first implementation should use scoped borrows and
   reject resize/destroy; stable arenas and deferred reclamation can be added
   only if profiling justifies their complexity.

4. **Native reservation/commit.** `NativeSpanFeed` has the strongest candidate
   seam: `streamReserve` returns writable space in a native chunk and
   `streamCommitReserved` publishes the bytes without a memcpy. The raw seam
   now adds the missing native cancel export and proves the lifecycle through an
   OCaml-owned staging buffer; the native reserve pointer never becomes an
   OCaml value. Commit or cancel is explicit, and close reports `Busy` while a
   reservation is active. A future zero-copy wrapper may expose a scoped
   `Cstruct.t`/native view only after it retains the feed owner and release
   token. The current Zig `FeedBackend` still stages a complete frame in
   `frameBytes` and then calls `writeAtomic`, so using the reserve API for the
   renderer itself would require a chunk-aware frame writer.

The optimized cell buffer is deliberately not the first native-owned view. Its
`char`, `fg`, `bg`, and `attributes` arrays are native SoA storage, but resize
currently reallocates them. A cached OCaml view would therefore become a
use-after-free or stale-address hazard. Keep cell mutation behind batched native
operations for now. If post-processing later needs direct views, choose one of
three explicit contracts: a scoped borrow that blocks resize/destroy, stable
allocations with deferred reclamation, or an intentional snapshot copy.

The first zero-copy implementation should consequently be:

- `Bigarray.Array1`/`Cstruct.t` for reusable OCaml-owned terminal input and
  scratch output;
- an abstract native-view token for any native-owned bytes;
- a native `release_span` operation with an idempotent OCaml token rather than
  OCaml mutating a refcount byte directly; and
- a benchmark that measures copies, view construction, minor allocations, and
  frame latency separately.

Zero-copy does not mean zero allocation: a Bigarray/Cstruct view descriptor,
reservation token, or result record may still allocate. The relevant target is
to keep the payload copy-free and keep descriptors out of per-cell and
per-byte loops. `[@@noalloc]` should be used only for primitives independently
proved not to allocate, raise, release the runtime, or invoke callbacks.

### Deterministic float text

Numeric values should cross the raw boundary as numeric values. The native
renderer already owns the formatting of terminal output, and the Phase 1
OpenTUI paths we have identified use floating point primarily for layout and
statistics rather than for escape-sequence text. OCaml should not turn those
values into strings merely to pass them through the binding.

There is still a legitimate need for a policy when OCaml emits diagnostics,
golden-test text, configuration, or a serialized protocol. `Stdlib.Float` and
`Printf` are useful human-facing formatters, but they should not silently define
the byte-level representation of a protocol. The policy must choose, per
format:

- shortest round-tripping decimal text;
- fixed-precision human text; or
- an exact binary/hex representation when decimal text is not the contract.

`dtoa` is a reasonable candidate for the first case. Its `shortest_string_of_float`
and ECMAScript-style functions implement a specified shortest-decimal algorithm
for OCaml `float` values, and the package has no runtime OCaml dependencies; the
linked 0.1 documentation is an older release, so any adoption would start by
evaluating the current release rather than copying that version. See the
[dtoa documentation](https://ocaml.org/p/dtoa/latest/doc/README.html) and
[package metadata](https://opam.ocaml.org/packages/dtoa/).

It is not a complete formatting policy or a hot-path solution. The current
implementation copies each result into a newly allocated OCaml string, and its
special-value handling produces `NaN`/`Infinity` and canonicalizes zero to `0`;
those choices need explicit review before using it for JSON, signed zero, or
bit-exact diagnostics. The upstream repository is also archived, so the
dependency should be wrapped rather than exposed directly. See the
[native wrapper](https://github.com/flow/ocaml-dtoa/blob/main/src/dtoa_stubs.c).

The eventual OCaml-facing boundary should therefore be a small module owned by
the package that owns the text format, for example `Float_text.shortest` and a
separate `Float_text.json_number` that rejects or explicitly encodes non-finite
values. A fixed-decimal formatter should be a separate function; `dtoa`'s
shortest-format APIs do not replace it. Because OpenTUI/Yoga uses `f32` in
several native structs while OCaml `float` is `f64`, any formatter for layout
readback must also state whether it formats the widened `f32` value or a
separately rounded/display-oriented value.

### Testing strategy

Tests should follow the layer being tested:

- raw ABI tests create, query, and destroy native resources and verify invalid
  handle/error behavior;
- terminal tests exercise input decoding, resize, capabilities, and output
  framing with deterministic byte streams or a pseudo-terminal;
- core tests verify retained identity, layout, event propagation, and teardown;
- reactive tests verify dependency invalidation, batching, keyed identity, and
  cleanup;
- integration tests run a small application through a real terminal boundary;
- benchmarks record allocations and frame/update costs rather than relying on
  visual inspection alone.

## Tentative decisions and risks

These are deliberately not settled yet:

1. **ABI shape.** We need to decide whether direct Zig exports are stable
   enough for OCaml FFI declarations or whether a small OCaml-oriented C ABI
   facade should be added alongside the upstream build. We should not infer
   ownership or calling conventions from the TypeScript FFI wrapper alone.
2. **Build ownership.** The root Dune project may invoke the upstream Zig build
   as a generated native artifact, or a small root build wrapper may produce
   the library before Dune links it. The choice should preserve reproducible
   target selection and avoid copying upstream source.
3. **Compiler baseline.** The current Dune constraint remains broad enough for
   the lower-level work. Whether the public project requires standard OCaml 5.5,
   OxCaml, or a narrower supported range should be decided after the first FFI
   and allocation benchmarks.
4. **Terminal ownership.** OpenTUI's native renderer owns substantial terminal
   behavior, while the TypeScript layer also contains input/event policy. We
   need to determine which pieces belong in `opentui-terminal` and which should
   remain a thin native adapter.
5. **Reactive scheduling.** The frame scheduler, batching boundary, effect
   ordering, context model, and equality/cutoff interfaces are open design
   work. They must be chosen with allocation measurements, not API familiarity
   alone.
6. **Upstream evolution.** The submodule is a pinned reference, not a promise
   that every upstream internal type is public or stable. Upstream updates
   require an ABI/source audit and a deliberate parent-repository gitlink
   update.

## Explicitly deferred

- Bonsai/Incremental or Jane Street compatibility layers;
- a general widget catalog;
- editor, audio, image, Ghostty-VT, and other nonessential OpenTUI systems;
- a compatibility layer for APIs that have not yet been designed;
- optimization claims before native and reactive benchmarks exist.
