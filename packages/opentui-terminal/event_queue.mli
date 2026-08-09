type event =
  | Input of Input_decoder.event
  | Resize of Terminal_size.t

type t

type error =
  | Invalid_capacity
  | Full

val message : error -> string
val pp : Format.formatter -> error -> unit

val create : ?capacity:int -> unit -> (t, error) result
val capacity : t -> int
val length : t -> int
val push : t -> event -> (unit, error) result
val read : t -> event option
val clear : t -> unit
