# OpenTUI-shaped renderable architecture

> Archived on 2026-08-11. The current source-tree correspondence and
> translation rules are in [`../upstream-map.md`](../upstream-map.md) and
> [`../architecture.md`](../architecture.md).

Status: active implementation direction, 2026-08-11. This note records the
direct OpenTUI-shaped architecture and the boundaries that the later Lwd
bridge must not collapse.

The pinned OpenTUI implementation gives us a useful low-level shape even
though its TypeScript surface is not a suitable OCaml API to copy literally.
Its retained renderables own persistent identity, layout participation, local
widget state, children, event handlers, and native rendering behavior. React
and Solid are separate reconciliation layers over those renderables. The
experimental core `VNode`/constructs API is explicitly non-reactive and is not
the foundation for this project.

The project should therefore mirror OpenTUI's retained semantics and major
renderable vocabulary while replacing JavaScript-specific mechanisms with
typed, explicit, allocation-conscious OCaml concepts.

Reference files:

- `vendor/opentui/packages/core/src/Renderable.ts`
- `vendor/opentui/packages/core/src/renderables/`
- `vendor/opentui/packages/core/src/renderables/composition/README.md`
- `vendor/opentui/packages/react/src/reconciler/host-config.ts`
- `vendor/opentui/packages/solid/src/reconciler.ts`

## Target package graph

```text
opentui-native
    │
opentui-core
    ├── imperative retained renderables
    ├── layout, identity, event propagation, and frame invalidation
    │
opentui-widgets                 direct OpenTUI-shaped content and controls, later
    ├── editor support, content renderables, input, select, scroll, and controls
    │
opentui-lwd                     later bridge
    ├── Lwd bindings over the direct core tree (core dependency only)
    │
optional application adapter   later, only if useful
    └── Elm-like Model / Msg / Update / Cmd policy
```

`opentui-core` and `opentui-widgets` must remain usable without Lwd. A caller
should be able to construct a retained scene, mutate renderables and controls,
dispatch events, and flush a frame without importing a reactive package.
`opentui-lwd` should bind values and keyed collections to that tree; it should
not replace the tree with a second virtual representation. It depends on
`opentui-core`, not on `opentui-widgets`; control-specific reactive adapters
would be a separate package only if direct control callers demonstrate a need.

## What we mirror

The following are behavior and vocabulary targets, not a promise of source
compatibility with TypeScript:

- persistent renderable identity across ordinary property updates;
- parent/child ownership and explicit child ordering;
- layout invalidation followed by a controlled frame flush;
- local state for stateful controls such as inputs and scrollable views;
- typed event propagation and teardown boundaries;
- core renderable names with recognizable OpenTUI counterparts such as `Box`
  and `Text`;
- extension points for custom renderables and custom widget behavior;
- tests and examples that can be translated conceptually from the pinned
  OpenTUI implementation.

Stateful widget vocabulary such as `Input`, `Select`, `Textarea`, and
`Scroll_box` is part of the Phase 6 direct content-and-control track. It should
be built in `opentui-widgets` after the direct core renderable contracts are
useful and before the later Lwd bridge, rather than making the Phase 5 core
gate open-ended.

The adoption path is semantic rather than source-compatible. TypeScript
option objects, inheritance, and callbacks cannot be carried over unchanged,
but a user familiar with OpenTUI should recognize the tree, the lifecycle,
the renderable names, and the update behavior.

## JavaScript concepts and OCaml replacements

These are the current replacement candidates. They are deliberately explicit
so reimplementation does not repeatedly reopen the same design question.

| OpenTUI concept | OCaml direction | Invariant or reason |
| --- | --- | --- |
| `BaseRenderable`/`Renderable` class hierarchy | An abstract owned node with typed modules for renderable kinds | Do not expose inheritance or a JavaScript-style universal mutable object. Keep identity and ownership in one narrow core. |
| Constructor option objects | Labelled constructors plus typed option records where a group is genuinely reusable | Invalid dimensions, colors, and layout values are rejected at the boundary; no `any`-shaped property bag. |
| Public mutable properties | Typed setters or property combinators | A changed value marks the correct node/scene dirty; equal values do not cause redundant native calls. |
| `EventEmitter` and `onFoo` fields | Typed event registration returning an owned subscription/cleanup value | Event payloads are typed, callback lifetime is explicit, and teardown can remove callbacks without a string event namespace. |
| `requestRender()` on arbitrary nodes | Scene invalidation plus a caller-owned frame scheduler | Many mutations coalesce into one controlled `flush`; the core does not secretly start an event loop or perform I/O. |
| `destroyRecursively()` | Explicit node destruction combined with a scope/lifetime owner | Native resources and callback registrations are released deterministically; stale nodes fail loudly. |
| `VNode`, `h`, and `VRenderable` | Optional `Constructs` convenience layer after the imperative API | The pinned composition API is exploratory and non-reactive; it must not become a second mandatory tree or identity system. |
| React/Solid reconciler | `opentui-lwd` property and keyed-child bindings | Lwd invalidation updates persistent nodes rather than producing a full `Lwd.t<Ui>` virtual tree. |
| Dynamic `children` arrays | Explicit child operations and a keyed collection binding | Key identity, reorder, insertion, removal, and teardown are observable contracts, not incidental list diffs. |
| String component catalogue | Typed constructors and a narrow extension registration mechanism, if needed | Core callers should not depend on runtime string lookup; extensions must preserve ownership and type invariants. |
| `null`/`undefined` props | `option` values or named clear/remove operations | Absence and clearing are distinct from an arbitrary JavaScript sentinel. |
| Ambient renderer/context lookup | Explicit scene, parent, and lifetime arguments | Dependencies and ownership remain visible; no hidden global renderer state. |
| Portals and overlays | A later mount/overlay target value with explicit ownership | An overlay is a second parent/target relationship, not a special escape from the ownership tree. |
| Framework hooks and lifecycle callbacks | Lwd roots/effects plus explicit scope cleanup | Reactive lifetime and native lifetime must be released together at the binding boundary. |
| Mutable JavaScript fields for widget state | Module-owned abstract state with domain operations | State remains local and efficient without publishing representation or making every field a generic property. |

