# Pointer dispatch

Status: in progress.

This feature defines how decoded mouse input is routed through the retained
renderable tree. It is a specialized dispatch system, not an instance of the ordinary
[`Event.Channel`](../event-system/feature.md) abstraction.

The shared rationale and alternatives are in the event-system
[`design-ideation`](../event-system/context/design-ideation.md). The focused
pointer design is recorded in [`context/design.md`](context/design.md).

## Purpose

Pointer dispatch combines input classification, layout hit-testing, target
selection, bubbling, pointer state, and renderer-owned default actions. These
responsibilities must remain visible at their boundaries: decoding a mouse
frame is not the same operation as routing a pointer event through the retained
renderable tree.

## Reference correspondence

| Reference source | OCaml correspondence | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/lib/parse.mouse.ts` | `opentui-core.Mouse_decoder` and `Stdin_parser` | Decode X10/SGR frames, modifiers, scroll data, button state, and move/drag classification. |
| `vendor/opentui/packages/core/src/Renderable.ts` mouse handling | `opentui-core.Renderable.t` pointer handlers | Invoke the target's handlers and expose the current route node while bubbling. |
| `vendor/opentui/packages/core/src/renderer.ts` mouse dispatch | `opentui-core.Renderer.t` and retained-tree pointer route | Hit-test the latest layout, derive pointer lifecycle events, manage capture/hover, and apply focus/selection defaults. |

The OCaml decoder carries modifiers and scroll information. The renderer
owns a current/next hit grid, hit-tests the committed grid, routes pointer
events from target to root, derives hover and drag lifecycle events, and
applies left-button focus and pointer-capture policy. Renderable handlers
expose target/current-target identity and mutable propagation/default-action
flags.

## Active contract

### Boundary between decoding and routing

The decoder owns terminal protocol recognition and emits an owned decoded mouse
event. The retained-tree dispatcher consumes that event only after the input handoff
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

The renderer derives `over`, `out`, `drag-end`, and `drop` behavior, tracks the
captured target, updates hover state after input and committed frames, and
uses left-button pointer events for focus. A resize releases pointer capture.
Selection remains a separate renderer-owned feature because the retained
selection model is not implemented by this package boundary.

The retained renderable tree owns tree routing and node-local lifecycle. The renderer/runtime
owns capture, hover transitions, focus and selection defaults, and any terminal
policy that depends on the active render loop. A default action must not be
added to the retained-tree route merely because the reference renderer has
one.

### Handler errors and lifecycle

The renderer catches pointer-handler failures and publishes a typed
`handler_error` notification through the renderer/context event source. The
pointer route does not use ordinary event-channel exception propagation.

Destroyed subtrees are excluded from hit-testing and cannot receive a later
route. Pointer capture is released when its owner is destroyed or the renderer
is resized, and repeated cleanup is safe. Destroyed renderables do not receive
later pointer callbacks.

## Implemented boundary and remaining correspondence

Mouse decoding, current/next committed hit-grid routing, target-to-root
bubbling, target/current-target identity, propagation/default-action flags,
hover transitions, drag capture, drop delivery, focus-on-down, resize cleanup,
stationary-pointer hover recheck, and handler-error reporting are implemented
in `Renderable.t` and `Renderer.t`.

Selection default actions and native scissor-aware hit-grid writes remain
separate correspondence work. The current hit grid is OCaml-owned and follows
the reference current/next semantics; replacing its storage with the native
renderer grid requires an explicit raw ABI seam.

## Acceptance criteria

- hit-testing uses the latest committed layout and selects the deepest
  eligible target;
- target-to-root route order and propagation stopping are deterministic;
- routed events distinguish original target and current route node;
- decoded modifiers, scroll data, button state, and ownership survive the
  parser-to-dispatch boundary;
- hover, drag, drag-end, drop, and capture behavior match the reference when
  those event families are enabled;
- renderer default actions are separately defined from retained-tree bubbling and
  respect prevention;
- destroyed nodes and captured targets cannot receive stale routes;
- pointer handler errors follow the documented renderer/tree boundary; and
- queueing and motion coalescing tests prove that input adaptation does not
  silently alter route order or event ownership.
