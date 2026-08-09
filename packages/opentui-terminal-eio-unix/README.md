# opentui-terminal-eio-unix

This package is the Unix-specific terminal-size boundary beside the optional
Eio flow package. `Terminal_size_source.get` performs one caller-invoked
window-size query through `Eio_unix`, validates the positive column and row
payload with `opentui-terminal.Terminal_size`, and maps `Unix.Unix_error` to a
structured result.

It does not install `SIGWINCH` handlers, create fibers or wakeups, push events,
own a file descriptor, or manage terminal restoration. A caller may push the
returned value into `opentui-terminal.Event_queue` according to its own
coalescing and dispatch policy.
