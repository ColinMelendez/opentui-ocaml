Yes. After looking at the actual uses more closely, I would change the direction from **“replace `EventEmitter` with typed callbacks”** to something more precise:

**Build a small OpenTUI event kernel with EventEmitter-compatible dispatch semantics, but do not build an OCaml `EventEmitter` object. Compose typed event channels into the objects that need them.**

That distinction solves most of the problems you are worried about. Your current guide already recognizes that event priority, dispatch mutation, prevention, and cleanup are semantic contracts, not implementation details.  But the current table entry — "`EventEmitter` → typed event variant and narrow callback registration/dispatch" — is underspecified for how pervasive and varied `EventEmitter` actually is.

## What OpenTUI is actually getting from `EventEmitter`

There are two different things that are easy to conflate.

The first is **EventEmitter's dispatch machinery**. Node's ordinary `EventEmitter` invokes listeners synchronously in registration order. The listener set is effectively snapshotted for an emission: removing a listener during an emission does not prevent that listener from being invoked later in that same emission. `once`, duplicates, prepend, listener counts, and clearing listeners also have defined behavior. ([Node.js][1])

The second is **when OpenTUI chooses to call `emit`**. That is not an EventEmitter property.

For example, `AudioStream` deliberately schedules metadata and terminal events using `setTimeout(..., 0)`, and only inside that timer does it invoke `EventEmitter.prototype.emit`. Its `closed` promise is resolved *after* terminal-event listeners have run.   `AudioRecorder` has the same pattern for terminal events.

By contrast, `EditBuffer` forwards a native event directly to `instance.emit(...)` from the native-event callback.  `CliRenderer` is itself the synchronous event source shared through `RenderContext`.

So I would establish this rule:

> **Events are synchronous. Scheduling events is the producer's responsibility.**

That gives you a stable foundation.

---

# I would build this primitive

Conceptually, something like:

```ocaml
module Event : sig
  module Subscription : sig
    type t

    val cancel : t -> unit
  end

  module Channel : sig
    type 'a t

    val create : unit -> 'a t

    val on :
      'a t ->
      ('a -> unit) ->
      Subscription.t

    val once :
      'a t ->
      ('a -> unit) ->
      Subscription.t

    val prepend :
      'a t ->
      ('a -> unit) ->
      Subscription.t

    val emit :
      'a t ->
      'a ->
      bool

    val listener_count : 'a t -> int
    val clear : 'a t -> unit
  end
end
```

`'a` is the **payload for one particular event**.

This is deliberately *not*:

```ocaml
type event_name = string
type payload = Obj.t
type emitter
```

and it is deliberately *not*:

```ocaml
type event =
  | Resize of ...
  | Error of ...
  | Metadata of ...
  | ...
```

The fundamental object is simply a typed event channel.

An `AudioStream<'metadata>` consequently owns several channels:

```ocaml
type 'metadata events = {
  metadata : 'metadata option Event.Channel.t;
  reconnecting : reconnect_event Event.Channel.t;
  ended : unit Event.Channel.t;
  error : error_event Event.Channel.t;
  disposed : unit Event.Channel.t;
}
```

A renderer owns a completely different record:

```ocaml
type events = {
  resize : resize_event Event.Channel.t;
  frame : frame_event Event.Channel.t;
  render_error : render_error Event.Channel.t;
  handler_error : handler_error Event.Channel.t;
  selection : Selection.t Event.Channel.t;
  focused_renderable : focused_renderable_event Event.Channel.t;
  destroy : unit Event.Channel.t;
  (* ... *)
}
```

There is no heterogeneous event table, no string dispatch, no `Obj.magic`, and no requirement that unrelated event producers share one giant sum type.

That is the part I think makes this approach particularly suitable for OCaml.

## But don't expose the channels directly

I would put a typed event vocabulary over them.

For example, the AudioStream API could look approximately like:

```ocaml
module Audio_stream : sig
  type 'metadata t

  module Event : sig
    type ('metadata, 'payload) t

    val metadata :
      ('metadata, 'metadata option) t

    val reconnecting :
      ('metadata, reconnect_event) t

    val ended :
      ('metadata, unit) t

    val error :
      ('metadata, error_event) t

    val disposed :
      ('metadata, unit) t
  end

  val on :
    'metadata t ->
    ('metadata, 'payload) Event.t ->
    ('payload -> unit) ->
    Event.Subscription.t

  val once :
    'metadata t ->
    ('metadata, 'payload) Event.t ->
    ('payload -> unit) ->
    Event.Subscription.t
end
```

