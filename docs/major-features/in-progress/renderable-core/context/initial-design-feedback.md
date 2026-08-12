This is substantially closer to an implementation-ready design. The high-level decomposition—`Renderer.t`, a shared `Render_context.t`, a heterogeneous `Renderable.t` spine, typed concrete modules, and separate event/keyboard/pointer systems—is coherent.

I would make several changes before treating it as the active contract. The most important ones are not large architectural reversals; they are places where the current document is a little too abstract and would leave an implementer room to accidentally change upstream semantics.

### 1. Make the behavior record a precise replacement for virtual dispatch

This is the largest remaining gap.

The document currently says the behavior record contains hooks for:

> layout updates, command generation, drawing, concrete cleanup, and any specialized child-operation validation.

That underspecifies what TypeScript overriding is doing. Current `Renderable` has meaningful override points for `onUpdate`, resizing, removal, concrete drawing, scissor geometry, child filtering, destruction, selection, keyboard/paste handling, and render-list reuse. `RootRenderable` additionally changes live-count propagation and replaces the rendering procedure itself.

More importantly, some overrides **replace** base behavior rather than augment it. `TextBufferRenderable.render()` replaces `Renderable.render()` rather than merely overriding `renderSelf`; likewise its `onResize()` does not call the base implementation.  If the OCaml implementation always executes a common render routine and calls a concrete `render_self`, Text can silently acquire behavior it does not currently have—for example base `renderBefore`/`renderAfter` handling.

I would explicitly define the dispatch surface. Conceptually:

```ocaml
type behavior = {
  on_update : t -> float -> unit;
  on_resize : t -> width:int -> height:int -> unit;
  on_remove : t -> unit;
  destroy_self : t -> unit;

  render : render_strategy;
  scissor_rect : t -> rect;
  visible_children : t -> visible_children_strategy;

  selection : selection_behavior;
  child_operations : child_behavior;

  render_list_policy : render_list_policy;
}
```

The names aren't important. The important distinction is that these are **replacement semantics where upstream has virtual replacement semantics**, not universally “callbacks after common behavior.”

I would also change “command generation” in the prose. The common `Renderable` should continue to own as much command generation as possible—opacity push/pop, render command placement, child traversal, clipping sequence, z-order, etc. Concrete behavior should supply the narrow variation points. Upstream's generic `updateLayout()` owns that invariant today.

### 2. Encode render-list reuse explicitly rather than reproducing prototype tricks

Upstream currently decides whether a render list can be reused partly by asking whether methods are still literally the base-class implementations:

```ts
this.onUpdate === Renderable.prototype.onUpdate
```

and similarly for custom scissor/child-filter behavior. The root also refuses reuse whenever `live_count > 0`.

That's exactly the sort of JavaScript mechanism you should **not** imitate.

The behavior record gives you a cleaner static equivalent:

```ocaml
type render_list_policy =
  | Reusable
  | Rebuild_each_frame
```

or more detailed flags if useful:

```ocaml
type traversal_behavior = {
  updates_each_frame : bool;
  custom_scissor : bool;
  filters_children : bool;
}
```

Then `Root` can calculate the equivalent of `canReuseRenderCommandList` without inspecting functions.

I would put this explicitly into the heterogeneous-renderables section because otherwise someone implementing `behavior` later may miss why function-override identity mattered upstream.

### 3. Model **three different invalidation states**

Relatedly, the document currently talks mainly in terms of dirty/layout state. Current OpenTUI actually has a useful three-way separation:

1. **Renderable dirty state** — pixels/state need redrawing.
2. **Layout generation** — calculated Yoga geometry has changed.
3. **Render-list revision** — traversal structure/order/clipping/etc. has changed.

For example, translation, opacity, z-index, visibility and structural changes bump the render-list revision, while the root compares both layout generation and render-list revision before deciding to reuse its command list.

I would add those concepts to the feature record explicitly:

```text
node dirty
    controls redraw state

layout generation
    invalidates cached geometry-dependent traversal

render-list revision
    invalidates cached traversal/ordering/clipping commands
```

