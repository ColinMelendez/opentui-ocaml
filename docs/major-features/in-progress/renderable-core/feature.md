# Renderable core and CLI renderer

Status: in progress.

This feature defines the retained-rendering spine of the OCaml OpenTUI
library. It ports the reference `Renderable`, `RenderContext`, `CliRenderer`,
`OptimizedBuffer`, `BoxRenderable`, and `TextRenderable` concepts into OCaml
modules with the same ownership and observable behavior.

The active contract is in this file. The [source correspondence
map](../../../upstream-map.md) identifies the reference paths, and the
[event-system feature record](../event-system/feature.md) defines the ordinary
event and lifecycle-channel contract used by the renderer and renderables.
The event-system [`design-ideation`](../event-system/context/design-ideation.md)
record explains why OCaml composition replaces TypeScript inheritance without
changing the reference event semantics. Keyboard routing and pointer routing
remain the [`keyboard-dispatch`](../keyboard-dispatch/feature.md) and
[`pointer-dispatch`](../pointer-dispatch/feature.md) records; this feature
owns the retained objects those systems dispatch through.

Native hit-grid storage, clipping, commit, and lookup are specified in the
[`native-hit-grid`](../native-hit-grid/feature.md) record; this feature owns
the retained render traversal that produces its native entries.

Global background color and terminal cursor/mouse-pointer presentation are
specified in the [`renderer-presentation`](../renderer-presentation/feature.md)
record; this feature owns the renderer and context capabilities that expose
those operations to retained renderables.

## Reference correspondence

| Reference source | OCaml port location | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/Renderable.ts` | `packages/opentui-core/src/renderable.ml` and `packages/opentui-core/src/layout_children.ml` | Common retained identity, physical parent/child ownership, layout state, dirty state, lifecycle, focus state, and render traversal. |
| `vendor/opentui/packages/core/src/types.ts` (`RenderContext`) | `packages/opentui-core/src/render_context.ml` and `packages/opentui-core/src/terminal_capabilities.ml` | Capabilities supplied to renderables, including dimensions, frame identity, copied terminal capability state, render requests, focus, hit-grid access, cursor/mouse-pointer presentation, and the renderer event source. |
| `vendor/opentui/packages/core/src/renderer.ts` (`CliRenderer`) | `packages/opentui-core/src/renderer.ml` | Renderer ownership, root construction, frame scheduling, layout passes, input integration, output presentation, resize, and shutdown. |
| `vendor/opentui/packages/core/src/buffer.ts` (`OptimizedBuffer`) | `packages/opentui-core/src/buffer.ml`; ABI operations remain in `packages/opentui-raw/buffer.ml` | Renderable-facing drawing operations over renderer-owned native buffers. |
| `vendor/opentui/packages/core/src/yoga.ts` | `packages/opentui-core/src/yoga.ml` | Layout-tree operations used privately by retained renderables. |
| `vendor/opentui/packages/core/src/lib/yoga.options.ts` and `lib/renderable.validations.ts` | `packages/opentui-core/src/yoga.ml` and renderable option validation | Layout-option parsing, clamping, and constructor validation used by retained renderables. |
| `vendor/opentui/packages/core/src/renderables/Box.ts` | `packages/opentui-core/src/renderables/box.ml` | Box properties, border and fill rendering, border insets, and box-specific layout options. |
| `vendor/opentui/packages/core/src/renderables/Text.ts` | `packages/opentui-core/src/renderables/text.ml` and `packages/opentui-core/src/renderables/text_children.ml` | Text content, text style, text-buffer integration, text-composition children, layout participation, and text rendering. |
| `vendor/opentui/packages/core/src/text-buffer.ts` | `packages/opentui-core/src/text_buffer.ml` | Native text storage plus Core metadata for styled text, defaults, syntax style, tab width, highlights, and text queries. |
| `vendor/opentui/packages/core/src/text-buffer-view.ts` | `packages/opentui-core/src/text_buffer_view.ml` and `packages/opentui-raw/text_buffer_view.ml` | Viewport, wrapping, native selection/local-selection, selected text, truncation, tab indicators, and visible-line calculations over a text buffer. |
| `vendor/opentui/packages/core/src/renderables/TextBufferRenderable.ts` | `packages/opentui-core/src/renderables/text_buffer_renderable.ml` | Common renderable state and drawing path for text backed by a text buffer. |
| `vendor/opentui/packages/core/src/renderables/TextNode.ts` | `packages/opentui-core/src/renderables/text_node.ml` | Styled text-node composition used by `TextRenderable`. |
| `vendor/opentui/packages/core/src/lib/styled-text.ts` | `packages/opentui-core/src/lib/styled_text.ml` | Styled text chunks and conversion from plain strings. |
| `vendor/opentui/packages/core/src/syntax-style.ts` | `packages/opentui-core/src/syntax_style.ml` | Syntax-style registration, theme resolution, merging, base-name lookup, caching, and destruction. |
| `vendor/opentui/packages/core/src/edit-buffer.ts` | `packages/opentui-core/src/edit_buffer.ml` | Pure editing state, cursor movement, history, highlights, change callbacks, syntax-style ownership, and extmark adjustment. |
| `vendor/opentui/packages/core/src/editor-view.ts` | `packages/opentui-core/src/editor_view.ml` | Visual-line calculations, wrapping, cursor/selection conversion, and the shared edit-buffer extmark owner. |
| `vendor/opentui/packages/core/src/lib/extmarks.ts` and `extmarks-history.ts` | `packages/opentui-core/src/lib/extmarks.ml` and `extmarks_history.ml` | Offset-stable marks, virtual marks, metadata, snapshots, undo, and redo. |
| `vendor/opentui/packages/core/src/renderables/Slider.ts` | `packages/opentui-core/src/renderables/slider.ml` | Independent track/thumb rendering, clamped value state, keyboard/pointer input, focusability, and change events. |
| `vendor/opentui/packages/core/src/renderables/EditBufferRenderable.ts` | `packages/opentui-core/src/renderables/edit_buffer_renderable.ml` | Edit-buffer/editor-view composition, cursor/viewport synchronization, keyboard editing, selection, paste, pointer selection, and native text rendering. |
| `vendor/opentui/packages/core/src/renderables/Textarea.ts` and `Input.ts` | `packages/opentui-core/src/renderables/textarea.ml` and `input.ml` | Placeholder/focus styling, constrained single-line input, editing, paste, submit, and typed change events. |
| `vendor/opentui/packages/core/src/renderables/ScrollBox.ts` and `ScrollBar.ts` | `packages/opentui-core/src/renderables/scroll_box.ml` and `scroll_bar.ml` | Composed scrolling subtree, culling, sticky positions, acceleration, scrollbar range state, arrows, and slider integration. |
| `vendor/opentui/packages/core/src/renderables/Select.ts` and `TabSelect.ts` | `packages/opentui-core/src/renderables/select.ml` and `tab_select.ml` | Typed option navigation, descriptions, indicators, tabs, wrapping, pointer translation, and selection/item events. |

The low-level `opentui-raw` modules remain ABI bindings. They do not replace
the core `Buffer`, `Renderable`, or `CliRenderer` counterparts.

## Public concept graph

```text
Renderer.t  (reference CliRenderer)
├── owner identity
├── Render_context.t
├── root : Renderable.t
├── children : Layout_children.t   (root layout-child capability)
├── lifecycle-pass registry
├── current and next borrowed Buffer.t views
├── renderer event source
└── scheduler, terminal output, and lifecycle ownership

