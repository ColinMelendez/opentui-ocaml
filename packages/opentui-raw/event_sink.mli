type t

val create : unit -> (t, Error.t) result
val close : t -> unit
val poll : t -> (Event.t option, Error.t) result
