(** Errors returned by imperative renderer and layout operations. *)
type t =
  | Closed
  | Frame_already_open
  | Frame_not_open
  | Native of Opentui_raw.Error.t

(** [message error] is a diagnostic string for [error]. *)
val message : t -> string

(** [pp ppf error] formats [error] for diagnostics. *)
val pp : Format.formatter -> t -> unit
