type t =
  | Closed
  | Native of Opentui_raw.Error.t

let message error =
  match error with
  | Closed -> "the native resource is closed"
  | Native error -> "native OpenTUI operation: " ^ Opentui_raw.Error.message error

let pp formatter error = Format.pp_print_string formatter (message error)