Renderable.t  (reference Renderable)
├── owner identity
├── stable identity and optional user id
├── parent and public physical layout-order queries
├── private Yoga node and cached layout
├── dirty, visibility, focus, lifecycle, and live-count state
├── focused-descendant state
├── layout-generation and render-list-revision participation
├── common event source
└── behavior

Box.t
├── as_renderable : Renderable.t
└── children : Layout_children.t

Text.t
├── as_renderable : Renderable.t
├── children : Text_children.t
└── TextNode.t composition tree (not layout nodes)

Root Renderable.t
└── root boundary
    ├── live scheduler boundary
    ├── layout calculation
    ├── command-list cache
    └── command execution without the root self-command
```

`Renderer.t` is the high-level renderer corresponding to reference
`CliRenderer`. The renderer owns the root and the frame lifecycle. A caller
attaches renderables through `Renderer.children` and requests or performs
rendering through the renderer. `Renderer.root` is the root `Renderable.t`
identity; it is not a `Box.t`.

`Renderable.t` is the common retained object. Concrete renderable modules
compose it with their specialized state. OCaml does not reproduce TypeScript
inheritance; it preserves the common operations, ownership rules, lifecycle
ordering, and rendering hooks through composition. `Renderable.t` exposes
read-only physical-tree inspection (`children`, `child_count`,
`find_child_by_id`, `find_descendant_by_id`) and does not provide a public
child-attachment operation. Concrete modules expose the mutation capability
that matches their reference `add` / `remove` / `insertBefore` behavior.

`Render_context.t` is a capability view over renderer-owned state. A normal
context shares the renderer's event source and render-request mechanism. The
renderer-spine slice does not introduce isolated contexts. Snapshot contexts
are separate and own independent state only where the reference creates it.

The renderer root has a specialized root behavior even though it uses the
common `Renderable.t` representation. The root owns lifecycle-pass execution,
Yoga calculation, render-list construction and reuse, command execution, and
the live-count transition into renderer scheduling. The root participates in
command-list construction, and the reference construction places its own
render command first. Root execution skips the root render command and
executes the surrounding commands and descendants. The OCaml implementation
preserves the resulting invariant that the root itself is not drawn or
entered into the hit grid, even when a surrounding opacity or clipping
command precedes it.

The root owns exactly one live Yoga node after construction. That node has
the context width and height and column flex direction. The reference
constructor allocates a normal renderable node, frees it, and replaces it;
that sequencing is an artifact of calling `super()` and is not an OCaml
obligation. A root-specific constructor may create the final node directly.

Live propagation reaches the renderer through an explicit root boundary. An
ordinary renderable adds or removes its live-count delta from its parent. The
root boundary calls `request_live` on a `0`-to-positive transition and
`drop_live` on a positive-to-`0` transition. Root-specific scheduling is an
ownership boundary, not an arbitrary override in every concrete behavior.

The renderer scheduler observes the aggregate live-request count and keeps
frames flowing while it is positive. `request_live` records one contribution
and wakes a caller-run scheduler; `drop_live` removes one contribution and
wakes it to reconsider the idle predicate. The synchronous renderer does not
start fibers implicitly, and the scheduler does not maintain a second live
registry.

## Heterogeneous renderables

The retained tree stores heterogeneous concrete renderables behind one common
`Renderable.t` value. The OCaml representation uses a private behavior record
stored once in each renderable. Its callbacks receive the common renderable
state and the frame operation they implement; a concrete constructor supplies
the callbacks and closes over its typed specialized state.

The behavior record has replacement semantics at the same variation points as
the reference virtual methods. Its conceptual dispatch surface is:

```ocaml
type behavior = {
  on_update : t -> delta_time:float -> unit;
  on_resize : t -> width:int -> height:int -> unit;
  on_remove : t -> unit;
  lifecycle_pass : (t -> unit) option;
  render : render_strategy;
  scissor_rect : t -> rect;
  visible_children : visible_children_strategy;
  selection : selection_behavior;
  key_press : key_press_behavior;
  paste : paste_behavior;
  destroy_self : t -> unit;
  render_list : render_list_policy;
}

