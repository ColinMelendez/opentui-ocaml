(** A generic retained renderable whose drawing behavior is supplied by a
    typed callback. *)

type render =
  Buffer.t -> delta_time:float -> renderable:Renderable.t -> (unit, Error.t) result

type t

val create :
  Render_context.t ->
  ?id:string ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  ?focusable:bool ->
  ?render:render ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val children : t -> Layout_children.t
val set_render : t -> render option -> (unit, Error.t) result
val destroy : t -> unit
