# Plugins and render slots

Status: in progress.

This feature defines the portable plugin and named-slot system corresponding
to the pinned reference implementation under
`vendor/opentui/packages/core/src/plugins`. It covers compiled plugin
installation, typed slot contributions, ordering, slot modes, view lifecycle,
renderer-bounded ownership, and structured failures.

The reference `runtime-plugin.ts` files are a separate boundary. They install a
Bun resolver/loader that makes host runtime modules available to code imported
from disk. They do not register slot contributions or own plugin lifecycle. The
OCaml feature likewise does not include dynamic module loading. A compiled
plugin definition is a first-class value; `Dynlink` or another loader, if ever
required, needs its own versioning, trust, and platform design.

No OCaml plugin or slot module exists yet. This record is the design plan that
must precede implementation.

## Purpose and scope

The feature lets a host declare independently typed render slots and lets one
installed plugin contribute to several of them. The host owns each slot's
props, layout, mode, fallback, and retained-tree mount. A plugin owns its
installation resources and contribution functions. A slot mount owns every
renderable view it accepts from those functions.

The first feature includes:

- an explicit renderer-bounded plugin host and first-class compiled plugin
  definitions;
- transactional multi-slot installation and idempotent uninstallation;
- one typed contribution sink for each host-declared slot;
- deterministic order and atomic installed-plugin order changes;
- append, replace, and single-winner mount modes;
- synchronous renderable view construction with activation and deactivation
  hooks;
- structured operational errors plus a composable diagnostic reporter; and
- exact ownership and renderer-bound teardown order for native hosts, future
  framework roots, plugin instances, slot mounts, views, and renderables.

It does not include a general dependency-injection container, a heterogeneous
string-keyed registry, generic framework node types, a process-global plugin
table, public registry resolution, asynchronous slot renderers, plugin-owned
nodes attached to a host tree, or Bun runtime transforms.

## Reference correspondence

| Reference source | Planned OCaml location | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/plugins/types.ts` | `packages/opentui-core/src/plugin.ml`, `slot.ml`, and private signatures | Plugin identity, installation, typed contributions, slot modes, views, and failures. |
| `vendor/opentui/packages/core/src/plugins/registry.ts` | `packages/opentui-core/src/plugin_host.ml` and private slot storage | Installed-plugin ownership, ordering, transactions, invalidation, teardown, and reporting. |
| `vendor/opentui/packages/core/src/plugins/core-slot.ts` | `packages/opentui-core/src/slot_mount.ml` | Core render-slot mount, selection modes, fallback, reconciliation, view lifecycle, and renderable ownership. |
| `vendor/opentui/packages/{react,solid}/src/plugins/slot.tsx` and renderer roots | Renderer pre-tree teardown attachment; no framework module in this feature | Evidence for shared selection semantics, framework-owned component identity, and automatic root disposal on direct renderer destruction. Their generic node types and error boundaries are not native OCaml slot architecture. |
| `vendor/opentui/packages/core/src/renderer.ts` | `packages/opentui-core/src/renderer.ml` | A distinct pre-tree teardown phase needed before retained-root destruction; the existing OCaml destroy notification remains the later post-tree event. |
| plugin examples and slot tests | `packages/opentui-core/test/test_plugins.ml` | Black-box installation, ordering, modes, view lifetime, hot replacement, failures, and teardown contracts. |
| `vendor/opentui/packages/core/src/runtime-plugin*.ts` | No direct OCaml module | Deferred Bun-specific runtime import rewriting; separate platform feature if ever required. |

## Assessment of reference usage and the current repository

The current OCaml repository has no plugin host, slot contribution, slot mount,
or plugin tests. The retained renderable spine supplies the common node and
parent/child ownership needed by a mount, but not cross-slot plugin
installation or contribution invalidation.

Repository-wide inspection of the pinned reference found no production use of
the slot plugin system inside OpenTUI itself. Outside its implementation, the
API is used by public React and Solid adapters, examples, documentation, and
tests. This distinction matters:

- the generic `SlotRegistry<TNode, TSlots, TContext>` exists so the JavaScript
  packages can share one registry across `BaseRenderable`, `ReactNode`, and
  `JSX.Element`; the OCaml port currently has only `Renderable.t`;
- practical examples confirm that one plugin contributes to multiple slots,
  plugins are dynamically registered, unregistered, and re-registered, modes
  change at runtime, and order can change while installed;
- React and Solid naturally get per-contribution mount/unmount lifecycle and
  subtree error boundaries from their frameworks;
- React and Solid attach their framework roots to the renderer before
  evaluating the application tree. Direct renderer destruction therefore
  unmounts the framework roots, runs component/effect cleanup, and unregisters
  plugin contributions without requiring a separate public root-unmount call;
- the reference renderer emits that early destruction event before destroying
  its retained root. Per-renderer registries then clear as a final safety sweep,
  while the configured late `onDestroy` callback runs after retained-root
  teardown;
- framework slots own registry subscriptions and contribution bookkeeping, but
  React or Solid owns the resulting component subtree. Reordering by plugin ID
  preserves component identity; unregister/reload unmounts the old contribution
  and a later registration may reuse the ID as a new instance;
- the core demo's managed contributions use activation and deactivation to
  bound timers, but they destroy their retained nodes themselves when
  deactivated; this demonstrates a view-lifecycle need, not a need for plugin
  ownership of attached nodes;
- external-plugin examples load a module, obtain a first-class plugin value,
  and separately register it, confirming that module loading and plugin
  installation are composable but distinct; and
- registry key reuse, mutable context identity, public batching, direct
  `resolve`, bounded registry error history, and mutation of plugin fields are
  exercised primarily by API tests or diagnostic demos rather than by an
  internal host.

The design therefore preserves demonstrated behavior without copying the
multi-framework TypeScript abstraction into OCaml. The event-system design may
implement private owner-local invalidation, but plugins do not become a new
renderer-wide event variant.

## Active design

### Independently typed slots

Each logical slot is an ordinary parameterized value rather than one case in a
heterogeneous slot map:

```ocaml
module Slot : sig
  type 'props t
  type 'props sink

  val create :
    host:Plugin.Host.t ->
    id:Id.t ->
    'props t * 'props sink
