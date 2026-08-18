# Native hit-grid ownership

Status: in progress.

This feature moves hit-grid storage, clipping, commitment, and lookup back to
the native renderer. It restores the reference ownership boundary while
leaving retained-tree traversal, renderable identity, pointer dispatch, and
event policy in OCaml.

The active pointer-routing contract is in the
[`pointer-dispatch`](../pointer-dispatch/feature.md) feature record. This
record defines the storage and producer boundary that pointer dispatch
consumes. It does not move terminal mouse decoding or pointer-event bubbling
into native code.

Global background color and terminal cursor presentation are specified by the
[`renderer-presentation`](../renderer-presentation/feature.md) record. They
are renderer-owned presentation state, not part of hit-grid storage.

## Purpose

The current OCaml implementation keeps `current` and `next` hit grids as
integer arrays in `Render_context`. That was a practical seam while the raw
renderer ABI exposed only drawing and buffer operations. It is not the desired
long-term design: it duplicates native renderer state, performs a full-grid
OCaml clear and commit, and makes it possible for hit-testing and native frame
presentation to observe different sources of truth.

The reference renderer owns both hit grids in native memory. Renderable
execution writes the next grid through native operations; pointer input reads
the committed current grid through the same owner. The OCaml port adopts that
model through a small, typed raw capability rather than mirroring native
storage in Core.

## Reference correspondence

| Reference source | OCaml correspondence | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/zig/renderer.zig` (`currentHitGrid`, `nextHitGrid`) | Native renderer state built by `opentui-raw` | Own grid dimensions, current/next storage, scissor state, swap, clearing, and dirty tracking. |
| `vendor/opentui/packages/core/src/zig/renderer.zig` (`addToHitGrid`, `checkHit`, `commitPendingHitGrid`) | `packages/opentui-raw/renderer.ml` and native ABI bindings | Provide allocation-free producer and lookup operations over the native owner. |
| `vendor/opentui/packages/core/src/zig/lib.zig` hit-grid exports | `packages/opentui-raw/native/opentui_abi.h`, `native.ml`, and `raw_stubs.c` | Keep the foreign function surface explicit, typed, and below `opentui-core`. |
| `vendor/opentui/packages/core/src/renderer.ts` hit-test and dirty-grid handling | `packages/opentui-core/src/renderer.ml` | Ask native for the target ID, resolve it through the OCaml renderable registry, and recheck hover only when the committed grid changed. |
| `vendor/opentui/packages/core/src/Renderable.ts` render-time hit-grid registration | `packages/opentui-core/src/renderable.ml` and `render_context.ml` | Produce native hit-grid entries while executing retained render commands. |
| `vendor/opentui/packages/core/src/renderables/RootRenderable.ts` hit-grid scissor setup | `packages/opentui-core/src/renderable.ml` root execution | Reset and scope native hit-grid scissors around the retained render traversal. |

The native source is copied into the generated build tree by the existing
`opentui-raw` build process. Any local ABI addition belongs in the tracked raw
header/stub/build patch seam; the vendored reference source is not edited as a
side effect of this feature.

## Ownership model

```text
OCaml retained tree and Yoga layout
        │  render command execution
        ▼
Render_context hit-grid capability
        │  typed raw calls
        ▼
native renderer
  ├── next hit grid  ◄── native producer calls during the frame
  ├── current grid   ──► checkHit for pointer targeting
  ├── hit scissor stack
  └── commit / clear / dirty state