type render_list_policy = {
  updates_each_frame : bool;
  custom_scissor : bool;
  filters_children : bool;
}
```

The exact private types may differ, but the dispatch obligations do not. A
behavior callback replaces the corresponding reference hook when the upstream
override replaces base behavior. In particular, `render` is a complete
per-command rendering strategy, and `on_resize` does not acquire base resize
behavior unless the reference implementation calls it. Base resize emits the
size-change listener and resize notification; a replacement `on_resize` does
not acquire those unless it invokes them. The common retained tree routine
continues to own command placement, opacity push/pop, child traversal,
clipping sequence, z-order, and layout-state propagation. Concrete behavior
supplies only the variation points.

`lifecycle_pass` is registered with the renderer/context when the renderable
is attached to a new parent and unregistered when it is detached. The root
executes registered passes at frame start in registration order. Text supplies
this pass; Box does not.

`selection`, `key_press`, and `paste` are local handler slots on the retained
object. This slice stores them and invokes them at the reference lifecycle
points that the retained object owns. Keyboard routing, pointer routing, and
renderer-driven selection ownership are supplied by the keyboard-dispatch and
pointer-dispatch records; selectable text renderables provide the local
translation hooks those routes consume.

This behavior record is the OCaml counterpart of virtual and overridden
`Renderable` methods. It is not a closed `Box | Text` variant, a dynamic event
table, or an `Obj`-based escape hatch. Behavior and specialized state are
allocated at construction, not per frame. An additional concrete renderable
adds a module and a behavior factory without changing the common tree's type.

`render_list` replaces the reference's function-identity checks. A behavior
permits command-list reuse when all of the following hold at rebuild time:

- `updates_each_frame` is false;
- `filters_children` is false; and
- overflow is `visible`, or `custom_scissor` is false.

Those three flags are the translation of `onUpdate === prototype.onUpdate`,
`_getVisibleChildren !== prototype._getVisibleChildren`, and
`getScissorRect === prototype.getScissorRect`. There is no independent
`reusable` flag on the behavior. A custom scissor callback matters only when
overflow is non-visible, matching the reference conjunction.

The root stores a sticky `render_list_reusable` boolean when it rebuilds a
command list. That stored decision is true only when the root live count is
zero and every rendered behavior in the list permits reuse. A later frame
reuses the list only when the stored decision is true and the recorded layout
generation and render-list revision still match. A later live-count
transition does not clear the stored decision or bump the render-list
revision; continuous frames can therefore reuse a list that was built while
the root was not live. This preserves the reference behavior, including its
distinction between list reusability and continuous frame scheduling.

The default render strategy has this sequence: select an owned private frame
buffer when buffering is enabled; run `render_before`; draw through
`render_self`; run `render_after`; mark the renderable clean; add its cached
geometry to the hit grid; and composite its private frame buffer into the
renderer buffer. `render_before` and `render_after` are constructor options on
the common renderable, not behavior-record replacements. A full render-strategy
replacement preserves the upstream exception to this sequence.
`TextBufferRenderable` registers its hit-grid geometry before drawing its text
buffer and does not acquire the base `render_before` or `render_after` calls
unless its own strategy invokes them.

## Renderer slice

This feature ports the renderer spine before the renderer's optional terminal
services. The supported slice includes:

- renderer construction and destruction;
- root renderable and normal render-context ownership;
- current and next borrowed renderer-buffer views;
- coalesced render requests and explicit frame execution;
- lifecycle passes, Yoga layout, render-list construction, drawing, and
  presentation order;
- viewport and terminal resize propagation;
- the renderer event source shared with normal render contexts;
- focus state, focused-descendant propagation, and the focus/blur/hide/destroy
  lifecycle;
- live-render reference counting and scheduler wakeups for positive and zero
  aggregate ownership;
- hit-grid writes during command execution;
- the initial typed terminal-capability snapshot, synchronous capability-response
  processing, shared capability notifications, and one-shot forced repaint
  invalidation; and
- Eio-backed terminal input/output adapters and Unix terminal resource scopes
  at the runtime boundary. `Lib.Clock` remains an injected capability with a
  deterministic manual implementation, and the Eio clock/scheduler path is
  implemented in the separate [`scheduler` feature record](../scheduler/feature.md).

The retained core represents opacity and clipping as scoped command-list
operations. `Buffer.t` exposes typed push/pop operations for the native
opacity and scissor stacks, and the retained executor applies those commands
around child traversal while propagating native failures as structured Core
errors. The same buffer boundary includes the reference native
text-buffer-view and box drawing operations used by retained renderables.

The following remain outside this slice. This feature provides the retained
objects and seams they require; it does not implement their dispatch or
services:

- keyboard dispatch phases, global handlers, prevention, and key-release
  (`keyboard-dispatch`);
- pointer hit-testing, bubbling, capture, hover, and renderer default actions
  (`pointer-dispatch`);
- pointer selection routing and renderer-driven selection ownership for
  selectable text/editor renderables (their local translation hooks are
  connected here);
- terminal setup, output writing, and asynchronous query scheduling; Core now
  supplies transport-neutral query strings, palette parsing/normalization,
  pixel resolution, and render geometry;
- scrollback surfaces, animation services, feed-idle retries, and isolated
  snapshot contexts;
- explicit pause, suspend, and resume services beyond the live scheduler
  boundary.

The renderer frame order is retained-tree command execution, registered post
processes, diagnostic console overlay, and native presentation. Post-process
registration remains passive; a caller requests a frame or owns a live
contribution when it needs ongoing updates.

Immediate re-renders after a frame are capped at the reference default of 60
frames per second. Continuous live frames use the reference default of 30
frames per second. Those defaults are part of the scheduler contract for this
slice.

## Native and Yoga prerequisites

The `opentui-raw` Yoga API exposes independently owned nodes. The reference
uses the same ownership shape: each renderable creates its own node with
`Yoga.Node.createForOpenTUI()`, parent `insertChild`/`removeChild` do not free
the child, and `destroy()` calls `yogaNode.free()` on that one node.

This feature therefore reshapes the raw Yoga seam before retained renderables
can own layout nodes:

- a node is created independently and owned by one renderable;
- insert and remove are non-destructive;
- free is explicit on renderable destruction;
- the style operations used by `Renderable` and `Box` are available, not only
  the current width/height/padding subset. That includes display, overflow,
  flex grow/shrink/basis/direction/wrap, align, justify, min/max size, margin,
  padding, position, and gap.

Text layout also requires the reference native-measure path. `TextBufferRenderable`
creates a native renderable, attaches the existing Yoga node, and sets a
`TextBufferView` measure target. The private `opentui-raw` contract supplies
those operations to `text_buffer_renderable.ml`; they are not a public core
API on normal core modules. The nested `Private` adapters are internal
trust boundaries used by core implementations. Without that measure target,
Text cannot participate in Yoga layout with the reference geometry.

These Yoga and measure changes are part of this feature's port sequence. They
update the raw ABI documentation in the same work.

## Errors and closed state

Public retained-tree operations use a structured `Error.t` rather than the
reference's `-1`/console-warn skips. The vocabulary for this feature is:

```ocaml
type t =
  | Closed
  | Destroyed
  | Owner_mismatch
  | Not_child
  | Invalid_anchor
  | Unsupported
  | Native of Native.Error.t
