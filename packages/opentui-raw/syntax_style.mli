(** Native syntax-style registry shared by text buffers. *)

type t

val create : unit -> (t, Error.t) result
val register_style :
  t -> name:string -> fg:Native.color option -> bg:Native.color option -> attributes:int32 -> (int32, Error.t) result
val resolve_style : t -> string -> (int32 option, Error.t) result
val style_count : t -> (int32, Error.t) result
val close : t -> (unit, Error.t) result

module Private : sig
  val raw : t -> Native_token.Syntax_style.t
  val with_open :
    t ->
    (Native_token.Syntax_style.t -> ('a, Error.t) result) ->
    ('a, Error.t) result
  val is_open : t -> bool
end