native target ID ──► OCaml renderable-number registry ──► pointer route
```

The ownership split is deliberate:

- Native owns the current and next arrays, their dimensions, scissor stack,
  clipping, frame commit, resize clearing, and dirty bit.
- `Render_context` owns only a capability that forwards producer operations to
  its renderer. It does not contain a second grid, a shadow scissor list, or a
  Core commit operation.
- The retained tree owns layout, draw-command construction, and the lifetime
  of renderables.
- The renderer owns pointer capture, hover, selection defaults, and dispatch
  policy. It supplies the active captured ID to the hit-grid capability so a
  captured renderable is omitted from newly produced hit regions in the same
  way as the reference.
- Core owns a process-wide ID-to-renderable registry. IDs are globally unique,
  so the native grid stores compact numeric IDs rather than OCaml values or
  foreign pointers. The table lookup is O(1); Core then validates that the
  entry belongs to the queried renderer and is attached below the renderer's
  root before routing. Entries are removed as part of renderable destruction,
  so a stale native cell cannot route a later event.

The term “native pointer producer” refers to native hit-grid production during
rendering. It does not mean that native decodes mouse protocols or dispatches
pointer events. Those remain explicit Core responsibilities.

## Active contract

### Grid phases and commit

The renderer has two native grids:

- `current` is the stable layout used by pointer hit-testing;
- `next` is the layout being produced by the active render traversal.

During a frame, each eligible renderable issues one native `addToHitGrid`
operation for its screen-space rectangle. Native clipping applies the viewport
and the active hit-grid scissor stack. Later producers overwrite earlier IDs in
the same cell, preserving retained render order and the reference overlap
behavior.

The normal frame sequence is:

```text
layout and command construction
  -> clear native hit-grid scissor state
  -> execute retained commands and write native next grid
  -> native buffer presentation
  -> native current/next hit-grid commit
  -> optional dirty-grid hover recheck