end
```

The host keeps the full `'props Slot.t`. A plugin receives only the
corresponding `'props Slot.sink`, which permits contribution but not mode,
props, fallback, mount, or tree mutation. Slot identifiers are validated
diagnostic names; they are never used to recover a payload type.

A host exposes its plugin authority as an ordinary typed record. For example:

```ocaml
type capabilities = {
  statusbar : Statusbar_props.t Slot.sink;
  sidebar : Sidebar_props.t Slot.sink;
  app : App_capability.t;
}
```

This naturally permits different prop types for different slots and lets a
plugin contribute to several slots without a GADT, functor-generated slot set,
existential payload pack, universal value, string dispatch, or `Obj`. A mount
is permanently associated with one typed slot. Dynamically switching one mount
between differently typed slot names has no implicit cast; a host uses an
explicit sum and distinct mounts if it needs that behavior.

The first implementation fixes the output to `Renderable.t` through the
`Slot_view` contract below. It does not introduce a generic node parameter only
because the reference shares infrastructure with React and Solid.

This native output boundary does not prevent a future React- or Solid-like
renderer adapter. Such an adapter owns its framework component graph,
subscriptions, and contribution values, then reconciles native renderables
through its own root. It may reuse the selection rules in this document, but it
must not wrap framework nodes in `Slot_view` or transfer their destruction
authority to a native `Slot_mount`. The renderer teardown attachment described
below is intentionally independent of `Slot_view`, so either a native plugin
host or a framework root can acquire the same automatic lifetime guarantee.

### First-class plugin definitions and narrow capabilities

A plugin is a compiled first-class definition parameterized by the capability
record its host supplies:

```ocaml
module Plugin : sig
  type 'capabilities definition
  type instance
  type errors = Error.t * Error.t list

  val define :
    id:Id.t ->
    order:int ->
    install:(Scope.t -> 'capabilities -> (unit, Error.t) result) ->
    ('capabilities definition, Error.t) result

  module Instance : sig
    val id : instance -> Id.t
    val order : instance -> int
    val set_order : instance -> int -> (unit, Error.t) result
    val uninstall : instance -> (unit, errors) result
  end

  module Host : sig
    type t

    val create : renderer:Renderer.t -> reporter:Reporter.t -> t
    val install :
      t ->
      capabilities:'capabilities ->
      'capabilities definition ->
      (instance, errors) result
    val close : t -> (unit, errors) result
  end
end
```

