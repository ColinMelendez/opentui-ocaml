# Keyboard dispatch

Status: in progress.

This feature defines how decoded keyboard and paste input reaches global
handlers and the currently focused renderable. It is a specialized dispatch
system, not an instance of the ordinary [`Event.Channel`](../event-system/feature.md)
abstraction.

The shared rationale and alternatives are in the event-system
[`design-ideation`](../event-system/context/design-ideation.md). The focused
keyboard design is recorded in [`context/design.md`](context/design.md).

## Purpose

The reference keyboard path has behavior that ordinary multicast channels do
not provide: global handlers run before the focused renderable, dispatch can be
prevented or stopped, and the dispatcher owns the policy for handler
exceptions. This record keeps those rules explicit while leaving parser
framing, input backpressure, and ordinary component notifications to their
own feature records and modules.

## Reference correspondence

| Reference source | OCaml correspondence | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/lib/KeyHandler.ts` | `packages/opentui-core/src/lib/key_handler.ml` | Key, key-release, and paste dispatch; global/local ordering; prevention; propagation; handler-error policy. |
| `vendor/opentui/packages/core/src/Renderable.ts` focus and key handlers | `opentui-core.Renderable.t` focus state and concrete renderables | The focused renderable owns local keyboard behavior and its internal registrations. |
| `vendor/opentui/packages/core/src/renderer.ts` focus methods | `opentui-core.Renderer.t` and `Render_context.t` focus ownership | There is one current focused renderable; focus transitions update the previous and next owners. |
| `vendor/opentui/packages/core/src/lib/stdin-parser.ts` and `parse.keypress.ts` | `Stdin_parser` and `Key_decoder` | Framing and decoding produce typed input, including canonical Kitty Unicode and special-key press, repeat, and release events with validated modifier metadata. They do not implement keyboard dispatch. |

`Lib.Key_handler` exposes the keyboard-dispatch boundary. The parser produces
typed key and paste events, while the dispatcher also accepts an explicit
key-release payload. `Stdin_parser` classifies the supported Kitty Unicode,
functional-letter, and tilde-key frames, carrying press, repeat, and release
metadata into the corresponding dispatch family. Invalid or empty Kitty
modifier fields remain opaque responses rather than becoming default-modifier
key events.

## Active contract

### Dispatch phases

For each dispatchable event, the keyboard dispatcher performs these phases in
order:

1. invoke the global handlers for the event family in their registration
   order;
2. if dispatch has not been prevented or stopped, invoke handlers owned by the
   currently focused renderable in their local registration order; and
3. for a keypress or paste, allow the focused renderable's default action only
   when the event is not prevented.

There is no keyboard bubbling through the renderable tree's parent chain. Focus selects
the local recipient; it does not make keyboard handlers on ancestors into
additional phases. Keypress, key-release, and paste are separate event
families even when they share payload or control-flag machinery.

Registration and dispatch use snapshots. A handler added during a dispatch
waits for a later dispatch; removing a handler affects later invocations but
does not rewrite the current snapshot. The reference global handler collection
and renderable-internal handler collection have different duplicate semantics:
global registrations are independent listeners, while an internal handler is
registered by callback identity. A translation must preserve that observable
difference rather than inheriting ordinary channel behavior accidentally.

### Prevention and propagation

`prevent_default` records that the event's default action is suppressed. It
does not undo callbacks that have already run. A global handler that prevents
the event prevents the focused-renderable phase in the reference path; a
focused-renderable handler that prevents it suppresses the renderable's
default action.

`stop_propagation` stops the remaining keyboard dispatch, including later
handlers and later phases. It is distinct from pointer bubbling: keyboard
dispatch has global/local priority and focus, not a target-to-root route.

The result of registration or dispatch must not be interpreted as “the
application handled the key” unless the owning API explicitly defines that
meaning. In particular, listener presence and default prevention are separate
facts.

### Focus and lifecycle

The renderer owns at most one current focused renderable. Focusing a new
renderable first applies the reference blur behavior to the old one, then
installs the new renderable's internal keyboard registrations. Repeated focus,
blur, and destruction operations follow the owning node's documented
idempotency rules.

Blurring removes internal registrations. Destroying a renderable removes its
registrations and makes it ineligible for later local dispatch. A local
callback that can trigger destruction must not cause a later default action to
run against a destroyed renderable.

Detaching a renderable from its parent does not blur it or remove its internal
keyboard and paste registrations. A focused detached renderable remains the
local recipient until the renderer's focus lifecycle blurs or destroys it.

Setting a focused renderable's visibility to false blurs it and removes its
internal registrations. Restoring visibility does not restore focus.

### Payload ownership and scheduling

The dispatcher receives typed, owned input from the parser/input boundary.
Paste bytes remain valid for the callback lifetime without borrowing mutable
parser storage. Key metadata preserves the decoded key, modifiers, raw
sequence, and source information available at the boundary; adding fields is
not a reason to change the dispatch phases.

Dispatch is synchronous once the owner context hands the dispatcher a typed
event. Parser deadlines, Eio scheduling, queue capacity, and cross-context
handoff happen before that boundary and are not hidden in keyboard callbacks.

### Exceptions

Keyboard dispatch owns its handler-exception boundary. The reference catches
handler failures, reports them through its handler-error policy, and keeps
ordinary event-channel exception propagation separate. The OCaml dispatcher
must document and test the corresponding reporting and continuation behavior;
it must not silently broaden a catch-all policy to `Event.Channel`.

## Implemented boundary and remaining correspondence

The parser and decoder are implemented. `Lib.Key_handler` provides global
keypress, key-release, and paste channels, focused-renderable registrations,
snapshot dispatch, control flags, exception reporting, and explicit cleanup.
`Renderable.focus`, `blur`, visibility changes, detachment, and destruction
own the local registration lifecycle.

The supported Kitty keyboard protocol event types, special-key forms, modifier
validation, and Kitty metadata are inside the parser boundary. The dispatcher
does not invent those fields or silently classify an ordinary parsed key as a
release; it routes the parser's press, repeat, and release classifications to
the matching keyboard event family.

## Acceptance criteria

- global handlers run before focused-renderable handlers;
- handler snapshots, registration order, and scope-specific duplicate
  behavior are preserved;
- `prevent_default` and `stop_propagation` affect the documented phases;
- keypress, key-release, and paste remain distinct event families;
- focus, blur, and destruction clean up local registrations and are safe under
  repeated calls;
- detachment leaves focus-owned registrations active until blur or destruction;
- hiding a focused renderable blurs it and removes its local registrations;
- callbacks cannot cause a destroyed renderable's default action to run;
- key and paste payload ownership is explicit and tested;
- handler exception reporting and continuation match the reference boundary;
- the dispatcher has no implicit parent bubbling; and
- parser queueing and Eio handoff tests prove that dispatch scheduling does not
  change the event order or payload ownership promised here.
