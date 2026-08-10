type t

val create : unit -> t

val revision : t -> int64

val notify : t -> unit

val wait : t -> since:int64 -> int64

val push :
  t ->
  queue:Opentui_terminal.Event_queue.t ->
  Opentui_terminal.Event_queue.event ->
  (unit, Opentui_terminal.Event_queue.error) result
