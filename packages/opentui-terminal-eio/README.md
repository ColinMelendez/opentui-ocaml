# opentui-terminal-eio

This package is the optional Eio/Cstruct runtime boundary over
`opentui-terminal`. The base terminal package remains independent of Eio and
continues to own framing, semantic decoding, mode transitions, and the pure
caller-clocked `Input_coordinator`.

`Input_flow` allocates one reusable Cstruct read buffer and one reusable byte
staging buffer. `read_once` reads one flow chunk, feeds it into the coordinator,
and returns only the read result; callers drain typed events separately. The
caller supplies an Eio monotonic clock, invokes `fire_timeout` when the exposed
deadline is due, and owns the surrounding fibers, switch, terminal modes, and
output flow.

The adapter does not create a parser, event-dispatch fiber, timer fiber, output
writer, renderer, retained scene, Lwd binding, or widget.
