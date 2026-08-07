type t

val create : width:int32 -> height:int32 -> (t, Error.t) result
val close : t -> unit
val current_buffer : t -> (Buffer.t, Error.t) result
val next_buffer : t -> (Buffer.t, Error.t) result
