type t =
  | Closed
  | Destroyed
  | Missing_async_lifetime
  | Invalid_argument
  | Wrong_domain
  | Owner_mismatch
  | Not_child
  | Invalid_anchor
  | Unsupported
  | Io of string
  | Native of Native.Error.t
  | Native_image of Opentui_raw.Image.error

let message error =
  match error with
  | Closed -> "the renderer owner is closed"
  | Destroyed -> "the renderable is destroyed"
  | Missing_async_lifetime ->
      "an asynchronous source requires an owner Eio switch"
  | Invalid_argument -> "an argument is invalid"
  | Wrong_domain -> "the operation must run in its owner Eio domain"
  | Owner_mismatch -> "the renderable belongs to another renderer"
  | Not_child -> "the value is not a direct child"
  | Invalid_anchor -> "the insertion anchor is invalid"
  | Unsupported -> "the retained-rendering operation is not available"
  | Io detail -> "I/O error: " ^ detail
  | Native error -> Native.Error.message error
  | Native_image error ->
      "native image operation: " ^ Opentui_raw.Image.message error

let pp formatter error = Format.pp_print_string formatter (message error)
