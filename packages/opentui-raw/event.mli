type t

val name : t -> bytes
val data : t -> bytes

module Private : sig
  val of_native : bytes -> bytes -> t
end
