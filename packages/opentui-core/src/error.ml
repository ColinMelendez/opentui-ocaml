type t =
  | Closed
  | Destroyed
  | Owner_mismatch
  | Not_child
  | Invalid_anchor
  | Native of Native.Error.t

let message error =
  match error with
  | Closed -> "the renderer owner is closed"
  | Destroyed -> "the renderable is destroyed"
  | Owner_mismatch -> "the renderable belongs to another renderer"
  | Not_child -> "the value is not a direct child"
  | Invalid_anchor -> "the insertion anchor is invalid"
  | Native error -> Native.Error.message error

let pp formatter error = Format.pp_print_string formatter (message error)
