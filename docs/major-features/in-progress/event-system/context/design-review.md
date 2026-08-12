# Event-system design review context

This file records design rationale and alternatives as non-normative context
for the [event-system feature record](../feature.md). The active contract is in
`feature.md`.

## Design rationale

The proposed direction replaces the broad rule “replace `EventEmitter` with
typed callbacks” with a more precise rule:

> Build a small OpenTUI event kernel with EventEmitter-compatible dispatch
> semantics, but do not build an OCaml `EventEmitter` object. Compose typed
> event channels into the objects that need them.

The discussion separates two concerns that are easy to conflate:

1. EventEmitter dispatch is synchronous, ordered, reentrant, and governed by
   listener-management semantics.
2. The producer decides when to call `emit`. OpenTUI sometimes schedules an
   event with `setTimeout(..., 0)` and sometimes emits directly from a native
   callback.

The resulting rule is:

> Events are synchronous. Scheduling events is the producer's responsibility.

The event-system primitive is a typed channel with subscriptions:

```ocaml
module Event : sig
  module Subscription : sig
    type t
    val cancel : t -> unit
  end

  module Channel : sig
    type 'a t
    val create : unit -> 'a t
    val on : 'a t -> ('a -> unit) -> Subscription.t
    val once : 'a t -> ('a -> unit) -> Subscription.t
    val prepend : 'a t -> ('a -> unit) -> Subscription.t
    val emit : 'a t -> 'a -> bool
    val listener_count : 'a t -> int
    val clear : 'a t -> unit
  end
end
```

The channel payload is statically typed. The design rejects string event names,
`Obj.t` payloads, and one global event variant. Each component owns a typed
family of channels. A renderer owns renderer events; an audio stream owns
metadata, reconnecting, ended, error, and disposed events; an edit buffer owns
concrete events such as cursor-changed and content-changed.

The public API does not expose channels directly. A component exposes typed
event descriptors or event-specific registration functions. A descriptor can
carry an owner phantom type so that an event from one component cannot be
registered on another component.

The discussion applies the following component translations. Audio,
edit-buffer, and renderer entries are future consumers of the event kernel;
their inclusion defines the contract they will use and does not claim that
those components are currently implemented.

- `AudioStream<M>` keeps its metadata type parameter and performs deferred
  delivery in the audio runtime before synchronous channel emission.
- `AudioRecorder` uses subscription tokens instead of callback identity for
  native capture cleanup.
- `EditBuffer` maps native `eb_*` names to concrete typed event descriptors;
  dynamic native strings do not become a dynamic public OCaml event API.
- `Renderable` composition separates base lifecycle events from
  renderable-specific events instead of placing every widget event in one base
  type.
- Normal `CliRenderer` and `RenderContext` share one renderer event source.
  An isolated snapshot context owns an independent source when the reference
  context is independent.

The ordinary channel contract preserves synchronous registration order,
duplicate registrations, snapshot dispatch, reentrancy, one-shot removal
before callback invocation, idempotent cancellation, and callback exception
propagation. Additions during an emission wait for a later emission. Removal
during an emission does not prevent a listener already present in the snapshot
from running.

The event kernel does not define a universal `error` policy. Each producer
decides whether an unobserved error is suppressed, reported, or raised. A
Boolean result from `emit` reports listener presence; it does not mean that a
callback handled, prevented, or propagated an event.

Keyboard and pointer dispatch remain separate. Keyboard dispatch owns
global-before-local priority, prevention, propagation, handler snapshots, and
its exception policy. Pointer dispatch owns hit-testing, current-target
semantics, bubbling, and propagation control. `Stdin_parser`,
`Input_coordinator`, and `Event_queue` remain separate because they own
framing, deadlines, bounded capacity, backpressure, coalescing, and lossless
handoff.

The event kernel remains independent of Eio and Lwd. It is not an `Eio.Stream`,
promise, or incremental signal. Event sources are owner-local. A native
callback, worker, or other domain performs an explicit handoff before the owner
context emits the event; a mutex does not replace that ownership rule.

The discussion identifies these tests as fundamental:

- registration order and duplicate subscriptions;
- additions, removals, and clearing during emission;
- recursive `once` behavior;
- exception propagation;
- listener counts and idempotent cancellation;
- destruction ordering and subscription cleanup;
- shared versus isolated renderer-context sources; and
- measured steady-state allocation for frame and renderer notifications.

The discussion also identifies a performance constraint: a steady-state emit
should not allocate a fresh listener snapshot. Copy-on-write listener storage
or an equivalent representation preserves snapshot semantics while moving
allocation to subscription changes.

This context refers to the Node.js EventEmitter contract and the pinned
OpenTUI sources under `vendor/opentui`. It is evidence for the active feature
record, not an additional API contract.
