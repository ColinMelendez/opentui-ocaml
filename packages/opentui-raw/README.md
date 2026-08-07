# opentui-raw

This package is the narrow waist between OCaml and the native OpenTUI ABI. It
owns the typed status boundary, the `Renderer.t`, `Buffer.t`, and
`Event_sink.t` lifetimes, and the native build/link seam. Packed native handle
bits remain private to the C facade; callers cannot mix renderer, buffer, and
event-sink domains.

The first production slice uses a memory-output renderer with native threaded
output disabled. Renderer-owned buffer views become closed when their renderer
closes. Event callbacks are copied into a bounded native queue and exposed by
polling; the raw package does not re-enter OCaml from a native callback. Queue
overflow is reported as a structured error. Because the pinned callback ABI
has no context pointer, only one event sink may be active at a time.

It deliberately does not contain Yoga/layout objects, a renderer tree,
terminal mode or parser state, a reactive graph, or a widget API. Those layers
must be able to depend on a small and auditable boundary.
