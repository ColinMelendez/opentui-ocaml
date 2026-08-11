# opentui-native

This package is the first imperative composition above `opentui-raw`. It owns
one renderer lifecycle and exposes an opaque `Renderer.Frame` token. A frame
opens the renderer's next native buffer, permits basic clear/cell/text updates,
and is consumed by `Renderer.present`, which maps the native rendered/skipped/
failed status to a typed OCaml result.

`Renderer.run_frame` is the small caller-owned composition seam for one
imperative frame. It opens a frame, passes it to a result-returning draw
callback, presents after `Ok ()`, and abandons the frame after a structured
draw error or callback exception so the renderer can be reused. Abandonment
clears the pinned transparent default into the native next buffer; it does not
own a loop, clock, terminal sink, event dispatch, or retained scene.

The package also exposes `Layout`, an owner-scoped composition over the raw
Yoga tree. Its opaque nodes support validated width/height updates, copied
six-field layout results, and direct-child removal; removing a child frees its
native subtree, while closing the layout invalidates every remaining node.

`Opentui_native.Color` is the caller-facing color module for frame and text
operations. It hides the raw color representation and maps invalid
construction into the native package's structured error type.

`Renderer.Frame.write_resolved_chars` writes the frame's resolved characters
into caller-owned `bytes`, preserving the raw boundary's bounded output
contract. `Ok count` is an all-or-nothing byte count; only the prefix
`output[0, count)` is defined, and insufficient capacity returns
`Error (Error.Native Output_too_small)`. It does not flush or own an output
sink. Callers can pass the returned count to
`Output_flow.write_subbytes`, which validates the prefix and avoids flushing
undefined trailing scratch bytes.

`Renderer.resize` delegates the audited raw resize operation and is only
allowed when no imperative frame is open. Resizing preserves the native
renderer and its borrowed buffer ownership; a successful operation verifies
that both native buffers expose the new dimensions. The pinned export still
swallows hidden hit-grid and other internal allocation failures, so those
failures cannot be reported through this layer.

`Text_renderable` is the first imperative leaf over those seams. It owns a
copied text value and holds an owner-scoped layout-node reference, then adds a
caller-supplied parent origin to the node's copied local origin before drawing
through a caller-owned `Renderer.Frame`. `Layout` remains responsible for node
lifetime and invalidates the reference on close. The leaf has no child tree,
measure callback, or retained-scene policy.

`Box_renderable` is the first imperative container renderable over the same
seams. It can fill its computed rectangle and draw a single-style border using
checked cell writes. The retained core applies the corresponding one-cell
Yoga inset when a border is enabled, so child composition does not paint over
the border. Its layout node remains owned by `Layout`; it does not own
children, focus, input, or a frame loop. The retained `opentui-core` layer
supplies the persistent identity and parent/child ownership around these native
renderable values.

The package does not expose native handles or raw buffer pointers. It does not
yet define retained renderables, measure callbacks, terminal modes, output
flushing, an event loop, Lwd bindings, or widgets.
