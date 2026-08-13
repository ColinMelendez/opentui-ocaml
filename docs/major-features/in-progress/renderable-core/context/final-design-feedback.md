I would make three substantive changes and one smaller cleanup before freezing it.

1. Keep physical child queries public even though physical child mutation is capability-based

This is the one architectural point I'd still change.

You currently say:

The implementation exposes these physical operations only to retained-rendering modules. They do not form a general public Renderable.add API.

I agree completely about mutation. But I don't think you should hide all physical-tree queries with it.

The upstream BaseRenderable contract publicly contains getChildren, getChildrenCount, getRenderable, and findDescendantById; the normal Renderable.getChildren() specifically returns its layout-order children.

That distinction actually makes your new capability model cleaner:

module Renderable : sig
  type t

  (* universal read-only retained-tree inspection *)
  val children : t -> t list
  val child_count : t -> int
  val find_child_by_id : t -> string -> t option
  val find_descendant_by_id : t -> string -> t option

  (* NO add/remove/insert_before *)
end

Then:

Box.children : Box.t -> Layout_children.t

is the public mutation capability, while:

Renderable.children (Box.as_renderable box)

is physical-tree inspection.

And importantly for Text:

Renderable.children (Text.as_renderable text)

means its physical Yoga children, just like the inherited upstream getChildren().

Whereas:

Text_children.children (Text.children text)

means its text-node children, corresponding to TextRenderable.getTextChildren().

This exposes a small wording problem in the current document. You currently say:

Text_children.children returns only the Text_node.t children, matching reference getTextChildren / getChildren.

Those aren't actually the same operation on TextRenderable. Current TextRenderable defines getTextChildren() but inherits ordinary Renderable.getChildren(), while RootTextNodeRenderable.getChildren() is the text-tree query.

I'd rewrite that to say it corresponds to TextRenderable.getTextChildren() / RootTextNodeRenderable.getChildren(), while generic Renderable.children remains the physical retained-tree query.

This preserves more of the reference API without compromising the capability design at all.

2. add needs the optional insertion index

Both proposed capabilities currently lose a real reference operation:

val add : t -> Renderable.t -> (int, Error.t) result

and:

val add : t -> child -> (int, Error.t) result

Upstream BaseRenderable.add is explicitly:

add(obj, index?)

and TextNodeRenderable.add also accepts an optional index.

So I'd make both:

val add :
  ?index:int ->
  t ->
  Renderable.t ->
  (int, Error.t) result

and:

val add :
  ?index:int ->
  t ->
  child ->
  (int, Error.t) result

That matters because insert_before isn't equivalent to arbitrary indexed insertion: you can't express every index cleanly without an existing anchor.

I'd also specify index normalization as part of the contract. TextNodeRenderable clamps insertion indices into the valid range and adjusts the index when moving a same-parent node forward through its own sequence. That's exactly the kind of small behavior differential tests should catch.

3. I would change the root-command wording

This section is slightly too clever:

The contract is the semantic skip, not a blind index-zero drop: if a later root property inserted a command before the root render command, execution would still omit only the root's own render command.

That's a reasonable interpretation of intent, but it isn't actually what the reference implements.

Current upstream literally executes:

for (let i = 1; i < this.renderList.length; i++) {
    ...
}

after building the list through the root's inherited layout traversal.

So the actual current invariant is closer to:

root updateLayout places the root render command first
+
root command execution begins at index 1

The hypothetical case where some future change inserts another command before the root render command isn't specified by today's behavior. In fact, unless upstream changed that loop too, current upstream would discard whatever ended up at index zero.

Given the overall philosophy of this port, I wouldn't infer stronger semantics than the reference demonstrates. I'd say:

The root participates in command-list construction, and the reference construction places its own render command first. Root execution skips that first command and executes the remainder of the list. The OCaml implementation preserves the resulting invariant that the root itself is not drawn or entered into the hit grid.

That is still implementation-independent enough while not inventing a future behavior.

4. Don't require the root's temporary Yoga allocation/free

This paragraph is another place where I think you're preserving an implementation artifact rather than a contract:

Construction follows the reference: the common renderable constructor creates a node, the root frees that node, and it creates a replacement node...

Upstream really does that. But I see no observable reason for OCaml to reproduce it.

The contract seems to be:

Root owns exactly one live Yoga node after construction.
That node:
  width  = context width
  height = context height
  flex-direction = column

How it gets there shouldn't matter.

I'd explicitly give yourself permission to have something like:

Renderable.Private.create
  ~layout_node:(Yoga.Node.create ...)
  ...

or:

Renderable.Private.create_root ...

rather than allocate a normal Yoga node solely to free it immediately.

This is exactly the sort of translation your document otherwise handles well: preserve ownership and final behavior, not incidental TypeScript constructor sequencing.

The rest is in very good shape

The behavior-table section now answers the concern I had before. In particular, explicitly saying that hooks have replacement semantics, that render can replace the whole per-command render strategy, and that base resize semantics aren't automatically inherited is the right way to emulate upstream virtual dispatch.

The render-list section is unusually precise now, in a useful way. Encoding upstream's method-identity tests as static policy flags is exactly the kind of mechanism translation I'd want in this port, and you've even retained the somewhat non-obvious sticky reuse behavior around live transitions. That matches the current root logic, where reuse is recomputed only on list reconstruction and canReuseCurrentRenderList() rejects a list built while _liveCount > 0.

I also like that you've resisted “fixing” strange reference lifecycle behavior. The focused-detached-node behavior and stale has_focused_descendant ancestor state are not particularly attractive semantics, but documenting and differential-testing them is consistent with the purpose of the port.

The cross-renderer restriction is also framed correctly now: it's identified as an intentional OCaml divergence, has a concrete invariant, fails before mutation, and is explicitly called out again in the translation table rather than being smuggled in as “type safety.”

And the Text destruction distinction is excellent. Current upstream really does make public clear() detach text-node parent links, while Text.destroy() simply truncates rootTextNode.children before proceeding. Your document captures that deliberately rather than flattening both into one “clean up children” operation.

One cross-document note

Your feature doc already says CONTRIBUTING.md gets updated as part of this work, which is important. The currently attached contributing guide still describes scene.ml, caller-owned flush scheduling, and the old EventEmitter translation, so it materially contradicts this final architecture today. That's not a problem with this feature record—you've explicitly planned to replace it—but I would make that docs update part of the same commit that establishes these APIs rather than leave both architectural descriptions live.

With the read-only physical query surface, indexed add, and the two places where the document currently over-specifies incidental root implementation details corrected, I wouldn't hold up implementation for another architectural pass. The Renderable.t + typed child-capability design now seems like a good foundation for extending the port to the more awkward renderables later.
