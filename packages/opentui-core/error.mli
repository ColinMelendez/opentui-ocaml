type t =
  | Closed
  | Destroyed
  | Cannot_destroy_root
  | Not_container
  | Not_text
  | Invalid_dimensions
  | Invalid_layout
  | Native of Opentui_native.Error.t

val message : t -> string
val pp : Format.formatter -> t -> unit
