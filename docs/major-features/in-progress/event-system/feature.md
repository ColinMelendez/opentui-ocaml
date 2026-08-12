# Event system

Status: in progress.

This feature defines the event model for the OCaml OpenTUI library. It
translates ordinary OpenTUI event notifications into owner-local typed event
channels while keeping terminal input, keyboard dispatch, pointer bubbling,
and Eio queues as separate systems.

The active contract is in this file. Non-normative rationale and alternatives
are recorded in
[`context/design-review-2026-08-12.md`](context/design-review-2026-08-12.md).

## Reference correspondence

| Reference source | OCaml correspondence | Event responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/Renderable.ts` | `opentui-core.Scene.Node` and concrete renderable modules | Stable node identity, lifecycle notifications, and renderable-specific notifications use composition instead of inheritance. |
| `vendor/opentui/packages/core/src/renderer.ts` | `opentui-core` renderer and runtime modules | Renderer notifications use one owner-local event source. |
| `vendor/opentui/packages/core/src/types.ts` | Renderer-context capabilities | A normal render context shares the renderer event source; it does not create a forwarding emitter. |
| `vendor/opentui/packages/core/src/lib/KeyHandler.ts` | Dedicated keyboard-dispatch module | Global/local priority, prevention, propagation, and handler errors remain outside ordinary event channels. |
| `vendor/opentui/packages/core/src/Renderable.ts` and renderer dispatch | `opentui-core.Scene.dispatch_pointer` | Hit-testing and pointer bubbling remain a dedicated dispatch path. |
| `vendor/opentui/packages/core/src/audio.ts` | Deferred audio modules | Typed event families preserve synchronous channel semantics; producer scheduling remains in the audio runtime. |
| Native `eb_*` event names | Edit-buffer event mapping | Concrete native names map to typed edit-buffer events at the native boundary. |

The source correspondence map records this cross-cutting feature under the
reference renderer, renderable, context, and keyboard paths.

## Concept graph

```text
owner
  └── typed event source
        ├── one channel per event payload type
        ├── typed component event vocabulary
        └── subscriptions with explicit cancellation

renderer event source
  ├── renderer
  └── normal render context

keyboard dispatch ── priority, prevention, propagation
pointer dispatch  ── hit-testing, bubbling, current target
input flow       ── framing, ownership, backpressure
```

An event source belongs to one owning scene, renderer, runtime, or component.
Unrelated producers do not share a global event table or a global event
variant.

## Ordinary event channels

An ordinary event channel carries one statically typed payload. A component
owns one channel for each event in its event vocabulary. Multi-value payloads
use named records rather than positional argument lists.

The channel kernel has the following semantic operations:

```ocaml
type subscription