```

Only a successfully presented frame commits `next` to `current`. A skipped
frame or a Core-side frame failure clears the partially produced `next` grid
and preserves `current`. A native presentation failure follows the native
renderer’s equivalent failed-frame cleanup. The Core failure path therefore
has an explicit `clear_next_hit_grid` raw operation; it must not leave a
partially written next grid to contaminate a later frame.

There is no OCaml `commit_hit_grid` operation after native rendering. Native
presentation is the commit boundary because it keeps the displayed buffer and
the pointer geometry under one renderer-owned frame transition.

### Scissors and coordinates

Renderable coordinates are converted to the same screen-space integer
coordinates used by the reference before the native call. The native owner
performs clipping against its dimensions and the nested hit-grid scissor
rectangles. A render command that pushes or pops a drawing scissor performs the
corresponding native hit-grid scissor operation; Core does not maintain a
parallel list to reproduce the clipping calculation.

The root clears the hit-grid scissor stack at the start of its execution. The
stack is frame-local native state. A malformed or unbalanced Core command list
must be rejected or cleaned up before the frame can be presented; it must not
become persistent state for the next frame.

### Lookup and hover invalidation

`Renderer.hit_test` calls native `checkHit` against `current`. ID `0` means no
target. A nonzero ID is resolved through the owner-local renderable registry,
then validated as attached, live, and eligible before pointer routing begins.
The hit-test path performs no scan of the retained tree and no OCaml grid
allocation.

After a successful native frame, Core asks native whether the committed grid is
dirty. Stationary-pointer hover is rechecked only when that bit is set. A
render request alone is not sufficient reason to synthesize hover transitions;
the geometry must have changed. Native resize invalidation participates in the
same dirty decision.

The native `clearCurrentHitGrid` and `addToCurrentHitGridClipped` operations
remain available behind a controlled raw capability for explicit immediate
geometry synchronization if a future reference feature requires it. They are
not used to build an ordinary frame and must never be used to clear `current`
while input can observe the previous committed layout.

### Capture and lifecycle

Pointer capture remains renderer-owned state. While a target is captured, the
renderer updates the context’s active captured ID before the next render
traversal; hit-grid production skips that ID, matching the reference
`addToHitGrid` wrapper. Releasing capture clears the capability and requests a
new frame so the target can re-enter the grid.

Renderable destruction removes the ID from the Core registry before the
destroyed node can be reached by a later pointer event. Destruction also
releases capture and hover ownership through the existing pointer lifecycle.
Native grid cells may still contain the old numeric ID until the next
successful frame, but registry lookup treats that ID as absent and therefore
cannot route a stale callback.

Resize is a native renderer operation. It clears both native grids, updates
their dimensions, and invalidates hover. Core updates the render-context
dimensions and performs no array recreation or full-grid fill of its own. Core
also clears the native hit-grid scissor stack during resize; the reference
renderer itself leaves that stack intact until the next root-render reset, but
both boundaries guarantee that stale frame-local scissors cannot affect the
next produced grid.

### Raw ABI surface

The raw binding exposes the native operations as primitive, handle-scoped
calls:

- `add_to_hit_grid`;
- `clear_current_hit_grid`;
- `clear_next_hit_grid` for Core-side abort cleanup;
- `hit_grid_push_scissor_rect`, `hit_grid_pop_scissor_rect`, and
  `hit_grid_clear_scissor_rects`;
- `add_to_current_hit_grid_clipped`;
- `check_hit`; and
- `get_hit_grid_dirty`.

The diagnostic `dump_hit_grid` export may remain a debug-only raw operation and
is not part of the Core pointer contract. Hot producer and lookup operations
use validated native handles and fixed-width integer arguments. They do not
allocate OCaml arrays, retain OCaml pointers, or return foreign-owned memory.

The raw module may expose a private capability record to Core rather than
making the native handle public. That keeps foreign lifetime checks and
closed-renderer behavior in `opentui-raw` while allowing the render context to
remain independent of the concrete raw renderer representation.

### Frame failure and ownership safety

The renderer must preserve the following invariant:

```text
current = last successfully presented hit layout
next    = only the in-progress layout, or an empty native staging grid
```

If retained rendering, post-processing, console rendering, or a Core-owned
validation step fails before native presentation, the renderer clears `next`,
preserves `current`, resets the native next drawing buffer and its drawing
scissor/opacity state, releases any temporary hit-grid scissor state, and
re-raises or reports the original structured error according to the existing
renderer error boundary. Cleanup must not replace an application exception
with a second cleanup exception.

Renderer resize and close invalidate the capability before native destruction.
No renderable may retain a raw handle or call a hit-grid operation after its
owning renderer has closed.

## Implementation sequence

1. Add the existing reference hit-grid exports to the checked raw ABI, with
   fixed-width declarations, static signature assertions, C stubs, OCaml
   wrappers, and raw integration tests.
2. Add the small local `clear_next_hit_grid` native seam required for Core-side
   aborts, and document why it is an ownership-preserving extension rather
   than a second commit model.
3. Replace `Render_context`’s OCaml arrays, dimensions, scissor list, and
   commit/swap helpers with the typed native capability. Forward render
   command writes and scissor operations directly to native.
4. Make `Renderer.render` use native commit and dirty state, including the
   explicit failed/skipped-frame cleanup path and conditional hover recheck.
5. Add a process-wide O(1) renderable-number table plus owner/attachment
   validation, and connect destruction, detachment, capture, resize, and close
   to its lifecycle.
6. Remove the temporary OCaml hit-grid implementation and update the pointer,
   renderable-core, source-mirror, and raw-ABI documentation to name native
   ownership as the active boundary.

The migration must not change pointer route order, bubbling, capture policy,
selection behavior, or mouse-decoder semantics. It changes only where hit
geometry is stored and how the target ID is obtained.

## Verification

The raw and Core integration tests must cover:

- overlapping renderables and retained-order winner selection;
- current-versus-next visibility before and after a successful frame;
- skipped and Core-failed frames preserving `current` and clearing `next`;
- native presentation failure cleanup;
- nested scissor clipping, pop/clear behavior, and root-frame reset;
- resize growth and shrink without stale cells or stale dimensions;
- dirty-grid reporting and conditional stationary-pointer hover rechecks;
- captured-ID omission and release-driven repopulation;
- registry lookup, detachment, destruction, and stale-ID rejection; and
- renderer close preventing later capability use.

Performance verification must show that a representative frame no longer
allocates or fills OCaml arrays proportional to terminal area. The hot path
may perform one bounded native call per hit-producing render command and one
native lookup per pointer hit-test; it must not recursively scan the retained
tree to resolve a native ID.

## Non-goals

This feature does not:

- move Kitty/X10/SGR mouse decoding into native code;
- move pointer bubbling, capture state, hover policy, focus defaults, or
  selection ownership into native code;
- make native buffers or raw handles public Core values;
- introduce a second asynchronous pointer-producer thread; or
- solve animation, audio, or plugin lifecycle concerns.

The feature moves to `docs/major-features/implemented/native-hit-grid/` only
after the native ABI, frame-failure, lifecycle, black-box pointer, and
performance criteria are all satisfied.
