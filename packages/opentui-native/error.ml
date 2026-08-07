type t =
  | Closed
  | Frame_already_open
  | Frame_not_open
  | Native of Opentui_raw.Error.t

let message = function
  | Closed -> "the native renderer is closed"
  | Frame_already_open -> "a native frame is already open"
  | Frame_not_open -> "the native frame is not open"
  | Native error -> "native renderer: " ^ Opentui_raw.Error.message error

let pp formatter error = Format.pp_print_string formatter (message error)
