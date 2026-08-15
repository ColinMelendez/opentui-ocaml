(** Scrollable retained container with optional native scrollbars. *)

type sticky_start = Bottom | Top | Left | Right
type t

val create :
  Render_context.t ->
  ?id:string ->
  ?scroll_x:bool ->
  ?scroll_y:bool ->
  ?sticky_scroll:bool ->
  ?sticky_start:sticky_start ->
  ?viewport_culling:bool ->
  ?scroll_acceleration:Lib.Scroll_acceleration.t ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val wrapper : t -> Renderable.t
val viewport : t -> Renderable.t
val content : t -> Renderable.t
val children : t -> Layout_children.t
val vertical_scrollbar : t -> Scroll_bar.t
val horizontal_scrollbar : t -> Scroll_bar.t

val add : ?index:int -> t -> Renderable.t -> (int, Error.t) result
val remove : t -> Renderable.t -> (unit, Error.t) result
val scroll_top : t -> float
val set_scroll_top : t -> float -> (unit, Error.t) result
val scroll_left : t -> float
val set_scroll_left : t -> float -> (unit, Error.t) result
val scroll_width : t -> float
val scroll_height : t -> float
val viewport_width : t -> float
val viewport_height : t -> float
val scroll_by : t -> dx:float -> dy:float -> (unit, Error.t) result
val scroll_to : t -> x:float -> y:float -> (unit, Error.t) result
val scroll_child_into_view : t -> Renderable.t -> (unit, Error.t) result

val sticky_scroll : t -> bool
val set_sticky_scroll : t -> bool -> unit
val sticky_start : t -> sticky_start option
val set_sticky_start : t -> sticky_start option -> unit
val viewport_culling : t -> bool
val set_viewport_culling : t -> bool -> unit

val handle_key_press : t -> Lib.Key_handler.key_event -> bool
val destroy : t -> unit