This is a semantic sketch rather than a final nesting decision. `Plugin.Id`
validates a non-empty identifier without making callers parse strings from
errors. Definitions are inert and may be stored, selected, or produced by a
future loader. Only `Plugin.Host.install` creates an instance.

The install callback receives the host-defined capability record, not an
unrestricted renderer and not a universal context object. Shared immutable
context can be one capability. Changing state is exposed through typed
accessors or services rather than by relying on JavaScript object identity.
Renderable construction receives only the narrow factory/context capability
that the host intentionally includes.

No plugin dependency graph is part of this feature. Applications compose
capabilities and installation order explicitly rather than acquiring a
service-container abstraction.

### Transactional installation and instance ownership

`Plugin.Host.t` is the single owner needed to coordinate one plugin instance
across several independently typed slots. It is explicitly created for a live
renderer and passed to `Slot.create`. There is no weak global map, implicit
current renderer, or `(renderer, string key)` lookup. Multiple independent
hosts are separate explicit values.

An install callback uses its unpublished `Plugin.Scope.t` to stage typed
contributions and to register cleanup actions immediately after acquiring
resources. Conceptually:

```ocaml
val Plugin.Scope.contribute :
  Plugin.Scope.t ->
  'props Slot.sink ->
  render:('props -> (Slot_view.t option, Error.t) result) ->
  (unit, Error.t) result

val Plugin.Scope.on_release :
  Plugin.Scope.t ->
  (unit -> (unit, Error.t) result) ->
  (unit, Error.t) result
```

One plugin may stage at most one contribution for a given slot, matching the
reference slot map. The scope is valid only during the install callback. It is
sealed before commit or rollback, and later `contribute` or `on_release` calls
return `Closed`; an installed plugin cannot mutate its contribution set behind
the host's transaction boundary. The implementation may stage type-erased
commit/cancel closures, but those closures close over already type-checked slot
operations and never cast payloads. Installation has this sequence:

```text
validate id and reserve installation sequence
  -> run install against an unpublished scope
  -> on failure, discard staged contributions and release acquired resources
  -> on success, publish all contributions
  -> notify every affected slot after the complete plugin is visible
  -> return the installed instance
```

Publication is atomic across the plugin's slots: every entry is installed
before any mount notification runs. A render failure in a notified mount is a
slot-local failure and does not roll back an otherwise successful plugin
installation. Setup failure returns a structured install error and no instance.
Rollback continues through every registered cleanup and returns both the
original failure and any cleanup failures.

Plugin identifiers are unique within one live host. A duplicate is rejected
without running installation. Resolved contributions use ascending plugin
order and then the host's monotonic installation sequence. This is the
reference's effective order; its later identifier comparison is unreachable
for two successfully installed entries because their registration sequences
are distinct.

`Instance.set_order` changes the order of every contribution from that plugin
as one transaction. All slot entry orders change before affected mounts are
notified, and each mount refreshes at most once. Plugin definitions and their
order fields are immutable; the host never discovers changes by rereading
caller-owned mutable records.

Uninstallation is idempotent and has an exact ownership order:

```text
mark instance uninstalling
  -> withdraw all contributions before any notification
  -> synchronously refresh affected live mounts
  -> deactivate, detach, and destroy their instance-owned views
  -> run plugin-scope cleanup in reverse acquisition order
  -> record the terminal uninstall result
```

Cleanup continues after individual failures and returns a non-empty structured
error pair-plus-tail when necessary. Repeated uninstall does not rerun
callbacks and returns the recorded result. An instance is never republished
after uninstall; the same plugin identifier may be installed later as a new
instance with a new installation sequence.

Hot reload is uninstall followed by installation of a new definition. It does
not preserve contribution-view or framework-component identity across the
reload. An asynchronous loader must invalidate its own load generation before
uninstall and ignore a module value that arrives after cleanup, matching the
reference React and Solid examples; loading remains outside the plugin kernel.

### Slot views and one renderable owner

A contribution constructs an optional detached `Slot_view.t` synchronously.
`None` is successful absence of output. A view contains one `Renderable.t` and
optional per-view activation and deactivation hooks:

