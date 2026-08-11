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
  | Native of Opentui_native.Error.t

let message error =
  match error with
  | Closed -> "core scene is closed"
  | Destroyed -> "core node is destroyed"
  | Cannot_destroy_root -> "core scene root cannot be destroyed"
  | Cannot_move_root -> "core scene root cannot be moved"
  | Invalid_child_index -> "core child index is invalid"
  | Not_container -> "core node cannot own children"
  | Not_box -> "core node is not a box"
  | Not_text -> "core node is not a text node"
  | Invalid_dimensions -> "core node dimensions are invalid"
  | Invalid_layout -> "native layout returned invalid coordinates"
  | Native error -> Opentui_native.Error.message error

let pp formatter error = Format.pp_print_string formatter (message error)
