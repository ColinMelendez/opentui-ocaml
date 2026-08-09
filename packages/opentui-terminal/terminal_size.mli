type t

type error = Invalid_dimensions

val message : error -> string
val pp : Format.formatter -> error -> unit

val create : columns:int -> rows:int -> (t, error) result
val columns : t -> int
val rows : t -> int
val equal : t -> t -> bool
