type error =
  | Unix_error of Unix.error * string * string
  | Output_error of Opentui_terminal_eio.Output_flow.error
  | Output_and_unix_error of
      Opentui_terminal_eio.Output_flow.error
      * Unix.error
      * string
      * string
  | Closed

type t

val message : error -> string
val pp : Format.formatter -> error -> unit

val create :
  sw:Eio.Switch.t ->
  fd:Eio_unix.Fd.t ->
  output:Opentui_terminal_eio.Output_flow.t ->
  (t, error) result

val enter : t -> (unit, error) result
val restore : t -> (unit, error) result
val close : t -> unit
val is_entered : t -> bool