```

This replaces the current scene-shaped error type. Scene-only cases such as
`Not_container`, `Not_box`, `Not_text`, `Cannot_destroy_root`, and
`Cannot_move_root` do not remain.

| Case | Result |
| --- | --- |
| Renderer already destroyed | `Error Closed` |
| Child or anchor already destroyed | `Error Destroyed` |
| Cross-renderer attachment | `Error Owner_mismatch` |
| `remove` of a value that is not a direct child | `Error Not_child` |
| `insert_before` when the anchor is missing, not a child, or is the inserted value | `Error Invalid_anchor` |
| A retained command requires a Buffer operation outside the current drawing surface | `Error Unsupported` |
| Same-parent indexed `add` whose index names another child | `Ok` inserted index; this is a layout-order move |
| Same-parent indexed `add` whose index names the inserted child | `Error Invalid_anchor`; the reference rejects a self-anchor |
| Native Yoga or buffer failure | `Error (Native _)` |

Cross-renderer attachment is a deliberate OCaml restriction. The reference
`replaceParent` does not replace `_ctx`, which would leave a child
structurally under renderer B while still calling renderer A. An ownership
mismatch fails before either tree changes.

After renderer destruction, later mutating renderer, context, and borrowed
buffer operations return `Error Closed`. `destroy` itself is idempotent and
returns no error. A destroyed renderable remains a queryable value for `id`,
`is_destroyed`, and similar observers; mutating operations return
`Error Destroyed`.

## Ownership and lifetime

- The renderer owns the native renderer, root, render context, lifecycle-pass
  registry, scheduler, and renderer-level event channels. The current and next
  `Buffer.t` values are borrowed views into native renderer buffers; the
  renderer owns their lifetime.
- A renderable owns its private Yoga node and specialized state.
- A parent owns a child's attachment and child ordering. Attaching a child to
  another parent detaches it from its previous parent according to the
  reference operation's rules. Same-parent re-attachment only moves the child
  in layout order; it does not re-run parent replacement, re-register a
  lifecycle pass, or re-propagate live count.
- A detached renderable remains a valid value until it is destroyed. Its
  parent is absent, its layout node is detached, and it no longer participates
  in retained-tree traversal, layout, lifecycle passes, or later hit-grid
  construction. Detachment does not imply blur or destruction. A focused
  detached renderable retains its focus-owned keyboard and paste registrations
  until the reference focus lifecycle blurs or destroys it.
- The common renderable destruction order is: mark the renderable destroyed;
  emit the destroyed notification while its parent is still present; remove it
  from its parent; release its private frame buffer; detach direct children
  without destroying them; blur and remove focus relationships; clear ordinary
  listeners; run common concrete cleanup; and release the Yoga node. Repeated
  destruction is harmless.
- Concrete overrides preserve their own reference cleanup order around the
  common operation. `Text` clears its text-node children and releases its
  native renderable, text-buffer-view, and text-buffer resources before it
  invokes common renderable destruction. Syntax-style state is owned by the
  separate `Syntax_style` domain module and is not part of the renderable
  lifecycle.
- `destroy_recursively` explicitly destroys descendants before destroying the
  receiver. The ordinary `destroy` operation never silently changes into
  recursive destruction.
- Destroying the renderer recursively destroys the root, then invalidates
  renderer-owned resources. Later operations follow the closed-state policy
  above.
- A renderable may own an optional private frame buffer for buffered rendering.
  The frame buffer is an owned resource that follows the renderable lifetime
  and is not exposed as a renderer-wide resource. Renderer current/next buffer
  views are borrowed resources and are never independently destroyed.
- Public APIs do not expose Yoga nodes, native buffer handles, packed handles,
  or raw pointers as retained-rendering values.

## Physical retained tree

The implementation owns a physical retained layout tree with the operations
used by the reference base class. Physical mutation remains internal to the
retained-rendering implementation. Physical queries are public on
`Renderable.t`, matching `getChildren`, `getChildrenCount`, `getRenderable`,
and `findDescendantById`:

```ocaml
module Renderable : sig
  type t

  val children : t -> t list
  val child_count : t -> int
  val find_child_by_id : t -> string -> t option
  val find_descendant_by_id : t -> string -> t option
