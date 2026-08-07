# opentui-native

This package is the first imperative composition above `opentui-raw`. It owns
one renderer lifecycle and exposes an opaque `Renderer.Frame` token. A frame
opens the renderer's next native buffer, permits basic clear/cell/text updates,
and is consumed by `Renderer.present`, which maps the native rendered/skipped/
failed status to a typed OCaml result.

The package does not expose native handles or raw buffer pointers. It does not
yet define retained renderables, Yoga composition, terminal modes, output
flushing, an event loop, Lwd bindings, or widgets.
