type t

val rgba :
  red:int -> green:int -> blue:int -> alpha:int -> (t, Error.t) result

val rgb : red:int -> green:int -> blue:int -> (t, Error.t) result

val black : t
val white : t
val channels : t -> int * int * int * int

module Private : sig
  val to_native : t -> int * int * int * int
end
