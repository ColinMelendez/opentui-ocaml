Design review focused on probing the reference implementation's usage of the feature leading to a refinement of the design.

## What the reference actually uses

An exhaustive search found no production use of the plugin system inside OpenTUI itself. Outside its implementation, it appears in:

- React and Solid public adapters.
- One core demo.
- React/Solid demos, including external loading.
- Documentation and tests.

The generic registry exists primarily so React and Solid can share one TypeScript implementation with different node types. React instantiates it with `ReactNode` in [slot.tsx](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/react/src/plugins/slot.tsx:56), while Solid instantiates it with `JSX.Element` in [slot.tsx](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/solid/src/plugins/slot.tsx:56). That is a real reason in TypeScript, but not currently a reason in this OCaml repository.

The framework adapters use the registry quite narrowly:

1. Subscribe to registry changes.
2. Resolve ordered entries for one slot.
3. Invoke each contribution with context and props.
4. Apply append/replace/single-winner behavior.
5. Install framework-specific error boundaries.

For example, React’s complete interaction with the registry is visible around [slot.tsx](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/react/src/plugins/slot.tsx:191).

## Requirements demonstrated in practice

Several reference behaviors are genuinely useful and should remain.

### Plugins contribute to multiple slots

The external example contributes both statusbar and sidebar output from one plugin value in [index.tsx](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/react/examples/.plugin/index.tsx:16).

That supports retaining a plugin-level installation transaction rather than registering completely unrelated contributions manually.

### Plugin values are loaded, installed, removed, and reloaded

The external demo dynamically imports a module, obtains a plugin value, registers it, and retains the unregister token in [external-plugin-slots-demo.tsx](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/react/examples/external-plugin-slots-demo.tsx:79) and [external-plugin-slots-demo.tsx](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/react/examples/external-plugin-slots-demo.tsx:155).

For OCaml, a plugin should therefore remain a first-class compiled value:

```ocaml
type 'capabilities Plugin.definition
```

It should not merely be application initialization code with no identity or uninstall handle.

### Modes are central

Append, replace, and single-winner are implemented independently by every adapter. They are not registry behavior; they are mount behavior. This strongly supports moving them into a typed `Slot_mount`.

Notably, `single_winner` evaluates only the first ordered contribution and falls back if it fails. It does not try the second plugin.

### Runtime ordering is used

The core demo updates plugin order interactively through `updateOrder` in [core-plugin-slots-demo.ts](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/examples/src/core-plugin-slots-demo.ts:543). An installed plugin instance should therefore expose a structured `set_order` operation that atomically updates all its contributions.

### Activation lifecycle has a real use

The core demo uses activation/deactivation to run timers only while contribution views are visible in [core-plugin-slots-demo.ts](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/examples/src/core-plugin-slots-demo.ts:256).

However, those “plugin-owned” contributions explicitly destroy their own nodes during deactivation. That demonstrates the need for a visibility lifecycle, not the need for dual ownership.

## What appears to be framework or test scaffolding

These parts do not have compelling practical use outside tests or API demonstrations:

- Generic `node`-typed registry abstraction.
- `(renderer, string key)` registry identity and context-object identity checks.
- Mutable plugin objects whose `order` can change behind the registry’s back.
- Public `resolve` APIs separate from the slot adapters.
- Registry-owned bounded error history.
- Generic batching as a public operation.
- Plugin-owned attached renderables.
- Dynamic switching between differently typed slot names.

The React/Solid dynamic-name tests require type casts when the slots have different prop types. That is exactly the kind of unsafe convenience the OCaml design should avoid. An OCaml mount should be permanently indexed by one `'props Slot.t`.

The error history is used by error-focused demos and tests, but not by normal plugin workflows. It can be a composable diagnostic reporter rather than registry state.

## Runtime loading is genuinely separate

The runtime “plugin” only rewrites imports so dynamically loaded modules can access host-owned runtime module instances. Its stated purpose is documented at [runtime-plugin.ts](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/core/src/runtime-plugin.ts:1), and its implementation constructs a Bun loader without depending on slot registries at [runtime-plugin.ts](/Users/colin/projects/ocaml-stuff/ocaml-open-tui/vendor/opentui/packages/core/src/runtime-plugin.ts:417).

The external demo composes the two mechanisms manually:

```
Bun loader → import module → obtain Plugin value → registry.register
```

So the existing plan is correct to keep OCaml loading completely separate from installation and slots.

## Revised recommendation

I would retain the earlier typed-slot model:

```ocaml
'props Slot.t
'props Slot.sink
'capabilities Plugin.definition
Plugin.Host.t
Plugin.Instance.t
```

A plugin definition would install against host-specific capabilities:

```ocaml
type 'caps definition = {
  id : Plugin_id.t;
  order : int;
  install :
    Plugin.Scope.t ->
    'caps ->
    (unit, Error.t) result;
}
```

A capability record naturally supports multiple differently typed slots:

```ocaml
type capabilities = {
  statusbar : Statusbar.props Slot.sink;
  sidebar : Sidebar.props Slot.sink;
  context : App_context.t;
}
```

Installation stages all contributions and publishes them together only after setup succeeds.

### Add a host-owned view lifecycle

I would refine my earlier “all nodes are host-owned” recommendation with a small view value:

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

The slot mount still owns and destroys the renderable. The hooks merely describe the lifetime of that particular produced view:

```
construct detached view
→ activate
→ attach
→ deactivate
→ detach
→ destroy
```

This supports the timer/resource use case from the core demo without letting the plugin retain ownership of a node inside somebody else’s tree. Plugin-wide resources remain in `Plugin.Scope`.

### Preserve context, but narrow it

The external plugins genuinely use host context such as application name and version. I would keep that capability, but not a universal `context` field plus the complete renderer. The host should define exactly what a plugin receives.

If a value must change over time, the capability can expose a typed accessor rather than relying on mutable object identity.

### Use a reporter, not an error registry

Normal operations return structured errors:

- `Plugin.Host.install`
- `Plugin.Instance.uninstall`
- `Plugin.Instance.set_order`
- explicit mount refresh or prop updates

Render and lifecycle failures that occur during host-driven reconciliation go to a structured reporter and select placeholder/fallback behavior. A bounded-history reporter can be supplied for applications that want the error-demo UI.

## Bottom line

The investigation changes one part of my earlier recommendation: I would explicitly retain per-produced-view activation/deactivation hooks.

It otherwise strengthens the simpler architecture:

- Keep plugin identity, multi-slot installation, hot unload/reload, order changes, modes, and renderer-bounded lifetime.
- Use independently typed slots rather than a heterogeneous generic registry.
- Specialize the initial system to `Renderable.t`.
- Keep every attached node host-owned.
- Make error history and logging composable diagnostics.
- Keep module loading entirely separate.
