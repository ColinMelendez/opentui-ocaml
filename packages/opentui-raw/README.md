# opentui-raw

This package is the narrow waist between OCaml and the native OpenTUI ABI. It
owns the typed status boundary, the `Renderer.t`, `Buffer.t`, `Event_sink.t`,
`Yoga_tree.t`, and `Yoga_node.t` lifetimes, and the native build/link seam.
Packed native handle bits and Yoga pointers remain private to the C facade;
callers cannot mix resource domains.

The first production slice uses a memory-output renderer with native threaded
output disabled. Renderer-owned buffer views become closed when their renderer
closes. Event callbacks are copied into a bounded native queue and exposed by
polling; the raw package does not re-enter OCaml from a native callback. Queue
overflow is reported as a structured error. Because the pinned callback ABI
has no context pointer, only one event sink may be active at a time.

The raw Yoga binding owns a generation-checked tree/node registry and copies
the exact six-field layout result. The capability binding copies terminal
strings and decodes the pinned enum codes into a typed snapshot. Both are ABI
resources, not a retained scene or terminal runtime.

It deliberately does not contain a renderer tree, terminal mode or parser
state, native-owned output span views, a reactive graph, or a widget API. Those
layers must be able to depend on a small and auditable boundary.