Usage becomes:

```ocaml
let subscription =
  Audio_stream.on stream Audio_stream.Event.metadata (fun metadata ->
    ...
  )
```

and:

```ocaml
Audio_stream.on stream Audio_stream.Event.error (fun { error; context } ->
  ...
)
```

Internally, `Audio_stream.on` is just a typed match from `Audio_stream.Event.metadata` to the corresponding `Event.Channel.t`.

You can implement those event identifiers as a small GADT, or as descriptors containing a channel accessor. **The important point is that the heterogeneous part lives in the tiny per-component mapping, not in the event engine itself.**

That gives every component the same external pattern while keeping the underlying storage statically typed.

---

# The four cases you mentioned then become straightforward

### `AudioStream<M>`

This is almost the ideal case for this design. Its TypeScript event map is already a closed typed family:

```ts
export interface AudioStreamEvents<M> {
  metadata: [metadata: M | null]
  reconnecting: [event: AudioStreamReconnectEvent]
  ended: []
  error: [error: Error, context: AudioStreamErrorContext]
  disposed: []
}
```

and the class extends `EventEmitter<AudioStreamEvents<M>>`.

The OCaml type parameter carries through naturally:

```ocaml
type 'metadata t
type ('metadata, 'payload) Event.t
```

No existential types are necessary.

The **deferred delivery** belongs in `Audio_stream`, not `Event.Channel`. Upstream explicitly schedules `metadata`, generic asynchronous events, and terminal events before calling the ordinary EventEmitter dispatcher.

So you might have internally:

```ocaml
let emit_metadata_later t =
  Runtime.defer t.runtime (fun () ->
    Event.Channel.emit t.events.metadata t.metadata |> ignore
  )
```

The event kernel itself remains synchronous.

That separation is important.

### `AudioRecorder`

Same pattern, just without a metadata type parameter.

The particularly nice improvement is this upstream code:

```ts
this.capture.on("error", this.captureErrorListener)
...
this.capture?.removeListener("error", this.captureErrorListener)
```

In OCaml you don't need callback identity at all:

```ocaml
let capture_error_subscription =
  Audio_capture_stream.on
    capture
    Audio_capture_stream.Event.error
    handle_capture_error
in
```

and cleanup is:

```ocaml
Event.Subscription.cancel capture_error_subscription
```

This is a real improvement in mechanism while preserving the lifecycle semantics exactly.

It also avoids having to define what "function equality" should mean in an OCaml `remove_listener callback` API.

### `EditBuffer`

This one initially looks like an argument for retaining dynamic string events, but current upstream actually makes the opposite case.

The TypeScript bridge takes native names beginning with `eb_`, strips the prefix, and forwards the resulting event name dynamically.  But the native implementation currently has concrete semantic events such as `"cursor-changed"` and `"content-changed"`. The Zig side emits them at the corresponding state transitions.   `EditBufferRenderable` then subscribes to exactly those named events.

So I'd port that as:

```ocaml
module Edit_buffer.Event : sig
  type 'a t

  val cursor_changed : unit t
  val content_changed : unit t
end
```

The native bridge maps:

```text
native eb_cursor-changed
        ↓
Edit_buffer.Event.cursor_changed

native eb_content-changed
        ↓
Edit_buffer.Event.content_changed
```

The dynamic string is an artifact of the JS/native bridge. **The semantic protocol isn't inherently dynamic.**

If future upstream adds another `eb_*` event, you add another typed event when you port it.

I would not preserve the ability for users to subscribe to arbitrary nonexistent strings merely because Node happens to allow it.

---

# `CliRenderer implements RenderContext` is the interesting one

This is where I think your architecture should explicitly introduce an **event-source capability**.

Upstream's `RenderContext` extends EventEmitter, and this isn't merely theoretical. A renderable can subscribe to renderer events through its context. For example, `ScrollBoxRenderable` does:

```ts
this._ctx.on("selection", this.selectionListener)
```

and removes that exact registration during destruction.

Therefore the OCaml `Render_context.t` needs access to **the same event channels owned by the `Cli_renderer`**.

I would model that explicitly:

```ocaml
module Renderer_events : sig
  type t

  module Event : sig
    type 'a t

    val resize : resize t
    val selection : Selection.t t
    val focused_renderable : focused_renderable t
    val theme_mode : theme_mode t
    (* ... *)
  end

  val on :
    t ->
    'a Event.t ->
    ('a -> unit) ->
    Event.Subscription.t
end
```

Then:

```ocaml
type Cli_renderer.t = {
  ...
  events : Renderer_events.t;
}
```

and:

```ocaml
type Render_context.t = {
  ...
  events : Renderer_events.t;
}
```

The context does **not create another emitter**.

When you derive the render context:

```ocaml
let render_context renderer =
  {
    ...
    events = renderer.events;
  }
```

you are sharing the exact event source.

Then the `ScrollBox` translation is something like:

```ocaml
let subscription =
  Renderer_events.on
    (Render_context.events ctx)
    Renderer_events.Event.selection
    on_selection
```

and destruction cancels the `Subscription.t`.

That gives you the semantic relationship that `implements RenderContext` supplied in TypeScript without pretending OCaml has inheritance.

This is probably the most important design point for interoperability.

---

# Renderable inheritance suggests the same strategy

There is another reason I would not build a generic OCaml `EventEmitter`.

`Renderable` itself extends EventEmitter, and its subclasses use that inherited emitter for subclass-specific events. On destruction, upstream emits `DESTROYED`, tears down its relationships, then calls `removeAllListeners()`.

Trying to recreate that with a single typed event family leads toward unpleasant types like:

```ocaml
type _ event =
  | Destroyed : unit event
  | Focused : unit event
  | Slider_changed : int event
  | Scroll_changed : ...
  | Text_changed : ...
```

Now every widget event has contaminated the base `Renderable` type.

Or you start constructing extensible variants/GADT inheritance machinery purely to emulate TypeScript classes.

I wouldn't.

Composition gives you a cleaner answer:

```text
Slider.t
 ├── retained node
 │    └── Renderable.Events
 │         ├── focused
 │         ├── blurred
 │         └── destroyed
 │
 └── Slider.Events
      └── changed
```

Generic code holding only a retained node can subscribe to:

```ocaml
Renderable.on node Renderable.Event.destroyed ...
```

Slider-specific code can subscribe to:

```ocaml
Slider.on slider Slider.Event.changed ...
```

A `Slider.t` can expose:

```ocaml
Slider.node : Slider.t -> Renderable.t
```

This is exactly where I think **not copying inheritance** pays off.

---

# The event kernel needs quite strict semantics

This is the part I would test once, thoroughly, and then use everywhere.

For ordinary channels, `emit` should be synchronous and reentrant. Listeners should run in registration order. Additions during an emission should not participate in that emission. Removals during an emission should affect later emissions, but not the already-snapshotted current emission. Duplicate registrations should be independent subscriptions. `once` needs to unregister *before* invoking its callback so a recursive emission cannot invoke it again. These are the important Node semantics. ([Node.js][1])

A useful internal representation is something like:

```ocaml
type 'a listener = {
  id : int;
  callback : 'a -> unit;
  once : bool;
  mutable fired : bool;
}

type 'a t = {
  mutable listeners : 'a listener list;
  mutable next_id : int;
}
```

`emit` takes a snapshot:

```ocaml
let emit channel value =
  let snapshot = Array.of_list channel.listeners in

  Array.iter
    (fun listener ->
      if listener.once then begin
        if not listener.fired then begin
          listener.fired <- true;
          remove_by_id channel listener.id;
          listener.callback value
        end
      end else
        listener.callback value)
    snapshot;

  Array.length snapshot <> 0
```

There are a couple of subtleties around recursive emissions and `once`, but this general structure gets you very close to Node's actual behavior without much code.

And importantly, **ordinary callback exceptions should propagate and terminate the current emission**, because that's what normal EventEmitter dispatch does. Don't have `Event.Channel` universally catch callbacks.

---

# `error` is not one universal policy in OpenTUI

This was another thing that became clear from looking around.

Node has special behavior for an unhandled event literally named `"error"`: without a listener, emission throws. ([Node.js][1])

But OpenTUI doesn't uniformly rely on that.

For instance, `TreeSitterClient` explicitly tests `listenerCount("error") > 0` before calling `emit("error", ...)`, thereby deliberately suppressing an unobserved error event rather than triggering Node's default unhandled-error behavior.

Audio has other error delivery behavior.

So I would **not bake `"error"` magic into `Event.Channel`**.

Instead the component's emission site owns its unhandled policy:

```ocaml
if Event.Channel.listener_count t.events.error > 0 then
  Event.Channel.emit t.events.error error
else
  ()
```

or, where reference behavior requires it:

```ocaml
if Event.Channel.listener_count t.events.error = 0 then
  raise error
else
  Event.Channel.emit t.events.error error |> ignore
```

Again: preserve OpenTUI's semantics, not every feature of Node's EventEmitter.