They don't necessarily have to be public types. They should be architectural state.

Otherwise an implementation can easily end up with one giant `dirty` flag and either rebuild everything every frame or, worse, improperly reuse traversal state.

### 4. The root needs a stronger specification

Your statement that the root has specialized behavior is right, but there are two important details worth making explicit.

First, `RootRenderable.render()` builds the normal command list through `super.updateLayout`, but executes it starting at index **1**, deliberately skipping the root's own render command. That means the root itself is not rendered/hit-grid registered like an ordinary renderable.

I would state:

> The root participates in layout and command-list construction but is not executed as an ordinary render command and does not become an ordinary hit-grid target.

Second, I would not necessarily put root live behavior into the generic behavior record. There is a cleaner data-model translation:

```ocaml
type t = {
  ...
  parent : t option;
  live_boundary : live_boundary option;
}
```

Ordinary propagation becomes:

```text
update local live_count
    ↓
parent exists → propagate to parent
    ↓
no parent + root live boundary → request_live/drop_live on 0↔1 transition
```

That preserves the upstream override while making “rootness” an ownership boundary rather than arbitrary polymorphism. Current upstream root calls `requestLive()` only on `0 -> positive` and `dropLive()` on `positive -> 0`.

### 5. One sentence about detached renderables is currently incorrect

This sentence:

> A detached renderable remains a valid value ... and it does not receive later traversal or input dispatch.

The **input dispatch** part is too strong.

Current `remove()` detaches Yoga, removes the child from layout/z-order, unregisters the lifecycle pass and clears `parent`; it does **not** blur the child or unregister its focused keyboard/paste handlers.  Focus registered those handlers directly with the render context's internal keyboard dispatcher, and `blur()` is what unregisters them.

So a focused renderable can remain keyboard-active after detachment until something blurs or destroys it.

I'd change the invariant to something like:

> A detached renderable remains valid and no longer participates in retained-tree traversal, layout, lifecycle passes, or subsequent hit-grid construction. Detachment alone does not imply blur or destruction; focus-owned input registrations follow the reference focus lifecycle.

That is a particularly good differential test to add, whether or not you like the behavior. If you intentionally want detach to blur in OCaml, mark it as an explicit divergence.

### 6. Resolve cross-renderer reparenting now

Your ownership model says:

> A renderable receives the capabilities of its owning renderer.

That raises a question your `add` contract currently doesn't answer:

**Can a renderable created with renderer A's `Render_context.t` be attached under renderer B?**

Current TypeScript reparenting removes the old parent and assigns the new parent, but the renderable's `_ctx` is retained; `replaceParent()` does not replace its context.

That means cross-renderer attachment would produce a rather incoherent object: structurally under renderer B but still making render/focus/event calls through renderer A.

I would not reproduce that accidentally.

My preference would be to give `Render_context.t`/`Renderer.t` an abstract owner identity and require:

```ocaml
Renderable.owner child = Renderable.owner parent
```

on attachment.

A mismatch should produce whatever structured failure policy you choose. Document that cross-renderer reparenting is unsupported unless you find evidence in your pinned reference that it is intended behavior.

That makes the ownership model considerably stronger and prevents a whole family of very difficult bugs.

### 7. `Text` makes specialized child dispatch particularly important

Your Text/TextNode model is generally accurate. Upstream really does maintain a separate tree of strings and `TextNodeRenderable`s, with `StyledText` expanded into styled text nodes.  Text's lifecycle pass gathers inherited style from that tree into the text buffer before layout.

But there's a subtle consequence for the behavior-record design.

`TextRenderable` overrides:

```ts
add(...)
remove(...)
insertBefore(...)
```

to operate on its text-node tree, even though `TextRenderable` is also a `Renderable`.

Therefore, if you expose:

```ocaml
Text.as_renderable : Text.t -> Renderable.t
```

then this must not happen:

```ocaml
Renderable.add (Text.as_renderable text) some_box
```

