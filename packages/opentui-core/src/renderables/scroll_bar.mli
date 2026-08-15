(** Scrollbar composition built from {!Slider} and terminal arrow cells. *)

type orientation = Horizontal | Vertical
type scroll_unit = Absolute | Viewport | Content | Step

type t

val create :
  Render_context.t ->
  orientation:orientation ->
  ?id:string ->
  ?show_arrows:bool ->
  ?track_background_color:Color.t ->
  ?track_foreground_color:Color.t ->
  ?arrow_foreground_color:Color.t ->
  ?arrow_background_color:Color.t ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val slider : t -> Slider.t
val orientation : t -> orientation
val start_arrow : t -> Renderable.t
val end_arrow : t -> Renderable.t
val track_background_color : t -> Color.t
val set_track_background_color : t -> Color.t -> (unit, Error.t) result
val track_foreground_color : t -> Color.t
val set_track_foreground_color : t -> Color.t -> (unit, Error.t) result
val arrow_foreground_color : t -> Color.t
val set_arrow_foreground_color : t -> Color.t -> (unit, Error.t) result
val arrow_background_color : t -> Color.t
val set_arrow_background_color : t -> Color.t -> (unit, Error.t) result

val visible : t -> bool
val set_visible : t -> bool -> (unit, Error.t) result
val reset_visibility_control : t -> unit
val show_arrows : t -> bool
val set_show_arrows : t -> bool -> (unit, Error.t) result

val scroll_size : t -> float
val set_scroll_size : t -> float -> (unit, Error.t) result
val scroll_position : t -> float
val set_scroll_position : t -> float -> (unit, Error.t) result
val viewport_size : t -> float
val set_viewport_size : t -> float -> (unit, Error.t) result
val scroll_step : t -> float option
val set_scroll_step : t -> float option -> (unit, Error.t) result
val scroll_by : t -> float -> scroll_unit -> (unit, Error.t) result

val handle_key_press : t -> Lib.Key_handler.key_event -> bool
val on_change : t -> (float -> unit) -> Event_subscription.t
val destroy : t -> unit