```ocaml
module Slot_view : sig
  type t

  val create :
    ?on_activate:(unit -> (unit, Error.t) result) ->
    ?on_deactivate:(unit -> (unit, Error.t) result) ->
    Renderable.t ->
    t
end
```

The mount owns every accepted view and its renderable. The renderable must be
live, owned by the same renderer, unattached, and different from the mount.
Each render invocation transfers a fresh view to one mount; a plugin cannot
return the same node to several mounts or retain destruction authority over a
node attached to the host tree.

Activation occurs once immediately before attachment. Deactivation occurs at
most once before detachment and destruction. A deactivation error is reported
but cannot prevent detachment or destruction. A view that never activates is
destroyed without a deactivation call. Ordinary renderable destruction remains
the final owner of node-local resources; plugin-wide resources belong to the
plugin scope.

This lifecycle supports visibility-bound timers and subscriptions demonstrated
by the reference core example without its dual plain/managed ownership. A
plugin that wants state to survive view replacement stores that state in its
plugin scope and creates a new view over it when activated again.

### Slot mounts, selection modes, and reconciliation

`Slot_mount.t` is a retained renderable tied permanently to one `'props Slot.t`.
It owns the current props, mode, lazy fallback factory, optional failure
placeholder, private slot subscription, and all mounted views. Props and mode
changes use explicit result-returning setters; no polymorphic structural
comparison decides whether arbitrary props changed.

Conceptually, the host factories have these shapes:

```ocaml
fallback : unit -> (Slot_view.t list, Error.t) result
placeholder : Failure.t -> (Slot_view.t list, Error.t) result
```

Fallback and placeholder views follow the same mount ownership and node
validation rules as contribution views. Multiple host views are allowed even
though each individual plugin contribution returns at most one view.

The modes preserve the behavior shared by the core, React, and Solid reference
adapters:

- `append` constructs the fallback and places it before every successful
  contribution output;
- `replace` renders every ordered contribution, preserves healthy output when
  another contribution fails, and constructs the fallback only if no
  contribution or placeholder produces output; and
- `single_winner` considers only the first ordered contribution and uses its
  placeholder or the fallback when it produces no output or fails. It does not
  fall through to the next plugin.

The fallback and placeholder are host callbacks, not plugin contributions.
Fallback construction is lazy when plugin output wins. A placeholder failure
is classified as a host placeholder failure with the triggering plugin and
slot as context; it is not misreported as a second plugin failure.

A mount caches an active view by contribution identity and props revision.
Ordering changes in append or replace mode reorder existing views without
reconstructing them. A props change, contribution replacement, render retry,
or a contribution becoming active again after single-winner deactivation
constructs a fresh view. Losing active status deactivates and destroys the old
view; inactive plugin nodes are not retained off-tree.

Refresh snapshots the current ordered contributions. It invokes plugin render
callbacks and host fallback/placeholder callbacks only at their explicit
extension boundaries, validates all detached output before mutation, and then
commits the desired child order synchronously before requesting a frame. No
partially constructed plugin output enters the retained tree.

Refresh and lifecycle callbacks are not structural re-entrancy points.
Installing or uninstalling a plugin, changing instance order, changing mount
props/mode, or explicitly refreshing the same mount from one of those callbacks
returns `Busy` without changing state. This avoids attaching output from an
instance that synchronously withdrew itself and preserves the guarantee that
uninstall destroys all views before plugin cleanup. Private invalidations that
arrive while a mount is already refreshing only mark it pending and coalesce
into one later host-driven refresh; they never recursively enter evaluation.

Slot-mount destruction unsubscribes first, deactivates active views, detaches
and destroys every owned renderable, destroys any constructed fallback or
placeholder view, and is idempotent. Destroying a mount does not uninstall a
plugin that may contribute to other mounts.

### Structured failures and diagnostics

Recoverable operations return structured errors. At minimum, failure context
records the plugin instance when known, slot when known, phase, origin, and a
typed cause:

```text
phase:
  define | install | rollback | render | activate | deactivate
  | set_order | uninstall | fallback | placeholder

origin:
  plugin | host | retained_tree | reporter
```

Plugin-provided exceptions are captured only at install, render, lifecycle,
and cleanup callback boundaries, with the exception value and optional
backtrace retained as a typed cause. Built-in code does not use a catch-all to
turn internal defects into plugin failures.

