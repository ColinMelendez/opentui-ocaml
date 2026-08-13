(** Errors returned by renderer, context, and retained-rendering operations. *)

type t =
  | Closed
  | Destroyed
  | Owner_mismatch
  | Not_child
  | Invalid_anchor
  | Native of Native.Error.t

(** [message error] is a diagnostic string for [error]. *)
val message : t -> string

(** [pp formatter error] formats [error] for diagnostics. *)
val pp : Format.formatter -> t -> unit
