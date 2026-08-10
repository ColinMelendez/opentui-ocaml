type error =
  | Already_installed
  | Existing_handler
  | Closed

type t

val message : error -> string
val pp : Format.formatter -> error -> unit

val create : sw:Eio.Switch.t -> unit -> (t, error) result
val wait : t -> (unit, error) result
val close : t -> unit
