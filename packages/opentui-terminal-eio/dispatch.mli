(** Caller-run dispatch over a bounded {!Opentui_terminal.Event_queue}.
    [run] waits on {!Wakeup} and does not create fibers or own resources. *)

(** [drain ~queue ~handle] invokes [handle] for each currently queued event in
    FIFO order. *)
val drain :
  queue:Opentui_terminal.Event_queue.t ->
  handle:(Opentui_terminal.Event_queue.event -> unit) ->
  unit

(** [run ~queue ~wakeup ~handle] drains events and waits for the next revision
    until cancelled by the surrounding Eio context. Handler exceptions
    propagate. *)
val run :
  queue:Opentui_terminal.Event_queue.t ->
  wakeup:Wakeup.t ->
  handle:(Opentui_terminal.Event_queue.event -> unit) ->
  unit
