# opentui-terminal-eio

This package is the optional Eio/Cstruct runtime boundary over
`opentui-terminal`. The base terminal package remains independent of Eio and
continues to own framing, semantic decoding, mode transitions, and the pure
caller-clocked `Input_coordinator`.

`Input_flow` allocates one reusable Cstruct read buffer and keeps one
character-typed Bigarray view over that same storage. `read_once` offers each
decoded event synchronously to a caller-owned sink without an intermediate
`bytes` staging copy. If the sink reports `Full`, the flow returns
`Backpressured count`, keeps any unread suffix in the same reusable buffer, and
does not read the source again until the sink accepts the earlier input. The
count is the number of bytes read during that call; it is zero when no new
source read occurred. A sink that calls `Event_queue.push
(Event_queue.Input event)` obtains the bounded lossless/coalescing handoff; a
sink that dispatches directly can follow the same push-and-drain path without
a queue. The caller supplies an Eio monotonic clock, invokes `fire_timeout`
when the exposed deadline is due, and owns the surrounding fibers, switch,
wakeups, terminal modes, and output flow.

`Wakeup` is a single-domain revision condition. Its revision makes a
notification that happens before a waiter sleeps observable, and its `push`
helper notifies only after the bounded queue accepts or coalesces an event.
`Dispatch.drain` handles already-queued events, while `Dispatch.run` drains
the queue and then waits with a second queue check to close the producer/waiter
race. It runs in the caller's fiber and does not create a fiber, own the
switch, or catch handler exceptions.

The adapter does not create a parser, input/timer/output fiber, output writer,
renderer, retained scene, Lwd binding, or widget. The Unix-only package owns
the process signal and terminal-attribute policies that are intentionally not
part of this package.

`Output_flow` binds the writer-free `Terminal_modes` transitions to a
caller-owned Eio sink. It writes a transition's bytes before committing the
remembered mode state, exposes synchronous writes for arbitrary frame bytes,
and maps Eio I/O failures to a structured result. `write_subbytes` validates
and writes a caller-selected byte range, so a native resolved-output count can
be handed to the sink without flushing undefined trailing scratch bytes. Any
I/O, cancellation, or invalid-progress failure poisons the wrapper against
retries because the sink may contain only a prefix. It does not close or
serialize the sink, create fibers, or own terminal restoration.
`Terminal_session` in the Unix package composes that writer with a saved
termios record when a real terminal scope is needed.