The table is a design parking lot, not permission to add every replacement as
a public abstraction. A candidate earns a public name only when it appears in
common caller code and removes more complexity than it adds.

## Intended caller paths

### Imperative retained path

The first path should be direct and independent of Lwd:

```ocaml
let panel = Box.create ~parent:root ~width:80.0 ~height:20.0 () in
let status = Text.create ~parent:panel ~text:"waiting" () in
Text.set status ~text:"ready";
Scene.flush scene
```

This is a conceptual sketch, not the committed signature. It demonstrates
the intended ownership: `panel` and `status` survive the update, while the
setter marks only the affected retained state.

### Lwd binding path

The reactive layer should attach to those same nodes:

```ocaml
let status = Lwd.var "waiting" in
let label = Text.create ~parent:panel ~text:"waiting" () in
let _binding = Lwd_bind.text ~node:label status in
Lwd.set status "ready";
Runtime.frame runtime
```

The binding samples invalidated Lwd roots, applies the smallest necessary
property changes, and lets the existing scene flush once. It does not create
a fresh virtual render tree for each value of `status`.

### Optional application-policy path

An Elm-like adapter can later own application state and effects without
becoming a dependency of the core:

```ocaml
type msg = Increment | Reset
type model = { count : int }

let update msg model =
  match msg with
  | Increment -> { count = model.count + 1 }
  | Reset -> { count = 0 }
```

The adapter would translate messages into Lwd updates and commands into an
effect runtime. The renderable and Lwd layers should remain usable without
this policy.

## Decisions still requiring focused design

- whether the common retained type is one abstract `Node.t` with typed
  modules, or a small family of abstract renderable types sharing flat
  accessors;
- whether subscriptions need a public `Subscription.t` or can be represented
  by scope-owned cleanup functions;
- how keyed collection bindings represent keys and preserve node identity;
- how styles and layout properties are grouped without reproducing one giant
  JavaScript option object;
- how focus and overlay ownership fit the existing scene root;
- whether an Elm-like adapter earns a package after the imperative and Lwd
  paths have real callers.

These decisions should be settled from caller snippets, the pinned OpenTUI
behavior, and allocation measurements. They should not be resolved by copying
the TypeScript class graph.

## Implementation order and acceptance

1. Extend the retained core with a small OpenTUI-shaped primitive slice,
   starting with Box and text behavior over the existing stable
   identity, layout, flush, pointer, and teardown contracts.
2. Add typed property/update operations with equality cutoffs and allocation
   measurements before widening the property surface.
3. Add direct test apps and docs for each implemented core renderable family,
   then build the remaining content, editor-supporting, and stateful families
   in `opentui-widgets` without an Lwd dependency.
4. Build `opentui-lwd` bindings over those imperative nodes, proving that a
   signal update preserves node identity and batches into one flush.
5. Consider a convenience `Constructs` layer and an Elm-like application
   adapter only after the direct and Lwd paths are useful.

The direct-renderable track must demonstrate applications that preserve node
identity across ordinary updates, release all nodes on teardown, and have
deterministic output/event tests. The later Lwd track must add the corresponding
binding cleanup and allocation/frame evidence. API familiarity is useful only
if these ownership and performance contracts remain visible.

## Direct conformance map

This map keeps “copy the architecture” concrete without making one phase an
open-ended promise to port every upstream feature at once. Each row gets a
typed OCaml module, a direct example, black-box behavior tests, and a reference
comparison when the observable behavior is comparable.

| Reference family | OCaml home | Direct-track status |
| --- | --- | --- |
| `Renderable` tree and lifecycle | `opentui-core.Scene` and typed renderable modules | retained identity, ordering, invalidation, pointer propagation, and teardown exist; typed surface is expanding |
| `BoxRenderable` | `opentui-core` | first implementation slice and direct executable example exist |
| `TextRenderable`, `TextBufferRenderable`, `TextNodeRenderable` | `opentui-core` | plain copied text and a direct update example exist; styled text and nested text nodes are Phase 5 foundational text follow-ons; `opentui-native` remains their lower-level drawing seam |
| `EditBufferRenderable`, `LineNumberRenderable`, `TimeToFirstDrawRenderable`, `ASCIIFontRenderable` | `opentui-widgets` | deferred supporting families with a direct Phase 6 home; each needs a contract and example |
| `FrameBufferRenderable`, `ImageRenderable`, `CodeRenderable`, `DiffRenderable`, `MarkdownRenderable`, `TextTableRenderable` | `opentui-widgets` | deferred content/rendering families with a direct Phase 6 home; each needs a contract and example |
| `InputRenderable`, `TextareaRenderable`, `SelectRenderable`, `ScrollBoxRenderable`, `SliderRenderable`, `TabSelectRenderable`, `ScrollBarRenderable` | `opentui-widgets` | deferred Phase 6 stateful control families; no Lwd dependency is implied |
| composition `VNode`/constructs | optional convenience module | intentionally deferred; not a second identity tree |
| React/Solid host reconcilers | `opentui-lwd` plus any later bridge | later bridge over the direct tree, never the prerequisite for direct examples |