and bypass Text's specialized child policy. Generic tree code acting on the erased `Renderable.t` has to observe the concrete object's child-operation semantics where upstream dynamic dispatch would.

This is why I would change your phrase:

> specialized child-operation validation

to something stronger:

> specialized child-operation dispatch and validation

You may still expose a richer:

```ocaml
Text.add : Text.t -> Text.child -> ...
```

for textual children, while generic `Renderable.add` only accepts `Renderable.t`. But when invoked on a Text renderable, the latter needs to reject the operation rather than silently introduce a Yoga child that upstream `Text.add()` would not create.

ScrollBox and future composite renderables will create the same issue.

### 8. Your Text destruction description is accurate

This part I would keep.

Current `Text.destroy()` clears its root text-node children first and delegates upward. `TextBufferRenderable.destroy()` then destroys the native measurement renderable, disconnects/destroys syntax style, destroys the view and buffer, and only then invokes common `Renderable.destroy()`.

The common destruction order is also worth testing at a slightly finer granularity than your current acceptance criteria. Upstream marks the node destroyed **before** emitting `destroyed`, and emits that notification while the node still has its parent. Only afterward does it detach. Blur happens later, before listeners are cleared.

So a `destroyed` listener observes:

```text
is_destroyed = true
parent = still present
```

and a focused node can subsequently emit `blurred` during the same destruction.

That's exactly the sort of strange-but-observable ordering your porting rules say should be preserved.

### 9. I would revise the current/next buffer paragraph

This paragraph worries me:

> The renderer obtains the current and next native-buffer views at construction and refreshes them when resize or screen-mode operations replace the native buffers.

At least on current upstream `main`, the renderer obtains `nextRenderBuffer` and `currentRenderBuffer` once when constructing the JS renderer.  The native renderer itself owns both buffer objects, and resize resizes those buffer objects **in place** rather than replacing them.

So unless your pinned revision differs, I'd say:

> The renderer acquires stable borrowed views of its current and next native buffers. Native resize mutates the owned buffers in place; the OCaml views remain valid until renderer teardown. If a future native operation actually replaces a buffer object, that operation must explicitly invalidate and refresh the borrowed view.

This also exposes an ownership distinction worth representing inside `Buffer.t`:

```text
Owned Buffer.t
    private renderable framebuffer / standalone buffer
    destroyable by its OCaml owner

Renderer-borrowed Buffer.t
    current/next native renderer buffer
    invalidated by Renderer.destroy
    never independently destroyed
```

The public type can remain abstract; I would make this distinction real internally.

### 10. Render-context values should be views, not copied configuration

Your `Render_context.t` formulation is good, but I'd add one sentence:

> Capabilities whose values change during renderer lifetime, including dimensions, frame identity, focus, capabilities, and selection state, are observed through the backing renderer state rather than copied when the context is created.

That heads off the temptation to implement:

```ocaml
type t = {
  width : int;
  height : int;
  frame_id : int;
  ...
}
```

and end up with stale context values.

The renderer and normal context should share **identity-bearing mutable capability sources**, not just happen to have initially equal values.

### 11. The request-during-render paragraph is now correct, but can be more exact

Your earlier docs had the wrong manual-flush model; this one fixes it.

Current renderer behavior when `requestRender()` is called during a render is to set `immediateRerenderRequested` and return. After the frame, that request is scheduled according to the max-FPS path rather than mutating the active traversal.

So I would turn:

> follows the reference scheduling rule

into an explicit invariant:

> A render request made during frame execution does not recurse into rendering or rebuild the active traversal. It records a pending immediate re-render, which is serviced after the active frame under the renderer's immediate-frame rate limit.

That will make scheduler tests much clearer.

### 12. Separate lifecycle-pass *storage* from lifecycle-pass *execution*

Minor wording issue.

The document says the root:

> owns lifecycle-pass execution

which is true enough, but the upstream registry itself is supplied by `RenderContext`: add/remove registers and unregisters lifecycle renderables through the context, while the root iterates that collection before layout.

