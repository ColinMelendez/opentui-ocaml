(** A one-line retained diagnostic showing the monotonic time observed at the
    first draw. *)

type t

val create :
  Render_context.t ->
  ?id:string ->
  ?fg:Color.t ->
  ?label:string ->
  ?precision:int ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val runtime_ms : t -> float option
val fg : t -> Color.t
val set_fg : t -> Color.t -> (unit, Error.t) result
val set_color : t -> Color.t -> (unit, Error.t) result
val label : t -> string
val set_label : t -> string -> (unit, Error.t) result
val precision : t -> int
val set_precision : t -> int -> (unit, Error.t) result
val reset : t -> (unit, Error.t) result
val destroy : t -> unit
