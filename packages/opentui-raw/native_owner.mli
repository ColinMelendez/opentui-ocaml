type t

val is_open : t -> bool

module Private : sig
  val create : unit -> t
  val close : t -> unit
end