I'd specify:

```text
Renderer/Render_context owns lifecycle-pass registration state.
Root executes the registered lifecycle passes at frame start.
```

This matters once you implement snapshot contexts.

---

## What I would change in the core concept graph

I'd make the internal picture slightly more explicit:

```text
Renderer.t
├── owner identity
├── Render_context.t ─────────────┐
├── root : Renderable.t           │ shared capabilities
├── renderer event source ────────┤
├── lifecycle-pass registry ──────┤
├── keyboard dispatcher ──────────┤
├── current/next borrowed Buffer.t│
└── scheduler / terminal runtime ─┘

Renderable.t
├── owner identity
├── stable identity / user id
├── parent + layout-order children
├── z-order children
├── private Yoga node
├── dirty state
├── layout-generation participation
├── render-list revision participation
├── live count
├── common lifecycle event channels
├── behavior
│   ├── update/resize/removal
│   ├── render strategy
│   ├── scissor / child visibility
│   ├── selection behavior
│   ├── child-operation policy
│   ├── cleanup
│   └── render-list policy
└── concrete state

Root
└── Renderable.t + root boundary
    ├── live scheduler boundary
    ├── layout calculation
    ├── command-list cache
    └── command execution (excluding root self-command)
```

That would make the architecture almost mechanically implementable.

## The main verdict

I would keep the overall design. In particular, I think these choices are right:

* **composition rather than a closed `Box | Text | ...` variant;**
* **one heterogeneous `Renderable.t` retained tree;**
* **typed concrete modules with preallocated behavior;**
* **a real `Render_context.t` capability boundary;**
* **renderer/context sharing the exact event source rather than forwarding;**
* **TextNode as a separate non-Yoga composition tree;**
* **Eio outside synchronous rendering/layout logic;**
* **`Scene` disappearing rather than remaining as an invented compatibility layer.**

The two changes I would consider blockers are **fully specifying the virtual-dispatch replacement** and **correcting detach/input semantics**. The cross-renderer ownership question should also be decided now because it affects the representation of every `Renderable.t`.

After those, the document feels suitable to drive the implementation rather than merely describe it.


As for how to approach solving the `Renderable.t` child dispatch problem:

Separate Renderable.t from child-container capabilities

This is the design I currently prefer.

Make Renderable.t represent exactly what all retained layout objects really have in common:

module Renderable : sig
  type t

  val id : t -> Id.t
  val parent : t -> t option
  val visible : t -> bool
  val destroy : t -> unit
  val request_render : t -> unit
  (* layout/render/focus/etc *)
end

Crucially:

there is no general public Renderable.add.

Then define the capability for ordinary layout children separately:

module Layout_children : sig
  type t

  val add :
    t ->
    Renderable.t ->
    int

  val insert_before :
    t ->
    Renderable.t ->
    anchor:Renderable.t ->
    int

  val remove :
    t ->
    Renderable.t ->
    unit

  val children :
    t ->
    Renderable.t list
end

A Box.t contains:

type t = {
  renderable : Renderable.t;
  children : Layout_children.t;
  (* box state *)
}

and exposes:

val as_renderable : t -> Renderable.t
val children : t -> Layout_children.t

A Scroll_box.t also exposes Layout_children.t, but its implementation delegates to the internal content node:

ScrollBox.children
       │
       ▼
Layout_children capability
       │
       ▼
internal content Renderable

That maps almost exactly to what upstream's override does today.

Text simply exposes a different capability:

module Text_children : sig
  type t

  type child =
    | String of string
    | Node of Text_node.t
    | Styled of Styled_text.t

  val add : t -> child -> int
  val remove : t -> Text_node.t -> unit
  val insert_before : ...
end

So:

Text.as_renderable text

lets generic renderer code operate on the layout object, while:

Text.children text

gives access to its text composition tree.

The important property is that this becomes impossible:

Renderable.add
  (Text.as_renderable text)
  box

because Renderable.add doesn't exist.

