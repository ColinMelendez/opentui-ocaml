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
the source event. Resize values are pushed directly to `Event_queue`. The
caller supplies an Eio monotonic clock, invokes `fire_timeout` when the exposed
deadline is due, and owns the surrounding fibers, switch, terminal modes, and
output flow.

The adapter does not create a parser, event-dispatch fiber, timer fiber, output
writer, renderer, retained scene, Lwd binding, or widget.

`Output_flow` binds the writer-free `Terminal_modes` transitions to a
caller-owned Eio sink. It writes a transition's bytes before committing the
remembered mode state, exposes synchronous writes for arbitrary frame bytes,
and maps Eio I/O failures to a structured result. Any I/O, cancellation, or
invalid-progress failure poisons the wrapper against retries because the sink
may contain only a prefix. It does not close or serialize the sink, create
fibers, or own terminal restoration.