end
```

`Renderable.children` returns layout-order physical children. It is not a
child-mutation API and does not follow a concrete component's public child
capability. `Renderable.children (Text.as_renderable text)` is therefore the
text renderable's Yoga children, as with inherited `Renderable.getChildren()`.

Internal physical mutation:

- construction establishes the renderer context, identity, layout node,
  visibility, opacity, focusability, and initial layout options;
- attach attaches a renderable at the end of the parent's layout order or at a
  requested index;
- insert-before attaches a renderable before an existing sibling;
- detach removes a direct child without destroying, blurring, or unregistering
  focus-owned input handlers;
- user-facing identifiers and internal numeric identities remain distinct;
- visibility changes update layout participation and request a render;
- any visibility change on a focused renderable blurs it and removes its
  focus-owned keyboard and paste registrations, matching the reference setter.
  Becoming visible does not restore focus;
- property changes preserve reference validation, clamping, no-op behavior,
  layout invalidation, and render invalidation;
- `request_render` marks the owning renderable dirty and reaches the renderer's
  coalesced frame-request boundary;
- `live` marks a renderable as requiring continuous work, and `live_count`
  propagates through parent attachments to the root's renderer scheduling
  boundary. A node's own live contribution is active only while it is visible;
  parent visibility does not suppress a child's propagated count;
- render traversal visits visible, non-destroyed renderables regardless of
  their `live` value and preserves the reference layout, z-order, clipping,
  and parent-child rules;
- layout readback caches screen coordinates per frame identifier and clamps
  computed width and height to a minimum of 1, matching
  `updateFromLayout`; and
- focus sets `has_focused_descendant` on each current ancestor and marks those
  ancestors dirty; blur clears that state on each current ancestor when the
  renderable remains attached. Detaching a focused renderable does not blur it,
  so previous ancestors retain the reference's stale focused-descendant state.
  Destruction also leaves that state stale because destruction removes the
  renderable from its parent before it calls `blur`.

Layout order and visual order are separate where the reference keeps them
separate. Layout order controls Yoga child positions. Visual order accounts
for z-index and the reference render traversal. Hit-grid writes follow render
order. Pointer hit-testing and bubbling consume that grid in the
pointer-dispatch record.

The implementation exposes physical attach, insert-before, and detach only to
retained-rendering modules. They do not form a general public `Renderable.add`
API.

## Public child capabilities

Public child operations belong to concrete components because OpenTUI gives
different concrete renderables different meanings for `add`, `remove`, and
`insertBefore`.

An ordinary layout container exposes a typed `Layout_children.t` capability:

```ocaml
module Layout_children : sig
  type t

  val add :
    ?index:int -> t -> Renderable.t -> (int, Error.t) result
  val insert_before :
    t -> Renderable.t -> anchor:Renderable.t -> (int, Error.t) result
  val remove : t -> Renderable.t -> (unit, Error.t) result
end
```

`Layout_children.add` without `index` appends. With `index`, if that index
names an existing layout child, the operation follows reference
`add(obj, index)` through `insertBefore` and inserts before that child. An
index that names the value being inserted is therefore `Error Invalid_anchor`,
matching the reference self-anchor rejection. If the index is out of range,
the child is appended. `insert_before` remains the API that names a sibling;
indexed `add` is not equivalent to every `insert_before` call, and the reverse
is also false.

Concrete modules expose that capability with a uniform accessor pair:

```ocaml
module Box : sig
  type t

  val create : Render_context.t -> (* labelled options *) -> t
  val as_renderable : t -> Renderable.t
  val children : t -> Layout_children.t
end

module Renderer : sig
  type t

  val root : t -> Renderable.t
  val children : t -> Layout_children.t
end
```

`Renderer.children` is the root's layout-child capability, used to attach
application renderables. A future composite such as `Scroll_box.t` exposes
`val children : t -> Layout_children.t` whose operations delegate to its
internal content renderable.

`Text.t` exposes a separate text-composition capability:

```ocaml
module Text : sig
  type t

  val create : Render_context.t -> (* labelled options *) -> t
  val as_renderable : t -> Renderable.t
  val children : t -> Text_children.t
end

