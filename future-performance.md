# Future performance optimization ideas

Status: deferred design note, updated 2026-08-10.

This document is a parking lot for allocation and zero-copy ideas. It is not
an implementation commitment or a new phase gate. The copy-first paths already
checked in remain the correctness reference while `opentui-core`, Lwd, and the
widget layer are designed and debugged.

That separation is intentional. A pool, lease, or native view can reduce
allocation, but it also creates lifetime, exhaustion, cancellation, and
cross-fiber failure modes. Higher-level bugs should be diagnosable without
having to determine whether a bespoke memory-management scheme corrupted the
state first.

## Current reference path

| Path | Current behavior | What it tells us |
| --- | --- | --- |
| Terminal input | `opentui-terminal-eio.Input_flow` reuses one `Cstruct.t` and one character `Bigarray` view. The pure parser makes one ownership copy into its queue, and emitted event payloads are owned. | The Eio read loop has no intermediate `Bytes` staging buffer. The remaining copies are deliberate ownership boundaries. |
| Native output | `opentui-native.Renderer.Frame` writes resolved characters into caller-owned `bytes`. `Output_flow.write_subbytes` validates and writes only the returned range. | Output is bounded and safe, but the Eio sink path still has a copy-first `Bytes`-to-`Cstruct` conversion. |
| Frame mutation | `set_cell` crosses the FFI one cell at a time, constructs a six-field tuple, and converts each color into a fresh four-field tuple. | The frame profile's OCaml allocation is currently more obviously exposed here than in the output sink. Direct byte transport alone will not solve it. |
| Native-owned storage | Optimized-buffer arrays and span-feed chunks remain native-owned and are not exposed as naked Bigarrays or Cstructs. | Resize, destruction, release, and renderer ownership remain explicit instead of being hidden behind a view that could outlive its owner. |

The latest local profile is diagnostic rather than a performance gate. One run
measured roughly 4.7 million minor words for 64 80x24 frames, 0.92 million
minor words for 32,768 CSI-up input events, and zero OCaml minor words for
4,096 128-byte output writes. Wall-clock timings varied between runs. The
`Gc` counters cover the OCaml heap only; Bigarray, Cstruct, native, and system
allocator activity is not represented by those counters.

## Rules for future work

1. Keep a simple copy-first implementation as the behavioral reference while
   an optimization is being evaluated. This is a test and diagnostic reference,
   not a promise to preserve obsolete public APIs.
2. Keep ownership in the layer that owns the resource. `opentui-raw` may define
   an ABI-level borrow or release token; `opentui-native` may compose it for
   rendering; `opentui-terminal-eio` may turn caller-owned storage into an Eio
   flow view. A lower layer must not import a higher runtime to make a view
   convenient.
3. A borrowed buffer cannot escape its documented operation or lease. If an
   event crosses fibers or survives a read, it must retain a valid lease or be
   copied into owned storage.
4. Pools and queues must be bounded. Exhaustion must produce backpressure or a
   structured fallback/copy result; it must never silently grow without limit.
5. Measure copies, descriptors, OCaml allocations, frame latency, input
   service latency, native-call volume, and outstanding leases separately. GC
   word counts are useful, but they are not a hard real-time guarantee.
6. Do not add `[@@noalloc]`, unsafe pointer views, or a general allocator based
   on an assumption about the implementation. Each such claim needs a narrow
   primitive, an ownership proof, and a benchmark.

## Candidate A: direct caller-owned output

If a later profile identifies output handoff as material, this is the
lowest-lifetime-risk spike because the borrow can remain synchronous. It is not
a current priority or a claim that the renderer-to-scratch copy disappears:
the native renderer still copies resolved characters from its native storage
into the caller-owned Bigarray. The intended win is to remove the later
`Bytes`-to-`Cstruct` materialization and any avoidable descriptor/allocation at
the Eio sink boundary.

1. Add a native primitive that writes resolved characters directly into a
   caller-owned one-dimensional character `Bigarray`, returning the exact
   count written. Keep the native package independent of Eio and Cstruct.
2. Add a narrow `Renderer.Frame` composition function for that buffer. It must
   retain the current frame-token checks and all-or-nothing capacity behavior.
3. Add `Output_flow.write_cstruct` for a caller-owned Cstruct view. At the Eio
   boundary, construct a view over the same Bigarray rather than converting
   through `Bytes`.
