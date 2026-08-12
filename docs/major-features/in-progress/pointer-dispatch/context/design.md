# Pointer dispatch design

This document records the focused design for pointer dispatch. It is
non-normative context for the active [pointer-dispatch feature
record](../feature.md); the shared event vocabulary and the reason pointer
dispatch is separate from ordinary channels are in the event-system
[`design-ideation`](../../event-system/context/design-ideation.md).

## Boundary

Pointer work has four distinct stages:

```text
terminal bytes
  -> Mouse_decoder / Stdin_parser
  -> input handoff and queueing
  -> retained-renderable-tree hit-test and target-to-root route
  -> renderer pointer state and default actions
```

The first stage classifies terminal protocol frames. The route consumes a
decoded event against the latest layout. The renderer stage may derive hover or
drag lifecycle events, maintain capture, and decide whether focus or selection
defaults run. Keeping these stages separate prevents a queue or decoder from
becoming an accidental owner of retained-tree semantics.

## Why this is not `Event.Channel`

An ordinary channel broadcasts to one owner-local listener set. Pointer
dispatch selects a target from geometry and then visits an ordered route. Its
propagation control is about ancestor traversal, while default-action
prevention is about renderer policy. A common event-channel API cannot express
those distinctions without becoming a second, implicit dispatch framework.

Small shared helpers for subscription cleanup or handler snapshots are fine;
the target, current-target, route, and pointer-state rules remain in the
pointer dispatcher.

## Reference observations and current subset

The reference parser recognizes X10 and SGR mouse frames, tracks pressed
buttons, and classifies motion, drag, scroll, and button transitions. The
reference renderer additionally handles hover transitions, pointer capture,
drag-end/drop delivery, and focus/selection defaults. Renderable handlers
observe the current route node and can stop ancestor propagation.

The current OCaml surface has a richer decoded mouse event than the routed
tree event, and the minimal retained-tree route implements the core hit-test
and bubble route with `Continue`/`Stop`. The future design must decide
where the richer routed payload, target/current-target identity, pointer
capture, and renderer default actions become public. Until then, the minimal
route is a current subset, not a claim that the reference mouse lifecycle
is complete.
