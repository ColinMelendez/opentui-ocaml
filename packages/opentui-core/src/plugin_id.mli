(** Validated names used by the native plugin and slot kernel. *)

type t = private string

type error =
  | Empty
  | Nul_character of int

val create : string -> (t, error) result
val to_string : t -> string
val equal : t -> t -> bool
val compare : t -> t -> int

val error_message : error -> string
val pp_error : Format.formatter -> error -> unit
