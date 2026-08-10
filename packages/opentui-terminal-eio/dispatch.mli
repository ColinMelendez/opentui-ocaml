val drain :
  queue:Opentui_terminal.Event_queue.t ->
  handle:(Opentui_terminal.Event_queue.event -> unit) ->
  unit

val run :
  queue:Opentui_terminal.Event_queue.t ->
  wakeup:Wakeup.t ->
  handle:(Opentui_terminal.Event_queue.event -> unit) ->
  unit
