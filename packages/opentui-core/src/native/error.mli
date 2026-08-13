(** Errors returned by core calls that directly use a native resource. *)
type t =
  | Closed
  | Native of Opentui_raw.Error.t

(** [message error] is a diagnostic string for [error]. *)
val message : t -> string

(** [pp formatter error] formats [error] for diagnostics. *)
val pp : Format.formatter -> t -> unit
