(** Caller-invoked Unix terminal-size probing. *)

type error =
  | Unix_error of Unix.error * string * string
  | Invalid_dimensions
(** System-call or validation errors. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val get :
  Eio_unix.Fd.t ->
  (Opentui_terminal.Terminal_size.t, error) result
(** [get fd] queries and validates the terminal size for [fd]. *)
