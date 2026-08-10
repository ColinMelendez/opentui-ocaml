# opentui-terminal-eio

This package is the optional Eio/Cstruct runtime boundary over
`opentui-terminal`. The base terminal package remains independent of Eio and
continues to own framing, semantic decoding, mode transitions, and the pure
caller-clocked `Input_coordinator`.

`Input_flow` allocates one reusable Cstruct read buffer and one reusable byte
staging buffer. `read_once` reads one flow chunk, feeds it into the coordinator,
and returns only the read result; callers can drain typed events separately or
transfer one pending event at a time into the pure bounded `Event_queue`.
`transfer_one` leaves the source event pending only when that destination
reports `Full`; a successful `Move`/`Drag` coalescing push at capacity consumes
the source event. `transfer_one_and_notify` additionally advances a caller-owned
`Wakeup` after a successful transfer. Resize values can use `Wakeup.push`, which
keeps queue insertion and notification together. The caller supplies an Eio
monotonic clock, invokes `fire_timeout` when the exposed deadline is due, and
owns the surrounding fibers, switch, terminal modes, and output flow.

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
and maps Eio I/O failures to a structured result. Any I/O, cancellation, or
invalid-progress failure poisons the wrapper against retries because the sink
may contain only a prefix. It does not close or serialize the sink, create
fibers, or own terminal restoration. `Terminal_session` in the Unix package
composes that writer with a saved termios record when a real terminal scope is
needed.
