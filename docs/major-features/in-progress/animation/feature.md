# Animation and timelines

Status: implemented for deterministic timelines and renderer attachment;
framework bindings and custom easing remain deferred.

This feature defines the OCaml animation timeline and its frame-driving
boundary. It corresponds to the pinned reference implementation in
`vendor/opentui/packages/core/src/animation/Timeline.ts`.

The OCaml implementation lives under `packages/opentui-core/src/animation`.
This record remains the design reference for the implementation. It
deliberately separates timeline evaluation from the renderer scheduler:
interpolation is synchronous state mutation, while frame timing and continuous
rendering belong to an explicit owner.

## Purpose

The feature provides a reusable timeline for animating numeric properties,
running callbacks at timeline positions, composing timelines, and keeping a
renderer live while work is active. It is useful both for ordinary OCaml
application state and for renderable properties whose setters invalidate a
frame.

It does not define post-processing effects, a declarative reconciler, audio
timing, or a general-purpose wall-clock scheduler. Those are separate
boundaries.

## Reference correspondence

| Reference source | Planned OCaml location | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/animation/Timeline.ts` | `packages/opentui-core/src/animation/timeline.ml` | Easing, timeline items, interpolation, looping, callbacks, nested timelines, and explicit engine ownership. |
| `vendor/opentui/packages/core/src/animation/Timeline.test.ts` | `packages/opentui-core/test/test_animation.ml`, `test_animation_edges.ml`, and `test_animation_engine.ml` | Black-box timeline and engine behavior tests using deterministic frame deltas. |
| `vendor/opentui/packages/core/src/renderer.ts` frame callbacks and live control | `Renderer.attach_pre_render`, `Renderer.attach_before_destroy`, and live leases | Run the explicit animation engine before retained traversal and keep the renderer live while an eligible timeline is active. |
| `vendor/opentui/packages/core/src/Renderable.ts` `onUpdate` and live propagation | `Renderable.Private` behavior and live-count boundary | Preserve the existing renderable per-frame hook and connect animated setter invalidation to the same render ownership rules. |
| React and Solid `useTimeline` hooks under `vendor/opentui/packages` | future framework integration | Scope one stable timeline and registration token to component mount and cleanup. |
| `vendor/opentui/packages/examples/src/timeline-example.ts` and `mouse-interaction-demo.ts` | core examples and integration tests | Cover model projection, timeline observations, manual driving, synchronization, and fire-and-forget engine ownership. |

The animation directory is retained under `opentui-core/src/animation` so the
reference correspondence remains discoverable. It is a qualified Dune
subdirectory, not a new top-level package.

### Practical reference usage

The React and Solid bindings construct timelines as component-owned resources,
register them on mount, and unregister them on cleanup. Their render entry
points attach the process-global engine to the current renderer. The React hook
also constructs a new timeline on every rerender while its empty-dependency
effect retains the first one; because its example triggers rerenders from
`onUpdate`, that unstable returned instance is a reference integration bug, not
a behavior to preserve.

The standalone timeline example uses synchronized children, callback items,
item loops, alternation, timeline time and duration observations, and direct
manual `update`. Its `createTimeline` calls also register the roots globally,
demonstrating that the reference does not prevent accidental manual-plus-engine
advancement. The mouse demo instead creates an autoplay timeline for each drop
and discards the handle; the global engine retains those completed timelines.
The active design below preserves the useful workflows while making both
advancement and temporary registration ownership explicit.

Across the framework and standalone examples, animations primarily mutate
plain numeric model objects and use `onUpdate` to project values into reactive
state or several renderables. Direct renderable-property animation is useful
but is not the only or dominant consumer shape, so the typed API includes a
lightweight mutable-value binding as well as renderable-owned descriptors.

## Assessment of the current implementation

The repository now has typed easing and property modules, deterministic
timelines, explicit engine registrations, and renderer attachment. The
relevant ownership seams are:

- `Renderable.Private.make_behavior` has an `on_update` callback and an
  `updates_each_frame` policy;
- retained renderables and the root already maintain live counts, with the
  root boundary forwarding live transitions to the render context;
- `Render_context` has coalesced render invalidation and aggregate live-request
  state;
- `Renderer_scheduler` owns paced frame attempts on the renderer's Eio owner
  domain, measures deltas with `Eio_clock`, and supplies `0.0` for the first
  attempt (and the first attempt after idle); and
- `Renderer.render` accepts a caller-supplied delta in seconds, runs registered
  pre-render drivers before retained traversal, propagates the same delta
  through retained traversal and post-process callbacks, and emits `on_frame`
  only after successful native presentation.

The existing `on_frame` notification is not used as the animation clock: it
runs after presentation, while the reference updates timelines before the
retained tree renders. `Animation.Engine.attach` uses the renderer-owned
pre-render registry and an opaque live lease, so automatic driving has the
same ordering without adding an Eio fiber to the animation module. Manual
`Animation.Engine.update` remains available for deterministic owners.

The event system is not the animation engine. Animation state changes may use
small internal callbacks to update live ownership, but animation does not
turn into a renderer-wide event variant or acquire Eio streams. The event
system's owner and cleanup rules still apply to any renderer subscription.

## Active design

### Timeline ownership and timing

`Timeline.t` is synchronous state. It advances only when its owner calls
`update` with a frame delta. It does not read a clock, install a timer, start
an Eio fiber, or implicitly register itself in a process-global engine.

The public animation time unit is milliseconds represented as `float`,
matching the reference's `number` values. `Renderer_scheduler` and
`Renderer.render` use seconds for measured and renderable/post-process deltas;
the renderer attachment converts that value exactly once at the
animation boundary before calling `Engine.update`. A timeline stores
`current_time` and `duration` in milliseconds. The evaluator must preserve
these reference cases:

- a negative delta regresses the timeline's current time and is forwarded to
  already-started synchronized children; items and callbacks still apply only
  when the resulting absolute time is at or after their start offset;
- a large delta evaluates crossed start and completion boundaries plus the
  reference evaluator's resulting loop-cycle transition in one update;
- an item captures its initial property values when it starts, not when it is
  added;
- a zero-duration item applies its final value once and does not receive
  repeated updates;
- a timeline with a finite duration completes at its own duration even when
  an item has a longer duration; and
- a looping timeline resets its items and re-evaluates any overshoot from the
  beginning of the next loop.

Construction validates numeric values instead of inheriting JavaScript's
`NaN`, infinity, and truthiness behavior. Timeline and item durations, loop
delays, start offsets, binding endpoints, and supplied deltas must be finite.
Item duration and loop delay are nonnegative. A looping timeline has a positive
duration so overshoot modulo is defined; a non-looping zero-duration timeline
is allowed. A finite item loop count is a positive integer, while the explicit
infinite form represents unbounded looping. Start offsets and manually supplied
deltas may be negative so the pinned negative-time case remains expressible.
Property reads and custom easing results must also be finite; a non-finite
runtime result faults the timeline at its typed boundary.

Omitted values receive documented defaults, but zero is never silently treated
as omission. Matching the reference, timeline defaults are duration `1000`,
autoplay enabled, and parent looping disabled; item defaults are duration
`1000`, linear easing, one execution, zero loop delay, and no alternation.
Calling `play` on a completed timeline restarts it. The reference's string
`startTime` form has no actual label semantics and is treated as zero; the OCaml
API exposes only an explicit numeric offset and does not invent named timeline
positions.

### Typed numeric properties

The reference accepts an arbitrary JavaScript target and discovers numeric
properties by dynamic key lookup. OCaml must not reproduce that with strings,
open records, `Obj`, or a heterogeneous property table.

The canonical replacement is a typed property descriptor plus a target-bound
property binding. Conceptually:

```ocaml
module Property : sig
  type 'target t
  type binding

  val create :
    read:('target -> (float, Error.t) result) ->
    write:('target -> float -> (unit, Error.t) result) ->
    'target t

  val bind :
    'target t ->
    'target ->
    to_:float ->
    binding

  val bind_ref :
    float ref ->
    to_:float ->
    binding
end
```

An animation item accepts a list of bindings. This preserves the reference's
ability to animate several numeric properties on one or more targets as one
item, including one `on_update` callback and one completion/loop lifecycle.
The binding representation may be existential internally; callers never
construct or inspect an untyped target.

`bind_ref` is the convenience path for the dominant reference usage: animate
a small mutable numeric model and let `on_update` project it into one or more
renderables or reactive values. It uses ordinary infallible reference reads and
writes without requiring every caller to manufacture a target type and
descriptor. Rich targets and renderable-owned setters still use `create` and
`bind`, so the convenience does not weaken their validation or invalidation
boundaries.

Renderable-specific descriptors belong with the renderable module that owns
the setter. They call the typed setter, preserve its validation and
invalidation behavior, and turn a closed/destroyed owner into the timeline's
structured update error. Animation must not mutate a renderable's private
field around its setter or bypass `request_render`.

Binding writes within one item are applied sequentially and are not
transactional. If a later write fails, earlier successful writes and their
invalidation remain visible; the evaluator does not attempt to roll back
arbitrary setter side effects. The item does not invoke its `on_update` or any
later lifecycle callback for that update, and the timeline enters the faulted
state described below.

When an item starts, it reads and stores every binding's initial value before
performing any write for that item. Bindings within an item then write in list
order, and animation items write in timeline insertion order. Overlapping
bindings are therefore deterministic: the last applicable write in that order
wins for the frame. The typed binding API may reject duplicate bindings within
one item if it can identify them without structural comparison; otherwise the
documented sequential rule is authoritative.

An update callback receives a typed animation-info value containing at least:

```ocaml
type update = {
  progress : float;
  current_time_ms : float;
  delta_time_ms : float;
}
```

It does not expose a dynamically typed target array. Callers that need the
target can close over their typed value when creating the property binding.
Matching the reference, `progress` is the eased progress before alternate
direction is applied; it is not the final reversed interpolation fraction.

Timeline observation is explicit even though evaluator state is abstract.
The public surface includes typed accessors for at least `current_time_ms`,
`duration_ms`, and lifecycle `state`; a `progress` convenience may derive from
the first two without introducing independently mutable state. This supports
the reference examples that render timeline progress without exposing item
arrays or writable clock fields.

### Easing

The built-in easing vocabulary mirrors the reference functions:

`linear`, `in_quad`, `out_quad`, `in_out_quad`, `in_expo`, `out_expo`,
`in_out_sine`, `out_bounce`, `out_elastic`, `in_bounce`, `in_circ`,
`out_circ`, `in_out_circ`, `in_back`, `out_back`, and `in_out_back`.

The first public representation uses a closed OCaml variant rather than string
lookup. Easing receives a clamped progress value; overshooting functions such
as `in_back` and `out_back` may produce values outside the `[0,1]` result range,
as in the reference. The follow-up custom-function case uses the same clamped
input; its result must be finite but is not clamped after evaluation.

No non-test reference consumer supplies a custom easing function. Custom
easing is therefore a follow-up extension, not a condition for completing the
first animation milestone. The initial public implementation may expose only
the closed built-in variant; when the custom case is added, the fault behavior
specified here becomes normative without changing built-in semantics.

### Items and callbacks

The timeline contains three item families:

- numeric animation items, with a start offset, bindings, duration, easing,
  per-item loop count, loop delay, alternate direction, and lifecycle
  callbacks;
- callback items, which execute once when their start offset is reached; and
- synchronized child timelines, which are evaluated against the parent clock.

The public operations correspond to the reference operations:

```text
add       add an animation item at an explicit offset
once      add an animation item at the current time and remove it on completion
call      schedule a callback item
sync      attach one child timeline at a parent offset
play      start or resume the timeline
pause     pause the timeline and its synchronized children, returning a result
restart   reset item state and start from time zero
update    advance one deterministic frame delta or return a structured fault
```

`once` is an item-lifetime operation, not a timeline loop mode. A once item is
removed only after its completion path runs. A timeline restart resets the
remaining item state but does not resurrect an already removed once item,
matching the reference's behavior.

Captured initial property values survive item loops, parent loops, and explicit
timeline restart. Restart resets lifecycle and evaluation state, not the
original binding values. This matches the reference, whose item reset does not
clear `initialValues`. A caller that needs a new starting value creates a new
item or timeline rather than relying on restart to recapture it.

Every timeline has at most one advancement owner: it is either an independent
root registered with one engine, a synchronized child of one parent, or
unaffiliated. The parent controls a synchronized child's play/pause state,
starts it when its offset is reached, passes start overshoot into its first
update, and resets it when a looping parent restarts. A child is never also
advanced independently by an engine.

Public `Timeline.update` is the manual driver for an unaffiliated timeline
only. Calling it on an engine-affiliated root or synchronized child returns an
ownership error; engine and parent evaluation use internal advancement
capabilities. This makes double advancement impossible even though the
reference's standalone timeline example calls `update` on a timeline that
`createTimeline` has also registered globally. An OCaml consumer choosing
manual driving constructs an unaffiliated timeline and does not register it.

`sync` transfers advancement ownership to the parent and returns an idempotent
cancellation token. Both timelines must be unaffiliated or belong to the same
engine; a different-engine relationship is a structured error. Registering a
parent affiliates its synchronized subtree with that engine after validating
that no descendant conflicts. Unregistering the parent unaffiliates the whole
subtree without rewriting its play state. Cancelling a sync while its parent is
engine-affiliated makes the child an independent root of that same engine;
cancelling while unaffiliated leaves the child unaffiliated. This prevents the
reference's one-way `synced` flag from leaving a detached child permanently
inert. A child promoted to an engine root this way remains owned by the
parent's registration token; releasing that token later releases both roots.
Retaining the child beyond that scope requires an explicit ownership transfer,
not an untracked engine affiliation.

While attached, a child's public `play`, `pause`, and `restart` controls return
an ownership error; the parent is its lifecycle owner. Parent evaluation and
reset use an internal child capability rather than bypassing that rule. A
consumer that needs independent control first cancels the synchronization
token.

Callback order is part of the contract. Within one update, synchronized
children are evaluated according to their parent offsets, then the parent
items are evaluated in insertion order, and completion/state-change callbacks
run at the same logical boundaries as the reference. Calling `pause` repeatedly
does not duplicate state or live-lease transitions, but it does invoke the
reference `on_pause` callback on every call. `pause` returns a structured
result; an `on_pause` exception faults the timeline after its playing state and
live ownership have been updated. Resource idempotency must not silently change
that observable callback behavior.

Large deltas preserve the reference's callback multiplicity as well as its
final property value. In particular, crossing several item-loop boundaries in
one update does not invent one callback per mathematically crossed boundary
when the reference evaluator reports only the resulting cycle transition.
Tests pin the exact `on_loop`, `on_complete`, callback-item, and synchronized
child behavior for such deltas.

### Mutation and re-entrancy during evaluation

Timeline evaluation is not re-entrant. Calling `update` or `restart` from an
item or lifecycle callback returns a structured `Busy` error rather than
recursively mutating evaluator state. Calling `play` or `pause` changes the
timeline's state immediately, but the current update snapshot finishes; the
new state controls later updates. This preserves the reference behavior in
which pausing during an item callback does not truncate the current item loop.

Each update snapshots its items and synchronized children before evaluation.
`add`, `once`, `call`, and `sync` invoked from a callback are staged, committed
after the outer update finishes, and first become eligible on the next update.
The staged mutations are retained even if a later callback faults the current
update; an explicit restart can subsequently evaluate them. Engine registration
and cancellation use the engine's frame snapshot in the same way: changes made
during one timeline callback affect the next engine update, not which remaining
roots receive the current frame delta.

### Faults and deterministic partial updates

A timeline has explicit `idle`, `playing`, `paused`, `completed`, and `faulted`
states. `update` returns a result. Its structured error contains at least the
timeline time, item identity when known, binding index when known, failure
phase, and underlying structured error or captured exception diagnostic. The
failure phases distinguish property read/write, custom easing, lifecycle
callbacks, update callbacks, and synchronized child evaluation.

Conceptually:

```ocaml
type failure_phase =
  | Read_property
  | Write_property
  | Custom_easing
  | On_start
  | On_update
  | On_loop
  | On_complete
  | On_pause
  | Child_timeline

type failure_cause

type fault = {
  item_id : int option;
  binding_index : int option;
  timeline_time_ms : float;
  phase : failure_phase;
  cause : failure_cause;
}

val update : t -> delta_time_ms:float -> (unit, fault) result
```

The final error module may carry a captured exception and backtrace as a typed
cause alongside ordinary repository errors; callers never parse its message.

Property descriptor read/write failures already arrive as results. Exceptions
are captured only at explicit user-extension boundaries such as descriptor
functions, lifecycle callbacks, update callbacks, and a custom easing function;
the captured error retains the exception value and optional backtrace rather
than reducing it to a string. This includes lifecycle callbacks invoked by a
control operation rather than by `update`. Built-in evaluator code does not use
a catch-all handler to disguise internal defects.

On the first evaluator or lifecycle-control failure, the timeline enters
`faulted` before the operation returns. It does not invoke any later lifecycle
callback from that operation, and it receives no further automatic updates.
`play` rejects a faulted timeline. An explicit `restart` clears the fault,
resets the ordinary item lifecycle state, preserves captured initial property
values, and starts again from time zero. Successful writes earlier in a failed
update remain applied, so retry is explicit and never presented as
transactional rollback.

A synchronized child fault first faults the child and then faults its parent
with phase `Child_timeline` and the child fault as structured context. The
parent skips its remaining items for that update. This propagation continues
through nested synchronized parents, while other top-level timelines owned by
the engine still receive their update opportunity.

### Explicit engine and live rendering

`Animation.Engine.t` is an explicit owner of registered timelines. It is
usable with deterministic manual updates without `Renderer_scheduler`. It also
provides renderer attachment through the owner-local pre-render and teardown
seams:

```text
register    attach a timeline and return an idempotent registration token
run_once    play under temporary registration until terminal state or cancellation
clear       detach all timelines and release the engine's live token
destroy     cancel driver attachment, clear timelines, and release ownership
update      advance every unsynchronized playing timeline and report failures
```

Releasing a registration token unregisters every affiliation it owns,
including its synchronized subtree and any descendant promoted to an
independent root by sync cancellation, without rewriting play state. The token
owns the engine's state listeners and affiliation claims, so component and
renderer integrations retain and release one resource instead of
reconstructing ownership with a later `unregister timeline` call. Token release
is idempotent and follows the same next-frame snapshot rule as other
registration changes.

`run_once` is a registration-lifetime convenience and is distinct from the
timeline's `once` item operation. It accepts an unaffiliated root, registers
and starts it, and automatically releases the registration when the root
completes or faults. It also returns a cancellation token so an owning UI
lifecycle can stop and release it early. Explicit cancellation pauses the root
and then releases all temporary affiliations even if `on_pause` faults; the
cancellation operation returns that structured fault. Persistent `register`
does not auto-release on completion because its owner may later restart the
timeline. This provides the reference mouse-demo's fire-and-forget behavior
without retaining every completed timeline in an engine indefinitely.

`clear` and `destroy` mark every outstanding registration and `run_once`
token released after detaching its affiliations. Releasing or cancelling one
of those tokens later is harmless; cancelling a `run_once` token after its
automatic terminal release does not invoke `on_pause` retroactively.

The engine observes timeline state changes. While at least one registered,
unsynchronized timeline is playing and incomplete, it holds one continuous
frame lease token. When the last such timeline pauses, completes, faults, or is
unregistered, the token is released. Acquisition returns an opaque token with
an idempotent release operation; the engine owns either zero or one token and
does not reconstruct lease ownership from an unpaired request/drop counter.
Other renderer owners may hold their own tokens or an explicit-start claim, so
one engine cannot stop rendering that another owner requested.

A timeline or synchronized subtree is affiliated with at most one engine.
Registration validates the complete subtree before changing affiliation, so a
failed registration cannot leave only part of it attached. Registering a
timeline that is currently a synchronized child is an error; the parent is the
registration root. Registration-token release and sync-token cancellation
update affiliation and live-token ownership as one state transition.

An engine updates a snapshot of its eligible timelines in deterministic
registration order. A timeline failure faults that timeline and releases any
resulting active ownership transition, but it does not prevent the remaining
timelines in the snapshot from advancing. `Engine.update` returns all failures
from that frame, tagged with their timeline identities. The frame driver
reports them through its diagnostic boundary and continues to retained-tree
rendering, so successful and documented partial mutations remain observable.
Animation failure does not silently turn into a renderer presentation failure.

Conceptually:

```ocaml
type engine_failure = {
  timeline_id : int;
  fault : Timeline.fault;
}

val update : t -> delta_time_ms:float -> (unit, engine_failure list) result
```

An error list is non-empty, and every eligible timeline in the frame snapshot
has been given its update opportunity before the result is returned.

`Animation.Engine.attach` adds the narrow renderer-owned integration with these
properties:

- after `Renderer.render` clears the request for the current attempt and before
  `Renderable.Private.render_root` begins, it invokes the registered pre-render
  driver(s) on the renderer owner domain;
- the driver receives the render attempt's seconds delta, converts it once to
  animation milliseconds, and runs the engine before retained traversal;
- animation engine diagnostics are reported through an animation-owned
  diagnostic boundary and do not become `Renderer.render` errors; and
- active animation owns one opaque, idempotent live lease whose acquisition
  and release update the renderer's existing aggregate live state. The lease
  is an ownership capability for the animation integration, not a general
  scheduler registry.

The placement after request consumption is deliberate: render requests made by
animation setters remain pending for a following attempt, just like requests
made by retained render hooks. Engine clear/destroy and renderer destruction
must cancel the pre-render attachment before releasing its live lease. The
animation engine remains independent of Eio and may also be driven
manually in tests or by an application scheduler. Renderer destruction invokes
the attached teardown callback before the retained root is destroyed, allowing
the engine to detach its driver and release its lease while the renderer is
still valid.

Framework bindings create exactly one timeline and registration token per
component mount, even when animation callbacks cause reactive rerenders. They
release that token during component cleanup. This intentionally avoids the
reference React hook's unstable-instance behavior, where a new `Timeline` is
constructed on every render while only the first instance is registered by
the mount effect.

For each scheduled attempt, `Renderer_scheduler` measures the monotonic delta
between attempts and passes it in seconds to `Renderer.render`. The first
attempt, and the first attempt after an idle period, receives exactly `0.0`;
later attempts receive finite, nonnegative measurements between attempts,
including when a previous presentation was skipped or failed. The animation
engine updates before retained-tree collection with that same attempt delta
(converted to milliseconds for animation), while post-process callbacks
receive the original seconds value.
A post-frame `on_frame` observer is not an equivalent substitute.

Animation setter invalidations made during the pre-render update must remain
pending for a following attempt, as do requests made by later render hooks.
If retained rendering or native presentation skips or fails, animation is not
rewound or replayed; the next attempt receives a newly measured delta.

Timeline and engine faults are animation diagnostics: they fault or isolate
the affected timeline, allow the rest of the frame and other eligible
timelines to proceed, and do not enter `Renderer.render`'s recoverable error
path. Consequently they must not emit a renderer render-error event or cause
the scheduler's paced renderer-failure retry. Unexpected programmer failures
at an owner-domain extension boundary follow the surrounding owner/Eio
failure policy rather than being relabeled as animation render failures.

Animation state, renderable setters, animation callbacks, buffers, and native
state remain on the renderer/application owner domain. No animation timeline,
callback, renderable mutation, or native handle is submitted to `Background`.

### Deliberate differences from the reference

For finite valid inputs, the OCaml evaluator preserves the reference's easing
curves, start overshoot, item and parent loops, loop delays, alternation,
initial-value capture, restart persistence, once removal, callback multiplicity,
synchronized-child timing, update-before-render ordering, and shared frame
delta. The following differences are intentional and consumer-visible:

- The reference discovers numeric target properties through JavaScript object
  keys. OCaml consumers construct typed property bindings; there are no dynamic
  target bags, string property dispatch, or target arrays in callback payloads.
- Reference timeline fields and item arrays are publicly mutable. OCaml keeps
  evaluator state abstract, exposes observations through typed accessors, and
  requires validated operations for mutation. JavaScript-style direct writes
  to `currentTime`, `items`, `isPlaying`, or `synced` have no counterpart.
- `createTimeline` automatically registers with one process-global reference
  engine. OCaml timelines and engines are explicit owners, and registration can
  fail structurally on an ownership conflict. Registration returns an
  idempotent token; `run_once` is the explicit auto-release convenience for a
  fire-and-forget root.
- The reference permits direct `Timeline.update` even after global
  registration, so an application can accidentally advance the same root
  manually and through the engine. OCaml permits direct update only while the
  timeline is unaffiliated; ported manual drivers construct an unaffiliated
  timeline instead of using an engine-registration convenience.
- Reference setter and callback exceptions escape `Timeline.update`; the
  renderer logs a frame-callback exception and the timeline can remain live.
  OCaml converts failures at explicit extension boundaries into a faulted
  timeline, releases its live ownership, continues other engine roots, and
  requires explicit restart before that timeline advances again.
- The reference iterates mutable item arrays directly, so structural mutation
  or recursive restart/update during callbacks has incidental, largely untested
  same-iteration effects. OCaml snapshots evaluation, stages structural
  mutation for the next update, and rejects re-entrant update/restart with
  `Busy`. Ported callbacks must not depend on same-update insertion.
- Reference mutation methods are chainable and generally report extension
  failures by throwing. OCaml operations that can validate ownership or invoke
  user code return structured results, and `sync` additionally returns its
  cancellation token. Ported consumers handle those results explicitly.
- The reference's `synced` flag is one-way and has no detach operation. OCaml
  `sync` transfers explicit advancement ownership and returns a cancellation
  token that can safely restore the child as an independent engine root. While
  attached, callers control the parent rather than directly playing, pausing,
  or restarting the child.
- JavaScript accepts or silently reinterprets some zero, negative, `NaN`, and
  infinite construction values through dynamic number and truthiness rules.
  OCaml rejects non-finite and otherwise malformed values with structured
  errors, preserves zero when valid, and uses defaults only for omission.
- The reference accepts a string `startTime` but treats every string as zero.
  OCaml omits this misleading form and exposes numeric offsets only.
- The reference easing API is a closed set of string names. OCaml initially
  uses a corresponding closed set of typed constructors. A planned follow-up
  permits an explicit custom easing function whose exceptions and non-finite
  results fault the timeline structurally; that extension is not required for
  the first milestone because no practical reference consumer uses it.
- Reference framework bindings use the process-global engine, and the React
  hook constructs a fresh timeline on rerender while its mount effect retains
  the first instance. OCaml framework bindings scope one stable timeline and
  registration token to each component lifetime.

The scheduler's measured render-attempt delta contract and
`Renderer.render`'s propagation of that delta through retained traversal and
post-process callbacks now establish the timing substrate for this feature.
The animation engine consumes that delta at the pre-render boundary. Pending
rerender requests made during animation, no rewind after presentation failure,
repeated `on_pause` callback behavior, and preservation of captured values
across restart are part of the current contract.

## Implementation sequence and remaining work

The first runtime slice is complete:

1. Built-in easing, typed property bindings, deterministic item evaluation,
   structured faults, synchronized-child ownership, and timeline state
   transitions live under `packages/opentui-core/src/animation`.
2. `Animation.Engine` provides explicit registration tokens, `run_once`,
   per-timeline fault isolation, state-driven live leases, manual updates, and
   renderer pre-render/teardown attachment.
3. Renderer attachment runs before retained traversal, converts seconds to
   animation milliseconds exactly once, and releases its live lease during
   engine or renderer teardown.

The remaining work is intentionally narrower:

4. Add renderable-specific property descriptors where a renderable exposes a
   stable public numeric setter; callers can already animate ordinary mutable
   numeric state through `Property.bind_ref` and project it in `on_update`.
5. Keep the staged callback-mutation boundary covered as the evaluator grows;
   committed `add`, `once`, `call`, and `sync` mutations remain ineligible until
   the next logical update, including when the current update faults.
6. Add custom easing only if a real consumer needs it, preserving the typed
   built-in easing surface as the default.
7. Add framework bindings after the framework/plugin boundary exists. They must
   retain one timeline and registration token for the component lifetime and
   release it before renderer teardown, matching the React/Solid ownership
   evidence without reproducing the reference React hook's unstable instance.

## Acceptance criteria

- timeline evaluation is deterministic for a supplied delta and does not read
  a hidden clock;
- construction rejects non-finite and malformed numeric values, preserves valid
  zero values, and still supports the pinned finite negative-delta behavior;
- all built-in reference easing curves produce the corresponding values,
  including overshoot curves;
- initial values are captured at item start and final values persist after
  completion; item loops and restart do not recapture them;
- omitted defaults and `play`-after-completion behavior match the reference,
  while valid explicit zero values are not treated as omission;
- item loops, loop delays, alternation, once removal, and parent loops follow
  the reference timing boundaries;
- callback items, lifecycle callbacks, and synchronized child timelines have
  deterministic ordering and overshoot behavior;
- target properties are typed, preserve setter ownership, and never require
  `Obj`, string property names, or dynamic records;
- mutable numeric models have a direct typed binding convenience, and timeline
  time, duration, and lifecycle state are observable without exposing mutable
  evaluator internals;
- all binding initial values are captured before item writes, and overlapping
  bindings/items resolve in documented list and insertion order;
- update failures at renderable ownership boundaries are structured and do not
  leave stale animation leases behind;
- a failed update preserves earlier successful setter effects, faults only its
  timeline, suppresses later callbacks for that update, and does not prevent
  other registered timelines from advancing;
- an engine advances only its registered, unsynchronized timelines and
  releases its opaque live token exactly once per active ownership transition,
  including fault transitions;
- persistent registration is owned by an idempotent token, while `run_once`
  releases temporary registration after completion, fault, or explicit
  cancellation without changing persistent-registration restart semantics;
- engine clear/destroy releases all token-owned affiliations, and later token
  release or cancellation is harmless and cannot repeat lifecycle callbacks;
- engine and renderer teardown cancel the pre-render attachment before
  releasing the live token, and repeated cancellation is harmless;
- re-entrant update and restart fail with `Busy`; callback-time `add`, `once`,
  `call`, and `sync` validate immediately, stage successfully, and commit only
  after the outer update (including a fault), while engine registration changes
  do not alter the current engine snapshot;
- synchronization has one advancement owner, rejects cross-engine trees, and
  its cancellation token cannot leave the child permanently inert; direct
  lifecycle controls on an attached child return an ownership error;
- direct `Timeline.update` succeeds only for an unaffiliated timeline and
  returns an ownership error for an engine root or synchronized child;
- the existing `Renderer_scheduler` owns paced frame attempts on one Eio owner
  domain, supplies exactly `0.0` for the first attempt after idle, and measures
  later deltas between attempts;
- the existing `Renderer.render` propagates its caller-supplied seconds delta
  through retained traversal and post-process callbacks;
- automatic driving updates timelines after the current request is cleared and
  before retained rendering; retained and post-process hooks receive the
  scheduler's seconds delta, while animation receives that value converted to
  milliseconds exactly once;
- animation invalidations made during an attempt remain pending for a following
  attempt, and skipped or failed presentation never rewinds or replays the
  animation update;
- timeline and engine faults are reported as animation diagnostics, do not
  emit renderer render-error events, and do not trigger the scheduler's paced
  renderer-failure retry;
- animation state, callbacks, renderable setters, buffers, and native handles
  remain on their owner domain and no such work is submitted to `Background`;
- renderer destruction, registration-token release, and repeated pause/completion
  have idempotent state and resource transitions; repeated `pause` still
  preserves the reference callback multiplicity, and an `on_pause` exception
  is returned structurally without leaving a live lease behind; and
- every future framework binding retains one stable timeline and registration
  token for the complete component mount, including across callback-triggered
  rerenders.