val on : 'a channel -> ('a -> unit) -> subscription
val once : 'a channel -> ('a -> unit) -> subscription
val cancel : subscription -> unit
val emit : 'a channel -> 'a -> bool
```

The channel type and its construction remain internal to the owning
component. Public APIs expose typed event descriptors or event-specific
registration functions. Public APIs do not expose string event names,
heterogeneous payloads, `Obj` values, or arbitrary channel emission.

The channel contract is:

- `emit` invokes callbacks synchronously in registration order;
- duplicate registrations create independent subscriptions;
- the listener set is snapshotted when `emit` starts;
- listeners added during an emission wait for a later emission;
- cancellation, clearing, or removal during an emission does not remove a
  listener from that emission's snapshot;
- `once` removes its subscription before it invokes its callback, so recursive
  emission does not invoke that subscription again;
- `cancel` is idempotent;
- callback exceptions propagate from `emit` unless the producer explicitly
  defines a different error boundary; and
- the Boolean result of `emit` reports whether the channel has a listener, not
  whether a callback handled, prevented, or propagated an event.

The steady-state emission path does not allocate a listener snapshot. Listener
storage uses copy-on-write or an equivalent representation that preserves
snapshot semantics while keeping subscription changes outside the hot path.

`listener_count` or `has_listeners` is available to a producer that needs to
avoid work when no consumer exists. A component owns the policy for whether an
unobserved error is ignored, reported, or raised. The channel kernel has no
special error event behavior.

## Typed component vocabularies

The event vocabulary belongs to the component that owns the event source. A
large family uses typed event descriptors:

```ocaml
module Event : sig
  type ('owner, 'payload) t

  val metadata : ('metadata, 'metadata option) t
  val reconnecting : ('metadata, reconnect_event) t
  val ended : ('metadata, unit) t
  val error : ('metadata, error_event) t
  val disposed : ('metadata, unit) t
end

val on : 'metadata stream -> ('metadata, 'payload) Event.t ->
  ('payload -> unit) -> subscription
```

The owner parameter prevents an event descriptor from one component from being
used with another component. A small event family may expose direct functions
such as `on_resize` when that shape is clearer. Both forms preserve the same
channel contract.

The following component translations apply:

- `AudioStream<M>` owns typed metadata, reconnecting, ended, error, and
  disposed events. Deferred delivery is an audio-runtime operation followed by
  synchronous channel emission.
- `AudioRecorder` owns typed lifecycle and error events. Native capture
  subscriptions use cancellation tokens instead of callback identity.
- `EditBuffer` maps concrete native `eb_*` names to typed events such as
  cursor-changed and content-changed. The dynamic native name does not become a
  dynamic public OCaml event API.
- `Renderable` owns base lifecycle channels such as focused, blurred, and
  destroyed. A concrete renderable owns its component-specific channels. A
  concrete renderable exposes its common node separately from its specialized
  event vocabulary.
- `CliRenderer` owns renderer channels. A normal `RenderContext` receives a
  capability for those same channels. A snapshot or isolated render context
  owns an independent event source when the reference context is independent.

## Separate dispatch systems

Keyboard dispatch is not an ordinary event channel. It has global-before-local
priority, handler snapshots, `preventDefault`, `stopPropagation`, and a
producer-defined exception policy. Its dedicated module may reuse subscription
identity and snapshot helpers, but it does not inherit the ordinary channel
contract as its complete dispatch model.

Pointer dispatch is not an ordinary event channel. `Scene.dispatch_pointer`
hit-tests the latest layout, invokes handlers from the target toward the root,
and applies `Continue` or `Stop` propagation decisions.

Terminal input is not an ordinary event channel. `Stdin_parser` owns framing
and typed parser events. `Input_coordinator` owns deadlines and a blocked event
slot. `Event_queue` owns bounded handoff, coalescing, and lossless overflow
behavior. These modules do not use observer channels to represent input
backpressure.

## Scheduling and concurrency

Event channels run in the owner context. The channel kernel does not start
fibers, await promises, use `Eio.Stream`, or provide cross-domain
synchronization.

An Eio fiber, timer, native callback handoff, or other producer performs any
required scheduling before it calls `emit`. A producer from another domain or
thread transfers ownership through an explicit handoff and the owner context
performs the emission. A mutex does not define event ordering, callback
ownership, or destruction races and does not replace that handoff.

## Lifecycle and ownership

The event source owner controls channel lifetime. Owner destruction makes later
subscription and emission behavior fail or become no-ops according to the
owning component's documented contract. Destruction is idempotent.

Renderable destruction preserves the reference lifecycle order: the destroyed
notification is emitted before listener cleanup and relationship teardown is
complete. A listener that runs during destruction observes the documented
destroyed state. Cleanup cancels internal subscriptions and clears remaining
channels after the destruction notification.

Every internal subscription has an owner-visible cleanup path. A subscription
does not depend on OCaml function equality. Repeated cancellation is safe.

## Error policy

The event kernel has no universal `error` event rule. Each producer defines the
policy for an unobserved error event. The policy can suppress the event, report
the error, or raise it. A producer that catches callback exceptions documents
that boundary; ordinary channels allow callback exceptions to propagate.

Error events do not imply propagation control. A Boolean result from `emit`
only reports listener presence. Handling, prevention, and propagation belong to
the specialized dispatcher or producer that defines them.

## Implementation criteria

The event-system implementation satisfies these criteria:

- ordinary channel tests cover registration order, duplicate subscriptions,
  additions and removals during emission, `once` recursion, exception
  propagation, listener counts, clearing, and idempotent cancellation;
- steady-state emission has a measured allocation behavior suitable for frame
  and renderer notifications;
- renderer and render-context tests prove shared-source behavior and isolated
  snapshot-context behavior where the reference distinguishes them;
- keyboard tests preserve global/local priority, prevention, propagation, and
  handler-error behavior without routing through the ordinary channel kernel;
- lifecycle tests prove destruction ordering and internal subscription cleanup;
- native event tests prove concrete `eb_*` names map to typed events; and
- the source correspondence map and package documentation identify each
  implemented event family and its owning module.

The feature record moves to `docs/major-features/implemented/event-system/`
when these criteria are satisfied.
