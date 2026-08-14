(** A retained renderable backed by native text storage and measurement. *)

type t
(** Text storage, a text view, and a native Yoga measure owner sharing one
    retained renderable. *)

val create :
  Render_context.t ->
  ?id:string ->
  ?width_method:Text_buffer.width_method ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  unit ->
  (t, Error.t) result
(** [create context ()] creates a text-buffer renderable with an attached
    native measure target. *)

val as_renderable : t -> Renderable.t

(** [text_buffer] returns the owned storage used by the renderable. Mutating
    the returned value directly does not invalidate Yoga; use [set_text],
    [append], or [clear] when changing text through this renderable. *)
val text_buffer : t -> Text_buffer.t

(** [text_buffer_view] returns the owned measurement view. Changes made
    directly to the view do not invalidate Yoga; use the renderable's wrapping
    operations when changing its measurement configuration. *)
val text_buffer_view : t -> Text_buffer_view.t

val set_text : t -> string -> (unit, Error.t) result
val append : t -> string -> (unit, Error.t) result
val clear : t -> (unit, Error.t) result

val wrap_mode : t -> Text_buffer_view.wrap_mode
val set_wrap_mode : t -> Text_buffer_view.wrap_mode -> (unit, Error.t) result

val measure_for_dimensions :
  t -> width:int32 -> height:int32 -> (Text_buffer_view.measure, Error.t) result

val destroy : t -> unit
