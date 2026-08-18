(** Errors returned by renderer, context, and retained-rendering operations. *)

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
  | Output of string
  | Native of Native.Error.t
  | Native_image of Opentui_raw.Image.error

(** [message error] is a diagnostic string for [error]. *)
val message : t -> string

(** [pp formatter error] formats [error] for diagnostics. *)
val pp : Format.formatter -> t -> unit
