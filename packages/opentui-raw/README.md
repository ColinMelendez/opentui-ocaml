# opentui-raw

OpenTUI's terminal renderer is implemented in Zig and exported through a C
ABI. `opentui-raw` is the OCaml package that calls that ABI. It is the
dependency beneath [`opentui-core`](../opentui-core/), not a second UI library.

The package owns the typed status boundary, the `Renderer.t`, `Buffer.t`,
`Event_sink.t`, and independent `Yoga.Node.t` lifetimes, together with the
native build/link rules. Packed handle bits and Yoga pointers remain private to
the C facade, so callers cannot mix resource domains or retain an unchecked
pointer.
The complete audited symbol list, layout assertions, and build/link contract
are in [`native/ABI.md`](native/ABI.md).

The package-owned ABI and native-link tests are in [`test/`](test/). The raw
package owns those tests because they validate foreign handles, C stubs, and
the Zig link seam directly; retained-tree and terminal-runtime tests are in
[`../opentui-core/test/`](../opentui-core/test/).

## Renderer and event ownership

The renderer API uses memory output with native threaded output disabled.
Renderer-owned buffer views close when their renderer closes. `Renderer.render`
returns the renderer's `Rendered`, `Skipped`, or `Failed` status without
exposing native output state. Event callbacks are copied into a bounded native
queue and exposed by polling; the package does not re-enter OCaml from a native
callback. Queue overflow is a structured error. The C callback ABI has no
context pointer, so one event sink can be active at a time.

`Renderer.resize` validates positive dimensions at the ABI boundary and resizes
the renderer's current and next buffers in place. Existing borrowed buffer
handles remain valid and observe the new dimensions when the facade's
postcondition check succeeds. The reference `resizeRenderer` export has a
`void` return and swallows allocation failures; the facade reports an
observable current/next buffer mismatch as `Native_failure`, but hidden
hit-grid or other internal allocation failures remain unobservable.

Yoga is the layout engine used by the renderer. The Yoga binding owns
generation-checked independent node tokens and copies the exact six-field
layout result. Its style subset includes the reference value, enum, float, and
border operations without publishing Yoga pointers. Inserting and removing a
child does not free it; single-node free requires a detached leaf, while
recursive free releases a detached subtree and invalidates every node token in
that subtree.

The capability binding copies terminal strings and decodes the renderer's enum
codes into a typed snapshot. The `Span_feed` binding preserves the
`NativeSpanFeed` ownership protocol: it copies drained payloads into OCaml
bytes, exposes an explicit idempotent release token, and keeps reservation
commit/cancel explicit through a caller-owned staging buffer. These values are
ABI resources, not retained UI nodes or terminal-runtime objects.

`opentui-raw` does not contain a renderer tree, terminal mode or parser state,
native-owned zero-copy span views, a reactive graph, or a widget API. Those
concerns belong to higher-level packages and can depend on this small,
auditable ABI boundary.
