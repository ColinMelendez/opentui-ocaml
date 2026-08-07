type t =
  | Closed
  | Frame_already_open
  | Frame_not_open
  | Native of Opentui_raw.Error.t

val message : t -> string
val pp : Format.formatter -> t -> unit