module Text_children : sig
  type t

  type child =
    | String of string
    | Node of Text_node.t
    | Styled of Styled_text.t

  val add : ?index:int -> t -> child -> (int, Error.t) result
  val remove : t -> Text_node.t -> (unit, Error.t) result
  val insert_before :
    t -> child -> anchor:Text_node.t -> (int, Error.t) result
  val children : t -> Text_node.t list
  val clear : t -> unit
end
```

The internal text-composition tree stores strings and `Text_node.t` values.
`Text_children.children` returns only the `Text_node.t` children, matching
`TextRenderable.getTextChildren()` and `RootTextNodeRenderable.getChildren()`.
`Renderable.children (Text.as_renderable text)` remains the physical Yoga
query and is a different operation. String children stay in the composition
tree and participate in style gathering; they are not in the
`Text_children.children` list. `Styled` input expands into text nodes and
strings at insertion time. Text-node children do not become Yoga children.

`Text_children.add ~index` preserves the reference index rules. A
`Text_node.t` insertion clamps the index into the valid range and, when moving
a same-parent node forward through its own sequence, subtracts one after
removing it from its current position. A string or styled-text insertion uses
the reference splice path at the requested index rather than that clamp.

`Text.as_renderable` supplies the common rendering, layout, lifecycle, and
focus operations; it does not supply a general child-attachment operation that
could bypass `Text_children`.

Cross-renderer attachment is unsupported. Every renderable and every layout
child capability carries an abstract owner identity. `Layout_children.add`,
`insert_before`, and equivalent internal attachment operations require the
child and parent to have the same owner identity. An ownership mismatch is
`Error Owner_mismatch` and does not detach or partially attach the child.

An erased child surface is not part of the renderer-spine slice. If a future
generic compatibility adapter needs the reference `BaseRenderable.add`
behavior, it receives an explicit `Renderable.Child_surface` module rather
than weakening `Renderable.t` or the typed child capabilities. That adapter
dispatches to the concrete child capability and remains separate from normal
application code.

## Invalidation and cached traversal

The retained renderer tracks three independent invalidation states:

- renderable dirty state means that a node's pixels or state require redraw;
- layout generation identifies the Yoga geometry calculation used by cached
  layout-dependent traversal; and
- render-list revision identifies changes to traversal structure, ordering,
  clipping, opacity, or hit-grid command construction.

Structural attachment and detachment, visibility, opacity, z-index, overflow,
scissor behavior, child filtering, and other traversal-affecting properties
bump the render-list revision. Yoga-affecting properties invalidate layout.
Drawing or content mutations mark the affected renderable dirty. A root Yoga
calculation advances the layout generation, and an externally observed new
layout advances it when the native layout state changes.

The root records the layout generation and render-list revision used to build
the current command list and stores the reusable decision made during that
build. It rebuilds the list when the stored decision is false or when either
recorded generation differs. A live-count transition alone does not invalidate
the stored decision. A clean node or a reusable command list does not suppress
drawing of visible non-destroyed renderables when the reference requires a
frame.

## Render context contract

The context exposes the capabilities that reference renderables use without
making them depend on the concrete renderer representation. This slice
includes:

- an abstract renderer-owner identity;
- terminal and viewport dimensions;
- a monotonic frame identifier;
- the current copied terminal-capability snapshot, updated by recognized
  responses and published through the shared renderer event source;
- palette state, pixel resolution, screen mode, footer height, and computed
  render geometry;
- render-request and lifecycle-pass registration;
- hit-grid construction and scissor state;
- focus ownership;
- first-line-offset claims used by text-buffer renderables; and
- the renderer event source.

Cursor presentation, pointer presentation, selection ownership, and the
keyboard dispatcher capability are seams on the same context object because
the reference `RenderContext` carries them. Terminal cursor and mouse-pointer
presentation now forward through the owner-scoped context capability. This
slice does not implement the keyboard dispatcher, pointer hit-testing, or
pointer capture. Native text-view selection and selectable-renderable
coordinate translation are implemented behind those seams, so programmatic
Core selection and captured pointer selection reach native drawing while route
ownership remains in the dedicated pointer-dispatch feature.

The context does not create a second renderer, event source, layout tree, or
input queue. A renderable receives the capabilities of its owning renderer.
Dimensions, frame identity, terminal capabilities, focus, and other values
that change during renderer lifetime are observed through shared renderer
state; they are not copied into a stale context record at construction. The
renderer/context pair shares identity-bearing capability sources, not only
initially equal values. The capability snapshot itself is a copied immutable
value from the raw binding; each recognized response replaces that value and
emits one synchronous notification. Terminal query/setup remains an outer
runtime concern until its Eio output boundary is ported. The renderer/context
owns lifecycle pass registration state, and the root executes the registered
passes at frame start.

## Frame and layout contract

The renderer performs a frame in the reference order:

1. accept a coalesced render request or an explicit render request;
2. run registered lifecycle passes before layout calculation;
3. calculate the Yoga layout for the retained tree;
4. update cached renderable positions and dimensions and build the render
   command list;
5. execute the command list, including drawing, clipping, opacity, and hit-grid
   updates. Construction places the root render command first; execution
   skips the root render command and runs the remainder;
6. hand the completed next buffer to the native renderer and present it.

The low-level buffer operation remains synchronous. The Eio runtime owns
terminal I/O, scheduling, cancellation, and resource scopes around this
operation; it does not change the retained-tree or buffer semantics.

The renderer frame applies registered post-processing effects, renders the
diagnostic console overlay, and then presents natively. Post registration is
passive; callers request a frame or own a live contribution when an effect
needs ongoing updates.

The renderer obtains the current and next native-buffer views at construction
and keeps them as borrowed views. Native resize mutates the owned buffers in
place; the views remain valid until renderer teardown. If a future native
operation replaces a buffer object, that operation explicitly invalidates and
refreshes the borrowed view. Presentation does not require the OCaml core to
swap or recreate those views after every frame. Resize also refreshes the
borrowed view dimensions, or makes the accessors read the current dimensions
from the renderer-owned state; callers never observe stale dimensions.

A renderable may request another frame while it is outside a render pass. A
render request during a render pass does not recurse into rendering or rebuild
the active traversal. It records a pending immediate re-render, which is
serviced after the active frame under the 60 fps immediate-frame cap. Dirty
state, frame requests, layout calculation, and presentation remain distinct
states. The explicit frame contract tests both the immediate re-render path
and the continuous scheduling path used when the root live count is nonzero.

## Concrete renderables

`Box.t` and `Text.t` are concrete renderables. Callers attach them through
`Layout_children.add` on the renderer root or another layout container. Their
constructors receive the owning render context and typed options; they do not
receive caller-owned Yoga nodes or raw buffers.

`Box.t` preserves the reference box behavior for background color, border
selection and style, border color, fill policy, border insets, and box-specific
layout properties. Its layout contract includes border sides and `gap`,
`row_gap`, and `column_gap`; its drawing contract includes titles, focused
border color, custom border characters, fills, and scissor insets derived from
the active border sides. Buffer-backed drawing operations are separate from
the retained layout capability. Box drawing is issued synchronously through
the renderer-owned buffer. Opacity and scissor stack commands remain separate
renderer seams and return `Error Unsupported`.

`Box.as_renderable` is the value stored in the retained tree.
`Box.children` is the public layout-child mutation capability.
`Renderable.children (Box.as_renderable box)` inspects the same physical
layout children. Generic retained-tree code uses internal physical attachment
operations rather than a universal child method on `Renderable.t`.

`Text.t` preserves the reference text-renderable relationship with the text
buffer, text-buffer view, text-node, and styled-text layers. A plain string is
a valid convenience input, but the core type does not reduce the reference
text model to a permanent single-string drawing helper. Text mutation
invalidates the retained node and updates the text-buffer state used by layout
and native text-view rendering. Global and local selection methods on the
text-buffer renderable update both Core metadata and the native text view;
renderer-driven selection from pointer input is connected for the selectable
text-buffer and editor renderables. Edge auto-scroll during a drag is owned by
`Scroll_box`: it uses the renderer-owned `on_update` callback and one guarded
`Render_context` live contribution while the pointer remains in the edge
region.

`TextNode.t` is a separate text-composition tree. It has no Yoga node and does
not participate in the retained layout tree. `Text.t` owns a root text node;
`Text.children` targets that text tree. `Renderable.children` queries physical
Yoga children; `Text_children.children` queries retained text-node children.
A lifecycle pass gathers inherited text-node styles into the text buffer
before the frame calculates layout.

`Text.t` does not expose `Layout_children.t`. Generic code cannot add a Yoga
child through `Text.as_renderable`.

`Text_children.clear` is the text-composition operation: it removes the
text-node children, clears their parent links, and requests a render.
`Text.clear` is the higher-level content operation: it clears the text-node
tree, installs empty styled text, updates text-buffer information, and requests
a render. Text destruction clears the root text-node child sequence before
releasing text-buffer resources. Destruction preserves the reference distinction
between direct sequence clearing and public clearing: public clearing detaches
child parent links, while destruction does not issue those parent-link updates
for its discarded child sequence.

Concrete renderable event vocabularies compose with the common renderable
lifecycle channels. The event-system record defines channel semantics; this
feature defines which owner supplies them. `Renderable` supplies focused,
blurred, and destroyed. The root supplies layout-changed and resized. Text
supplies line-info-change.

## Translation boundaries

The following boundaries keep the port close to OpenTUI while using OCaml
ownership and type systems:

| Reference mechanism | OCaml translation |
| --- | --- |
| TypeScript base-class inheritance | Composition of `Renderable.t` with concrete module state. |
| `CliRenderer implements RenderContext` | `Renderer.t` owns a `Render_context.t` that shares renderer capabilities and event channels. |
| Constructor option bags | Labelled arguments and typed option records with reference defaults and validation. |
| `OptimizedBuffer` native views | Core `Buffer.t` over checked `opentui-raw` ownership bindings. |
| Renderer current/next buffers | Borrowed `Buffer.t` views owned and invalidated by `Renderer.t`; they are not independently destroyable. |
| Yoga node fields and methods | A private Yoga node owned by each renderable, inserted into and detached from the parent's private layout tree by retained-tree operations. |
| `requestRender()` | Dirty invalidation plus renderer-owned coalesced scheduling. |
| Base `add`/`remove`/`insertBefore` methods | Typed `Layout_children.t` or `Text_children.t` mutation capabilities; no public child mutation on `Renderable.t`. |
| `getChildren` / `getChildrenCount` / `getRenderable` / `findDescendantById` | Public read-only queries on `Renderable.t` over the physical layout-order tree. |
| `EventEmitter` inheritance | Typed owner-local channels defined by the event-system feature record. |
| Keyboard and pointer handler dispatch | Dedicated dispatch systems defined by the keyboard and pointer feature records. This feature owns focus state, hit-grid writes, and local handler slots. |
| Terminal input stream | `Stdin_parser`, `Input_coordinator`, and Eio input flow retain their existing ownership and backpressure contracts. |
| Method-identity render-list reuse | `render_list_policy` flags plus the root's sticky reuse decision. |
| Cross-renderer `replaceParent` leaving `_ctx` unchanged | `Error Owner_mismatch` before either tree changes. |

The translation preserves reference behavior first. An OCaml-specific
representation is acceptable only when it keeps the same observable
validation, ordering, lifetime, scheduling, and error decisions, except for
the documented `Owner_mismatch` restriction and structured results in place
of `-1`/warn skips.

## Port sequence

The implementation follows the reference dependency order:

1. reshape the raw Yoga seam so a node can be created, inserted, detached
   without destruction, and freed explicitly, and so the style operations
   used by retained renderables are available;
2. establish the core `Buffer.t` boundary over the existing checked raw
   buffer operations;
3. establish `Renderer.t` and `Render_context.t` with shared renderer
   capabilities, replacing the current low-level frame-wrapper `Renderer.t`
   and deleting `Scene` rather than wrapping it;
4. implement the common `Renderable.t` ownership, tree, layout, dirty-state,
   lifecycle, live-count, behavior-dispatch, invalidation, and traversal
   operations;
5. establish the internal physical layout-child operations and the public
   `Layout_children.t` capability, then port the reference Box behavior onto
   the common renderable;
6. add the native-measure and text-view ABI used by text-buffer renderables,
   then port the text-buffer, text-buffer-view, styled-text, and
   text-buffer-renderable dependencies;
7. establish the independent syntax-style, edit-buffer, editor-view, extmark,
   palette, geometry, and selection foundations;
8. port the TextNode tree and Text behavior, including lifecycle-pass
   synchronization into the text buffer; and
9. connect the dedicated keyboard and pointer dispatch systems to the
   renderer, focus lifecycle, hit-grid, and renderable handler slots.

`Scene` is not part of this port sequence. It is not a reference OpenTUI
concept and does not remain as a compatibility facade around the new modules.
The contributor translation table in `CONTRIBUTING.md` is updated in the same
work so it no longer maps `Renderable.ts` or `CliRenderer` to `scene.ml`.

## Acceptance criteria

The feature satisfies these criteria when:

- the source correspondence map points each reference path to the feature
  record and its concrete OCaml module, and `CONTRIBUTING.md` no longer
  describes `Scene` as the retained tree;
- `Renderer.t` exposes the high-level renderer/root relationship rather than
  only a low-level frame wrapper;
- `Renderable.t`, `Render_context.t`, and `Buffer.t` have no public dependency
  on `Scene`, raw handles, or caller-owned Yoga nodes;
- Box and Text attach through `Renderer.children` or `Box.children`, and
  `as_renderable` is the value stored in the retained tree;
- `Renderable.children` reports physical layout-order children, including
  empty Yoga children on Text, while `Text_children.children` reports
  text-node children;
- indexed `add` preserves the reference index rules for layout children and
  for text-node, string, and styled-text insertions;
- tree insertion, removal, same-parent reorder, destruction, visibility,
  identity, dirty state, layout, and render order have black-box tests;
- behavior tests prove replacement semantics for resize, rendering, removal,
  scissor, child filtering, cleanup, and render-list reuse policy;
- dirty state, layout generation, and render-list revision remain distinct and
  produce the reference command-list reuse decisions;
- tests distinguish nonrecursive destruction from explicit recursive
  destruction and verify that detached children remain valid;
- a focused detached renderable remains focused until blur or destruction;
- hiding a focused renderable blurs it and does not restore focus when it
  becomes visible;
- destruction tests verify common resource order, focus cleanup, and the
  text-renderable cleanup boundary;
- renderer shutdown uses recursive root destruction, and later operations
  return `Closed`;
- live-state transitions update ancestor live counts and renderer scheduler
  wakeups without excluding non-live visible nodes from drawing;
- TextNode tests prove that text composition is separate from Yoga layout
  children, that `Text_children.children` returns nodes rather than strings,
  and that Text child operations use the text-node tree;
- focused-descendant propagation and the reference stale-ancestor state after
  focused detachment or destruction are covered by differential tests;
- cross-renderer attachment returns `Owner_mismatch` before changing either
  tree;
- the root participates in layout and command-list construction, execution
  skips the first command, and the root is not drawn or entered into the hit
  grid;
- borrowed renderer buffers are not independently destroyed and become invalid
  with their renderer, and their dimensions remain current after resize;
- renderer and render-context tests prove shared capability and event-source
  ownership;
- capability tests prove upstream response recognition, bounded pixel parsing,
  copied terminal strings, synchronous shared notifications, response
  consumption, and repaint invalidation;
- a small Eio-native application creates a renderer, attaches Box and Text
  through `Renderer.children`, renders, mutates Text in place, resizes,
  destroys a child, and shuts down;
- analogous reference fixtures compare rendered output and tree behavior for
  the supported slice; and
- existing parser, input-handoff, and terminal-lifecycle contracts remain
  unchanged, except for the Yoga and native-measure ABI expansions required
  by this feature.

Keyboard delivery and pointer bubbling are accepted by their own feature
records. Programmatic text-view selection is part of the current native view
contract, and renderer-driven pointer selection is connected for the active
selectable text/editor renderables. Pointer ownership and capture remain
pointer-dispatch responsibilities; ScrollBox owns drag-edge auto-scroll once
selection is active.

The feature record moves to
`docs/major-features/implemented/renderable-core/` when these criteria are
satisfied.