Install, order, explicit refresh/setter, and uninstall callers receive their
failures directly. Failures produced by host-driven mount invalidation are
also sent to a supplied diagnostic `Reporter.t`. Reporting is observational:
reporter failure cannot change plugin, mount, or cleanup state and is sent to
the repository diagnostic boundary without recursive plugin reporting.

The plugin host does not own an error event bus or bounded history. A host that
wants UI-visible history composes the reporter with a bounded ring-buffer
reporter and exposes that application state normally. Debug printing is
another reporter combinator and cannot change lifecycle semantics.

A contribution render failure leaves the plugin installed. The mount uses the
configured placeholder/fallback policy and healthy contributions continue.
Activation failure prevents attachment and follows the same placeholder or
fallback path after destroying the rejected view. Deactivation and uninstall
failures never preserve stale attached nodes or resurrect a withdrawn
contribution.

### Renderer lifetime and Eio capabilities

A plugin host is renderer-bounded but not globally discoverable. Explicit
`Plugin.Host.close` remains useful for orderly application shutdown, but it is
not the only cleanup path. The reference React and Solid adapters guarantee
that `Renderer.destroy` alone disposes their public framework roots; an OCaml
framework adapter must be able to make the same guarantee.

Before implementing plugins, `Renderer` therefore gains an owner-local
pre-tree teardown attachment. Attaching returns an opaque, idempotent token
that can be detached or explicitly closed. Attachments run once, in
registration order, after ordinary renderer work and new attachments have been
frozen but before `Renderable.destroy_recursively root`. A teardown callback
retains the narrow authority needed to unmount or destroy its owned nodes while
the tree is still valid; it does not render another frame or resume normal
application mutation. New attachments are rejected after teardown starts. The
existing OCaml `on_destroy`/`once_destroy` notification keeps its current later
meaning and is not repurposed for callbacks that need a live retained tree.

A framework adapter attaches its root cleanup before evaluating the application
tree. Hosts created by that tree attach later. Direct renderer destruction then
has this observable order:

```text
mark teardown started; freeze ordinary work and new attachments
  -> dispose/unmount attached framework roots
  -> framework effect cleanup explicitly uninstalls its registrations
  -> close attached plugin hosts as a final safety sweep
  -> withdraw any remaining contributions and destroy their native views
  -> release plugin scopes in reverse installation order
  -> destroy the retained renderable root
  -> emit the existing late destroy notification and close native/context state
```

Native applications may explicitly close and detach a host before destroying
the renderer; a future framework adapter may do the same for its root. Both
paths invoke the same idempotent cleanup. Attachment callbacks continue after
an individual reported failure so one faulty plugin or framework root cannot
strand later owners; each callback reports its own domain failures rather than
making `Renderer` understand plugin- or framework-specific error types. The
host's stronger native invariant remains that mounted views are deactivated,
detached, and destroyed while plugin-scope resources are still valid, even
though the reference registry itself calls plugin `dispose` before notifying
slot consumers.

The core plugin modules do not start fibers, acquire an Eio environment, or
drive `Renderer_scheduler`. A host may deliberately include owner-domain
`Lib.Clock` and Eio spawn/switch operations in its typed capability record;
every resulting timer, fiber, and cancellation action is registered in the
plugin scope and ends during uninstall. UI work remains on the renderer owner
domain and requests an ordinary frame through a narrow host capability.

`Background.t` is a separate optional capability, not the plugin runtime. It is
granted only to plugin phases that accept copied, owned inputs and satisfy an
explicit `Worker_safe` contract. Completion returns to the owner domain and
checks both instance generation and closed state before publishing state or
requesting a frame. Uninstall invalidates the generation before cancelling the
scope, so a late result is harmless even when worker cancellation cannot stop
already-running CPU work. Async work still cannot be returned from a
synchronous slot renderer.

### Bun runtime plugin support

The reference runtime plugin installs exact-path import rewriting so an
externally imported module shares the host's core, React, Solid, and optional
runtime-module instances. The external examples then independently call the
normal registry API with the value exported by that module. The loader has no
slot resolution or lifecycle role.