4. Compare this path with the existing bytes/subrange path for payload copies,
   view construction, minor/major words, and frame latency. Do not call the
   path zero-copy from the native renderer unless a later design actually
   removes that native-to-caller copy.

Acceptance requires exact-prefix output, no trailing scratch bytes, structured
insufficient-capacity and sink-failure behavior, and proof that neither the
native call nor the sink retains the caller's storage after return. The
existing bytes path remains the fallback if a host or sink cannot support the
view cleanly.

## Candidate B: pooled input slabs and leases

The input path has more complicated ownership because events can outlive a
read and can cross from an input fiber to the UI owner.

The possible shape is a fixed pool of reusable character Bigarray slabs. The
parser would decode fixed-size common keys and mouse events directly from a
leased slab where practical. Variable-size paste, text, and unknown protocol
payloads would be copied, or would retain the slab through an explicit lease.
The event handoff would use bounded preallocated slots rather than allocating a
Queue cell and event wrapper for every byte sequence.

This is not permission to introduce a general memory manager. Before doing so,
the design must answer:

- who owns each slab while the parser, event queue, and UI handler can see it;
- how a lease is released on normal delivery, cancellation, and handler error;
- what happens when every slab is retained by a slow consumer; and
- whether common event allocation is actually material compared with parsing
  and native rendering.

Acceptance requires chunk-shape-invariant framing, split UTF-8 and paste
behavior, ESC-timeout correctness, event ordering, bounded exhaustion behavior,
and an observable absence of use-after-release. A deliberate copy fallback is
preferable to an unbounded pool or an implicit lifetime extension.

## Candidate C: batch frame mutations

The current per-cell FFI tuple is a likely allocation hotspot. The higher-level
fix should be a rendering contract, not a generic allocator. Candidates include
reusable command storage, a bounded batch of cell mutations, native text/fill
operations, and dirty-region submission.

The retained core should accumulate mutations and flush them at one controlled
frame boundary. It should not render by rebuilding a list or virtual tree for
each update, and it should not require a per-cell OCaml object or native pointer
view. The imperative `opentui-native` layer can expose only the narrow batch
operation that the profile justifies.

Acceptance requires stable native identity, equivalent frame output, explicit
failure behavior for a partially accepted batch, and lower allocation/native
call volume on representative scenes. This work belongs after the core's
render/update ownership is understood; otherwise it can obscure a scene or
invalidation bug.

## Candidate D: native-owned views and span reservations

`NativeSpanFeed` and the optimized cell buffer are possible zero-copy sources,
but they have stronger lifetime hazards than caller-owned scratch storage.

- A span view needs an owner and an idempotent release token. The feed must not
  recycle the chunk until release/consumed is complete.
- A reservation needs explicit commit and cancel, including close behavior
  while a reservation is active.
- A cell-buffer view must account for resize reallocating the native SoA arrays.
  The first safe choices are a scoped borrow that blocks resize/destroy, stable
  storage with deferred reclamation, or an intentional snapshot copy.
- The current native feed backend stages a complete frame before `writeAtomic`;
  using reservations for renderer output would require a chunk-aware frame
  writer as well as an OCaml view API.

These should be attempted only if profiling demonstrates that caller-owned
scratch and batching do not address the real cost. No naked native pointer,
Bigarray, or Cstruct should cross `opentui-raw` without its owner and lifetime
contract.

## Suggested order when we return to this

1. Stabilize and debug the imperative retained-core contracts using the current
   copy-first paths.
2. Compare the existing profile across supported compiler, host, and native
   artifact combinations.
3. If output copies are material, implement Candidate A as an isolated raw,
   native, and Eio seam with a direct comparison benchmark.
4. If frame mutation allocation dominates, investigate Candidate C before
   introducing any input pool.
5. If input event allocation remains material, design Candidate B with an
   explicit bounded lease state machine and exhaustion tests.
6. Consider Candidate D last, only with a measured need and a native lifetime
   proof.

At every step, higher-level correctness tests and the copy-first profile remain
the comparison point. If an optimization makes a failure harder to localize,
the optimization is not ready to become the default path.

## Explicit non-goals

- no custom OCaml garbage collector or process-wide allocator;
- no unbounded slab, event, or command pool;
- no lock-free or multi-domain queue without a measured ownership requirement;
- no per-cell native pointer view as a substitute for a render contract;
- no claim that lower allocation alone provides hard real-time behavior; and
- no Lwd or widget API decisions in this document.
