# opentui-core

This package is the first retained imperative layer above `opentui-native`. A
`Scene` owns one native renderer and one Yoga tree. Its root and descendants
have persistent opaque node values with stable integer identities; ordinary
text and dimension updates mutate those nodes instead of rebuilding the tree.

The initial vertical slice intentionally stays small:

- fixed-size Box and Text renderables;
- owner-scoped creation and recursive teardown;
- layout calculation before each required frame;
- dirty tracking with one controlled `flush` boundary;
- caller-owned resolved-output bytes, with the sink left to the runtime layer;
- synthetic pointer hit-testing and target-to-parent propagation; and
- structured closed, destroyed, layout, and native errors.

The typed `Scene.Box` and `Scene.Text` modules are the first direct
OpenTUI-shaped renderable surface. They share the common `Scene.Node` identity
and ownership model, so property updates do not recreate the retained nodes.
The executable example in [`../../examples/README.md`](../../examples/README.md)
shows the intended caller path and output contract.

`Scene.flush` skips a clean scene unless the caller passes `force:true`. A
rendered result reports the defined output prefix; the caller can pass that
prefix to `opentui-terminal-eio.Output_flow`. A failed frame remains dirty so a
caller can diagnose or retry it through the same boundary.

The package does not own terminal flows, clocks, event fibers, native pointer
views, reactive values, or widgets. Terminal decoders will adapt their typed
events to the core pointer boundary later. Rich Yoga styles, custom native
renderables, focus, keyboard routing, keyed child reconciliation, Lwd, and
widgets are subsequent increments.