The OCaml port starts with linked modules producing `Plugin.definition`
values. It makes no promise that arbitrary `.cmxs`, shared objects, or source
files can be safely loaded. A future dynamic-loader feature must define ABI
versioning, dependency resolution, trust, capability negotiation, unloading
limits, and code/resource lifetime without weakening typed slot sinks or
introducing an untyped escape hatch.

### Deliberate differences from the reference

The design preserves unique plugin identity, setup-before-visibility,
multi-slot plugins, hot uninstall/reinstall, effective ordering, atomic change
notification, synchronous contribution rendering, append/replace/single-winner
selection, fallback behavior, per-contribution failure isolation, and
renderer-bounded cleanup. The following differences are intentional and
consumer-visible:

- The reference stores heterogeneous slots in one string-keyed generic
  registry shared by core, React, and Solid. OCaml exposes one independently
  typed `'props Slot.t` and contribution sink per slot and initially fixes
  output to `Renderable.t`.
- A reference plugin is a mutable record containing a mapped `slots` object.
  An OCaml plugin is an immutable first-class installation function using a
  host-specific typed capability record. Plugin authors call typed contribution
  functions rather than construct a dynamic property bag.
- The reference gives setup the complete renderer and renderers a shared
  context object. OCaml gives installation only the narrow capabilities chosen
  by the host; shared context or renderable construction is explicit within
  those capabilities.
- Reference framework slots can accept a runtime slot name, with tests using
  casts to switch between names whose props differ. An OCaml mount is indexed
  permanently by one props type; heterogeneous switching requires an explicit
  sum and separate typed mounts.
- The reference registry is recovered by `(renderer, key)` from a weak global
  map and requires repeated calls to reuse the same context object. OCaml hosts
  and slots are explicit values with no global lookup or context-identity rule.
- The reference uses one early generic renderer event and listener registration
  order to dispose framework roots before clearing registries. OCaml adds a
  dedicated pre-tree teardown attachment with an opaque token and preserves the
  existing later destroy notification, making the live-tree requirement
  explicit without turning plugin cleanup into an event payload.
- The reference permits mutable plugin order and rereads it during resolution.
  OCaml definitions are immutable and an installed instance changes order only
  through a transactional, result-returning operation.
- The reference core distinguishes host-owned plain nodes from plugin-owned
  managed nodes. OCaml mounts own every attached node; per-view activation and
  deactivation preserve the practical lifecycle use case without split
  destruction authority or off-tree node retention.
- The reference registry invokes plugin `dispose` before notifying slot
  consumers that contributions disappeared. OCaml first withdraws
  contributions and destroys their native views, then releases plugin-scope
  resources, so view cleanup can safely use installation-lifetime resources.
- Reference operations return callbacks/Booleans or throw, and the registry
  owns error listeners plus bounded history. OCaml controls return structured
  results and a composable reporter handles failures that have no direct
  caller; history and debug output are optional reporter policy.
- The reference exposes generic `resolve`, public batching, and mutable
  registry configuration. OCaml keeps resolution and invalidation private to
  typed slots, performs batching inside installation/order/uninstallation
  transactions, and configures ownership policy at explicit construction.
- Reference callbacks can incidentally mutate the registry or slot again while
  framework/core rendering is in progress. OCaml returns `Busy` for structural
  re-entrancy and coalesces private invalidation for a later refresh, so plugin
  callbacks cannot make the current contribution snapshot stale.
- JavaScript framework error boundaries can catch failures produced later by a
  React or Solid subtree. The first OCaml slot boundary covers synchronous view
  construction and lifecycle callbacks; later retained-render failures follow
  the renderer's ordinary structured render-failure contract unless a separate
  retained-subtree boundary is designed.
- Bun runtime import rewriting has no OCaml counterpart in this feature.

The fact that one plugin can contribute to multiple slots, order is ascending
then installation sequence, ordering changes preserve active view identity,
single-winner does not try a runner-up after failure, and module loading is
separate from installation intentionally matches the reference.

## Planned implementation sequence

1. Add the renderer pre-tree teardown attachment and opaque idempotent token.
   Preserve the existing late destroy notification, define registration-order
   execution, and cover direct renderer destruction plus explicit detach/close.
2. Implement validated plugin and slot identifiers, independently typed slot
   values/sinks, immutable plugin definitions, structured failure values, and
   the reporter capability.
