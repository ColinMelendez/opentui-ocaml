(** A retained renderable backed by an explicitly owned off-screen buffer. *)

type t

val create :
  Render_context.t ->
  ?id:string ->
  width:int ->
  height:int ->
  ?respect_alpha:bool ->
  ?width_method:Text_buffer.width_method ->
  ?focusable:bool ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val frame_buffer : t -> Owned_buffer.t
val resize : t -> width:int -> height:int -> (unit, Error.t) result
val width : t -> int
val height : t -> int
val destroy : t -> unit
