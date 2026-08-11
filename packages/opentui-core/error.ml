type t =
  | Closed
  | Destroyed
  | Cannot_destroy_root
  | Not_container
  | Not_text
  | Invalid_dimensions
  | Invalid_layout
  | Native of Opentui_native.Error.t

let message error =
  match error with
  | Closed -> "core scene is closed"
  | Destroyed -> "core node is destroyed"
  | Cannot_destroy_root -> "core scene root cannot be destroyed"
  | Not_container -> "core node cannot own children"
  | Not_text -> "core node is not a text node"
  | Invalid_dimensions -> "core node dimensions are invalid"
  | Invalid_layout -> "native layout returned invalid coordinates"
  | Native error -> Opentui_native.Error.message error

let pp formatter error = Format.pp_print_string formatter (message error)