That isn't a limitation. It is OCaml expressing a distinction that TypeScript couldn't conveniently express.

Internally, layout attachment still exists

Obviously the retained implementation itself needs operations such as:

Renderable.Internal.attach_layout_child
Renderable.Internal.detach_layout_child
Renderable.Internal.layout_children

But those are physical tree primitives, not the component's public child API.

That gives you a clean distinction:

                    public component API

     Box.children                      Text.children
          │                                  │
          ▼                                  ▼
   Layout_children.t                   Text_children.t
          │                                  │
          │                                  ▼
          │                            TextNode tree
          │
          ▼
Renderable.Internal
physical Yoga/layout tree

For Box, public and physical children happen to coincide.

For Text, they don't.

For ScrollBox, public layout children and physical children are both renderables, but they are different subtrees.

That seems to capture the reference architecture unusually well.

However, there is the issue of "what if we need to add an ambiguous child?"

And that's where I would reach the final solution with a hybrid approach.

Upstream code can take something known only as BaseRenderable and dynamically call:

parent.add(child)

and get whatever the concrete override means. TextRenderable is allowed to reinterpret that operation because add is part of the base abstract interface.

Maybe the React/Solid-style reconciler depends on this sort of erased dispatch.

If we eventually need that behavior, I would not make it the normal public OCaml API. I'd add a narrow dynamic compatibility layer:

module Renderable.Child_surface : sig
  type t

  val of_renderable :
    Renderable.t ->
    t

  val add_dynamic :
    t ->
    Dynamic_child.t ->
    (int, error) result
end

used only by things like a generic reconciler or reference-compatibility adapter.

Then the architecture is:

Typed OCaml API
────────────────────────────────

Box.children        Text.children
     │                   │
     ▼                   ▼
Layout_children     Text_children


Optional dynamic compatibility layer
────────────────────────────────────

             Renderable.Child_surface
                       │
             concrete child dispatch

That lets you preserve upstream's generic dynamic mechanism where it is actually needed, without making every OCaml caller pay for it.

I think the capability model fits the reference better than it first appears

At first glance it looks less faithful because upstream exposes methods directly on every object.

But look at the three current semantics:

Renderable
add(x)
  └── x becomes my Yoga child

Text
add(x)
  └── x becomes a RootTextNode child

ScrollBox
add(x)
  └── x becomes a child of my internal content node

What is actually common here isn't a retained-tree operation. It's the looser conceptual property:

this component exposes some child-attachment surface.

So I'd model exactly that.

You could even generalize the tiny abstraction without losing typing:

module Children : sig
  type ('owner, 'child) t

  val add :
    ('owner, 'child) t ->
    'owner ->
    'child ->
    int

  val remove : ...
end

Then concrete modules hide the parameterization:

module Box : sig
  type t

  val add : t -> Renderable.t -> int
end

module Text : sig
  type t
  type child

  val add : t -> child -> int
end

while internally both are backed by the same generic mechanism.

But I'm not even sure the generic Children module is necessary initially. Three straightforward modules may be easier to understand than a clever abstraction.

What I would change in your design doc

Rather than saying:

The behavior record contains ... specialized child-operation validation.

I'd make child semantics separate from the render behavior record:

Renderable.t owns the physical retained-layout relationship used by traversal and Yoga. Public child operations are capabilities of concrete renderables rather than universal operations of Renderable.t. Ordinary containers expose a layout-child capability; Text.t exposes its text-composition child API; composite renderables such as ScrollBox.t may expose a layout-child capability whose operations delegate to an internal retained node. Internal physical-tree operations remain available only to retained-rendering implementations. Where a future generic reconciler requires erased child dispatch equivalent to BaseRenderable.add, that compatibility surface is implemented explicitly rather than weakening the typed core API.

I think this is a better OCaml translation than putting add into the behavior vtable.

The behavior record should answer “how does this retained node behave during rendering?” The child capability should answer “what does this concrete component consider its public children?” Those are independent axes in OpenTUI, and Text plus ScrollBox are the evidence that separating them is useful.