# opentui-core

`opentui-core` is the user-facing Eio-native OCaml library for terminal UI
programs. It uses `opentui-raw` for checked calls to the Zig renderer. Its
source directories correspond to the matching directories in
`vendor/opentui/packages/core/src`; package-local tests, reference tools, and
performance tools remain under this package.

## Renderer and buffers

`Renderer.t` owns one native renderer, one `Render_context.t`, and the native
renderer’s current and next buffers. `Render_context.t` is the capability view
shared by the renderer and retained renderables. It observes live dimensions
and frame identity, records coalesced render requests, and provides typed
resize and frame notifications from the renderer’s one owner-local event
source.

`Buffer.t` is a checked drawing view over one renderer-owned native buffer. A
buffer does not own its native storage and cannot be destroyed independently.
Resize mutates the native buffers in place, so existing `Buffer.t` values
observe the new dimensions. Destroying the renderer closes its context and
invalidates all borrowed buffers.

`Yoga.Node.t` represents an independently owned layout node. Attaching and
detaching a node does not free it; its owner frees it explicitly. The Yoga
module exposes the style operations required by the retained-rendering
modules and returns structured native errors.

The retained renderable tree, concrete Box and Text modules, and their
text-buffer dependencies follow the source correspondence recorded in the
[renderable-core feature record](../../docs/major-features/in-progress/renderable-core/feature.md).
They use the renderer, context, buffer, and Yoga ownership boundaries defined
here rather than introducing a second tree owner.

## Terminal modules

`Lib.Stdin_parser` is the terminal input boundary. It frames input bytes and
emits typed key, mouse, paste, and response events. `Lib.Key_decoder` and
`Lib.Mouse_decoder` are parsing helpers used by `Lib.Stdin_parser`; they are
not a required second input stage. `Lib.Input_coordinator` and
`Lib.Event_queue` provide deadline, backpressure, and event-handoff policies.
`Platform.Eio_runtime` contains Eio flow, wakeup, output, and dispatch
modules. `Platform.Eio_unix_runtime` contains Unix terminal-size, signal, and
termios-session modules. These modules provide explicit building blocks for
an application runtime; they do not hide resource ownership in a global loop.

The source location and deferred reference areas are listed in the [source
correspondence map](../../docs/upstream-map.md).
