# Pointer dispatch

Status: in progress.

This feature defines how decoded mouse input is routed through the retained
scene. It is a specialized dispatch system, not an instance of the ordinary
[`Event.Channel`](../event-system/feature.md) abstraction.

The shared rationale and alternatives are in the event-system
[`design-ideation`](../event-system/context/design-ideation.md). The focused
pointer design is recorded in [`context/design.md`](context/design.md).

## Purpose

Pointer dispatch combines input classification, layout hit-testing, target
selection, bubbling, pointer state, and renderer-owned default actions. These
responsibilities must remain visible at their boundaries: decoding a mouse
frame is not the same operation as routing a pointer event through the scene.

## Reference correspondence

| Reference source | OCaml correspondence | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/lib/parse.mouse.ts` | `opentui-core.Mouse_decoder` and `Stdin_parser` | Decode X10/SGR frames, modifiers, scroll data, button state, and move/drag classification. |
| `vendor/opentui/packages/core/src/Renderable.ts` mouse handling | `opentui-core.Scene.Node` pointer handlers | Invoke the target's handlers and expose the current route node while bubbling. |
| `vendor/opentui/packages/core/src/renderer.ts` mouse dispatch | `opentui-core.Scene.dispatch_pointer` plus renderer/runtime policy | Hit-test the latest layout, derive pointer lifecycle events, manage capture/hover, and apply focus/selection defaults. |

The current OCaml decoder already carries modifiers and scroll information.
The current scene dispatcher is intentionally smaller: it hit-tests the latest
layout, routes a five-kind pointer event from target to root, and supports
`Continue` or `Stop`. Full reference mouse-event lifecycle, capture, hover,
derived events, and default actions remain in progress.

## Active contract

### Boundary between decoding and routing

The decoder owns terminal protocol recognition and emits an owned decoded mouse
event. The scene dispatcher consumes that event only after the input handoff
has established its lifetime and ordering. Queue capacity and motion
coalescing are input-adapter behavior; they must not be smuggled into a node's
pointer handler semantics.

### Target selection and bubbling

Dispatch hit-tests against the latest committed layout. The selected target is
the deepest eligible node at the pointer coordinates. The route proceeds from
that target toward the root in parent order. A node's handler sees the routed
event for its current route position; a future public event type must
distinguish the original target from the current route node rather than
overwriting one identity with the other.

Stopping propagation prevents ancestor handlers from receiving the event. It
does not mean that the decoder drops later input, and it does not by itself
cancel renderer default actions. Prevention of a default action is a separate
event fact and must be defined for each action.

### Pointer state and renderer policy

The reference renderer derives `over`, `out`, `drag-end`, and `drop` behavior,
tracks the pressed/captured target, updates hover state, and uses pointer
events in focus and selection decisions. Those are part of this feature's
compatibility target, but they are not implicit consequences of the small
`Scene.dispatch_pointer` route currently exposed.

The scene owns tree routing and node-local lifecycle. The renderer/runtime
owns capture, hover transitions, focus and selection defaults, and any terminal
policy that depends on the active render loop. A default action must not be
added to `Scene.dispatch_pointer` merely because the reference renderer has
one.

### Handler errors and lifecycle

The current scene handler contract propagates handler exceptions. The
reference renderer catches pointer-handler failures and applies its
handler-error/reporting policy. The eventual routed API must choose and
document the corresponding owner boundary; it must not silently conflate
pointer errors with ordinary `Event.Channel` callback behavior.

Destroyed subtrees are excluded from hit-testing and cannot receive a later
route. Pointer capture and subscriptions, once implemented, must be released
when their owner is destroyed, and repeated cleanup must be safe.

## Current scope

Mouse decoding and a minimal target-to-root scene route are implemented. The
full reference pointer lifecycle and its renderer integration remain in
progress. This record deliberately does not promise a new public event shape
until target/current-target identity, propagation, default-action prevention,
capture, cleanup, and handler-error behavior have a single tested owner.

## Acceptance criteria

- hit-testing uses the latest committed layout and selects the deepest
  eligible target;
- target-to-root route order and propagation stopping are deterministic;
- routed events distinguish original target and current route node;
- decoded modifiers, scroll data, button state, and ownership survive the
  parser-to-dispatch boundary;
- hover, drag, drag-end, drop, and capture behavior match the reference when
  those event families are enabled;
- renderer default actions are separately defined from scene bubbling and
  respect prevention;
- destroyed nodes and captured targets cannot receive stale routes;
- pointer handler errors follow the documented renderer/scene boundary; and
- queueing and motion coalescing tests prove that input adaptation does not
  silently alter route order or event ownership.