---

# Keyboard and mouse should *not* be forced through this abstraction

This is an important boundary.

`InternalKeyHandler` is already not a normal EventEmitter. It overrides dispatch to implement global-before-renderable priority, `preventDefault`, `stopPropagation`, handler snapshots, and exception catching.

Likewise pointer events bubble through the retained node tree and have target/current-target/propagation semantics.

Those are **dispatch systems**, not ordinary observer events.

I would therefore have:

```text
Event.Channel
    ordinary multicast notifications
    renderer events
    lifecycle events
    audio events
    edit-buffer notifications
    widget change notifications

Key_dispatch
    global/local priority
    preventDefault
    stopPropagation

Pointer_dispatch
    hit target
    bubbling
    currentTarget
    stopPropagation
```

They can reuse little pieces such as `Subscription.t` or snapshotting helpers, but they should not be made instances of one mega-event framework.

That prevents a common abstraction mistake.

---

# I would also keep Eio out of `Event`

The event kernel should be synchronous pure OCaml.

Don't make:

```ocaml
Event.emit : ... -> unit Eio.Promise.t
```

and don't implement each event as an `Eio.Stream`.

An `Eio.Stream` is a producer/consumer synchronization primitive. Introducing it here would give events queueing and backpressure semantics that Node EventEmitter does not have.

Likewise I would not use Lwd signals as the event system. Lwd is useful for **state dependency and reconciliation**; an EventEmitter event is a discrete notification with synchronous callback/reentrancy semantics. Those are different abstractions.

When upstream does:

```text
setTimeout(0)
   -> emit
```

the OCaml translation should be:

```text
Eio/runtime scheduling
   -> Event.Channel.emit
```

not:

```text
Event.Channel magically becomes asynchronous
```

This will also make differential testing much easier.

---

# One additional invariant: event channels should be owner-local

Because you're moving into OCaml 5/Eio, you now have a possibility Node didn't have: two domains could concurrently call `emit`.

I would prohibit that at this layer.

An event source should belong to the owning renderer/runtime/domain. `emit`, subscribe, and unsubscribe occur on that owner. A native thread, worker, or another OCaml domain that produces something first performs the appropriate cross-domain handoff; **after** the handoff, the owner invokes `Event.Channel.emit`.

Otherwise you suddenly have to define things Node never had to define:

```text
Did domain A's listener registration happen before domain B's emit?
Which domain runs the callback?
What does registration order mean between domains?
Can one callback race destruction?
```

A mutex inside `Event.Channel` does not really solve those semantic questions.

So this should remain an observer primitive, not become your multicore message transport.

---

## The resulting architecture

I think the system should end up conceptually like this:

```text
                    ┌────────────────────┐
                    │   Event.Channel<'a> │
                    │                    │
                    │ synchronous        │
                    │ ordered            │
                    │ snapshot dispatch  │
                    │ reentrant          │
                    │ subscriptions      │
                    │ once / prepend     │
                    │ listener_count     │
                    └─────────┬──────────┘
                              │
             ┌────────────────┼─────────────────┐
             │                │                 │
             ▼                ▼                 ▼
     Renderer_events    Audio_stream      Edit_buffer
       typed family      typed family      typed family
             │
             ├──────────────┐
             │              │
             ▼              ▼
       Cli_renderer    Render_context
             │              │
             └──── same event source ────┘


Separate dispatch machinery:

     Key_dispatch             Pointer_dispatch
     priority                 target/bubble
     preventDefault           stopPropagation
     propagation              currentTarget
```

So, **yes, I would pursue a different mechanism from `EventEmitter` as an API/representation, but not a different semantic model for ordinary events.**

I think the precise contributing rule should become something close to:

> **`EventEmitter` inheritance is translated to composition with typed event channels. Ordinary event channels preserve synchronous registration-order dispatch, snapshot semantics, reentrancy, one-shot subscriptions, and explicit cleanup. Scheduling, unhandled-error policy, propagation, and priority remain properties of the reference producer or dispatcher rather than of the event primitive. Objects that share an event source, such as `CliRenderer` and `RenderContext`, share the same channel set rather than forwarding between independent emitters.**

That gives `AudioRecorder`, `AudioStream<M>`, `EditBuffer`, `CliRenderer`, `Renderable`, and future widgets a very mechanical porting pattern without importing JavaScript's dynamic event bus into the OCaml design.

[1]: https://nodejs.org/api/events.html?utm_source=chatgpt.com "Events | Node.js v26.5.1 Documentation"
