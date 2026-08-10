# opentui-terminal-eio-unix

This package is the Unix-specific runtime boundary beside the optional Eio flow
package. `Terminal_size_source.get` performs one caller-invoked window-size
query through `Eio_unix`, validates the positive column and row payload with
`opentui-terminal.Terminal_size`, and maps `Unix.Unix_error` to a structured
result.

`Resize_source` is the explicit Unix `SIGWINCH` owner. It installs at most one
source in a process and one Eio domain, refuses to replace an existing
non-default handler, and restores the previous default/ignored behavior when
closed or when its Eio switch is released. A signal only marks a pending
notification and wakes a waiter; the caller still performs
`Terminal_size_source.get` and pushes the owned value into the bounded event
queue.

`Terminal_session` is the caller-owned terminal scope. It saves the exact
termios record, enters a raw input configuration, and then restores both the
successful `Output_flow` mode state and the saved termios record. A session
that was never entered has no terminal state to restore and performs no ANSI
write. Failed individual restoration steps remain retryable without repeating
steps that already succeeded. Its switch release hook is a best-effort
fallback; callers that need a structured restoration error should call
`restore` explicitly. It never closes the file descriptor or output sink, and
it must be registered after those resources so switch release restores the
terminal before they close.
