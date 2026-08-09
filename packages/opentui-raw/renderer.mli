type t

type render_status = Rendered | Skipped | Failed

val create : width:int32 -> height:int32 -> (t, Error.t) result
val resize : t -> width:int32 -> height:int32 -> (unit, Error.t) result
val close : t -> unit
val current_buffer : t -> (Buffer.t, Error.t) result
val next_buffer : t -> (Buffer.t, Error.t) result
val render : t -> force:bool -> (render_status, Error.t) result

module Private : sig
  val with_open :
    t ->
    (Native_token.Renderer.t -> ('a, Error.t) result) ->
    ('a, Error.t) result
end