3. Implement `Plugin.Host`, unpublished installation scopes, staged typed
   contributions, rollback cleanup, atomic multi-slot publication, instance
   tokens, order changes, terminal uninstallation, and renderer attachment.
4. Add black-box host tests for duplicate IDs, multiple differently typed slot
   contributions, setup failure and rollback, ordering, order changes, hot
   uninstall/reinstall, idempotency, reporter isolation, direct renderer
   teardown, and the framework-root-before-host safety-sweep ordering.
5. Implement `Slot_view` and `Slot_mount` with one renderable owner, activation
   and deactivation, snapshot refresh, lazy fallback/placeholder construction,
   view reuse on reorder, and fresh construction on props or activity changes.
6. Add black-box mount tests for all modes, healthy output beside failures,
   single-winner failure without runner-up, multiple mounts, props changes,
   node validation, structural re-entrancy rejection, lifecycle failures, and
   cleanup ordering.
7. Add a small linked-plugin example that demonstrates multiple slots, order
   changes, enable/disable, persistent plugin state, visibility-bounded
   resources, owner-domain timer/fiber cleanup, and an optional copied
   `Worker_safe` background phase whose stale completion is rejected.
8. Reassess dynamic loading and a generic framework-slot adapter only from
   separate requirements; do not add `Dynlink` or a generic node registry as a
   side effect of the native slot feature.

## Acceptance criteria

- each slot's props remain statically related to its contribution sink without
  `Obj`, universal values, string payload dispatch, or polymorphic structural
  comparison;
- one first-class plugin definition can transactionally contribute to several
  differently typed slots and is invisible everywhere until setup succeeds;
- installation scopes seal before publication and reject later contribution or
  cleanup registration without an untyped mutation escape hatch;
- failed setup rolls back every registered resource, reports cleanup failures
  structurally, and never exposes a partial plugin;
- plugin IDs are unique per host, effective order is ascending order then
  installation sequence, and an instance order change updates all slots before
  any mount refreshes;
- uninstall withdraws every contribution, destroys affected views before
  plugin-scope cleanup, continues through cleanup failures, and is idempotent;
- append, replace, and single-winner match the reference selection, fallback,
  healthy-sibling, and no-runner-up behavior;
- contribution output is at most one view, host fallback/placeholder output may
  contain several views, and all follow the same validation and ownership
  rules;
- order-only changes preserve active view identity, while props changes,
  replacement, or reactivation construct fresh views;
- every attached plugin renderable is owned by exactly one mount, is validated
  before attachment, and is deactivated, detached, and destroyed exactly once;
- activation/deactivation hooks can bound visibility-dependent resources
  without granting a plugin destruction authority over attached nodes;
- operational controls return structured results, host-driven failures go to a
  non-authoritative reporter, and optional history/logging remains composable;
- plugin, fallback, placeholder, reporter, and retained-tree failures are
  attributed to the correct origin and cannot corrupt installation or tree
  ownership;
- structural operations invoked re-entrantly from render or lifecycle
  callbacks return `Busy`, and private invalidation never recursively refreshes
  a mount or changes its current contribution snapshot;
- renderer teardown freezes the host, withdraws all contributions, destroys
  mount views while plugin resources remain valid, and releases scopes before
  the retained tree becomes unusable;
- direct `Renderer.destroy` invokes attached framework-root cleanup before
  attached host safety sweeps and retained-root destruction, while explicit
  root/host close detaches the same idempotent cleanup path;
- pre-tree attachments run once in registration order, one attachment failure
  does not strand later owners, and the existing late destroy notification
  still observes an already-destroyed retained tree;
- order-only changes preserve framework component identity when an adapter keys
  contributions by plugin ID, while unregister/reload removes the old component
  and permits a new instance to reuse that ID;
- the plugin kernel has no Eio, scheduler, background-executor, or
  dynamic-loader dependency, while hosts can explicitly grant renderer-bounded
  owner-domain capabilities;
- optional background work accepts only copied, owned `Worker_safe` values and
  a completion checks instance generation and closed state on the owner domain,
  so uninstall makes late worker results harmless; and
- Bun-specific runtime rewriting and any future OCaml dynamic loader remain
  separate from typed plugin installation and slot rendering.
