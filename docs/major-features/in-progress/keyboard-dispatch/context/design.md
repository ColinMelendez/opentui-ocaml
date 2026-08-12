# Keyboard dispatch design

This document records the focused design for keyboard dispatch. It is
non-normative context for the active [keyboard-dispatch feature
record](../feature.md); the shared event vocabulary, ordinary channel
boundary, and rejected mega-dispatcher design are in the event-system
[`design-ideation`](../../event-system/context/design-ideation.md).

## Boundary

Keyboard dispatch begins after `Stdin_parser` has recognized and owned a typed
key, key-release, or paste event. It ends after global handlers, the focused
renderable's handlers, and any permitted default action have run. The stages
around it remain separate:

```text
terminal bytes
  -> Stdin_parser / Key_decoder
  -> input handoff and queueing
  -> keyboard dispatch
       global handlers -> focused-renderable handlers -> default action
```

The queue is an ownership and backpressure boundary. It is not a keyboard
listener registry, and queue coalescing must not change the keyboard event
families or dispatch phases.

## Why this is not `Event.Channel`

An ordinary channel is synchronous multicast with registration-order and
snapshot semantics. Keyboard dispatch adds two ordered scopes, focus selection,
default-action suppression, propagation stopping, and a producer-specific
exception boundary. Those rules can reuse small subscription or snapshot
helpers, but composing them from ordinary channels must not erase their
meaning.

The reference also gives global listeners and renderable-internal listeners
different duplicate behavior. This is a contract decision, not an incidental
choice of OCaml collection.

## Focused recipient

The renderer maintains the current focused renderable. Focus and blur own the
installation and cancellation of internal keyboard handlers. A scene parent
is not a fallback keyboard recipient, so a focused child does not cause key
events to bubble through its ancestors.

The focus owner and dispatcher must share the same lifecycle boundary: a
destroyed or detached node cannot receive a later local event, and a callback
that destroys its node cannot leave a default action queued against stale
state.

## Reference observations and open implementation work

The reference `KeyHandler` has `keypress`, `keyrelease`, and `paste` event
families. Its global phase runs before renderable-internal handlers. Global and
local collections are snapshotted, `preventDefault` gates later local/default
work, and `stopPropagation` terminates the remaining route. The reference
handler boundary catches and reports callback failures.

The current OCaml parser supplies key and paste events and the scene already
has retained-node lifecycle concepts, but keyboard dispatch and focus
integration are not yet an exposed core module. The implementation design
must settle the typed payload module, registration return/cancellation shape,
focus ownership, and handler-error reporting together; it must not make each
renderable invent a different dynamic-dispatch mechanism.
