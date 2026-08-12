(** Errors returned by retained scene operations. *)
type t =
  | Closed
  | Destroyed
  | Cannot_destroy_root
  | Cannot_move_root
  | Invalid_child_index
  | Not_container
  | Not_box
  | Not_text
  | Invalid_dimensions
  | Invalid_layout
  | Native of Native.Error.t

(** [message error] is a diagnostic string for [error]. *)
val message : t -> string

(** [pp ppf error] formats [error] for diagnostics. *)
val pp : Format.formatter -> t -> unit
