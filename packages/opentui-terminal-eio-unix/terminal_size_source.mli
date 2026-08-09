type error =
  | Unix_error of Unix.error * string * string
  | Invalid_dimensions

val message : error -> string
val pp : Format.formatter -> error -> unit

val get :
  Eio_unix.Fd.t ->
  (Opentui_terminal.Terminal_size.t, error) result
