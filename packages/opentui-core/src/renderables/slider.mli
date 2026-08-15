(** A renderer-independent slider with keyboard and pointer control. *)

type orientation = Horizontal | Vertical

type t

val create :
  Render_context.t ->
  orientation:orientation ->
  ?id:string ->
  ?value:float ->
  ?min:float ->
  ?max:float ->
  ?viewport_size:float ->
  ?background_color:Color.t ->
  ?foreground_color:Color.t ->
  ?focusable:bool ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val orientation : t -> orientation
val value : t -> float
val set_value : t -> float -> (unit, Error.t) result
val min : t -> float
val set_min : t -> float -> (unit, Error.t) result
val max : t -> float
val set_max : t -> float -> (unit, Error.t) result
val viewport_size : t -> float
val set_viewport_size : t -> float -> (unit, Error.t) result
val background_color : t -> Color.t
val set_background_color : t -> Color.t -> (unit, Error.t) result
val foreground_color : t -> Color.t
val set_foreground_color : t -> Color.t -> (unit, Error.t) result

val handle_key_press : t -> Lib.Key_handler.key_event -> bool
val on_change : t -> (float -> unit) -> Event_subscription.t
val destroy : t -> unit
