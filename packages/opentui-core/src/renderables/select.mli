(** Keyboard-navigable option list renderable. *)

type option_item = {
  name : string;
  description : string;
  value : string option;
}

type action = Move_up | Move_down | Move_up_fast | Move_down_fast | Select_current
type key_binding = action Lib.Keybinding.binding
type selection_change = { index : int; option : option_item option }
type t

val create :
  Render_context.t ->
  ?id:string ->
  ?options:option_item list ->
  ?selected_index:int ->
  ?background_color:Color.t ->
  ?text_color:Color.t ->
  ?focused_background_color:Color.t ->
  ?focused_text_color:Color.t ->
  ?selected_background_color:Color.t ->
  ?selected_text_color:Color.t ->
  ?description_color:Color.t ->
  ?selected_description_color:Color.t ->
  ?font:Ascii_font_spec.name ->
  ?show_scroll_indicator:bool ->
  ?wrap_selection:bool ->
  ?show_description:bool ->
  ?show_selection_indicator:bool ->
  ?item_spacing:int ->
  ?fast_scroll_step:int ->
  ?key_bindings:key_binding list ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val options : t -> option_item list
val set_options : t -> option_item list -> (unit, Error.t) result
val selected_index : t -> int
val set_selected_index : t -> int -> (unit, Error.t) result
val selected_option : t -> option_item option
val background_color : t -> Color.t
val set_background_color : t -> Color.t -> (unit, Error.t) result
val text_color : t -> Color.t
val set_text_color : t -> Color.t -> (unit, Error.t) result
val focused_background_color : t -> Color.t
val set_focused_background_color : t -> Color.t -> (unit, Error.t) result
val focused_text_color : t -> Color.t
val set_focused_text_color : t -> Color.t -> (unit, Error.t) result
val selected_background_color : t -> Color.t
val set_selected_background_color : t -> Color.t -> (unit, Error.t) result
val selected_text_color : t -> Color.t
val set_selected_text_color : t -> Color.t -> (unit, Error.t) result
val description_color : t -> Color.t
val set_description_color : t -> Color.t -> (unit, Error.t) result
val selected_description_color : t -> Color.t
val set_selected_description_color : t -> Color.t -> (unit, Error.t) result
val font : t -> Ascii_font_spec.name option
val set_font : t -> Ascii_font_spec.name option -> (unit, Error.t) result
val move_up : t -> ?steps:int -> unit -> (unit, Error.t) result
val move_down : t -> ?steps:int -> unit -> (unit, Error.t) result
val select_current : t -> (unit, Error.t) result
val handle_key_press : t -> Lib.Key_handler.key_event -> bool

val show_scroll_indicator : t -> bool
val set_show_scroll_indicator : t -> bool -> (unit, Error.t) result
val wrap_selection : t -> bool
val set_wrap_selection : t -> bool -> unit
val show_description : t -> bool
val set_show_description : t -> bool -> (unit, Error.t) result
val show_selection_indicator : t -> bool
val set_show_selection_indicator : t -> bool -> (unit, Error.t) result
val item_spacing : t -> int
val set_item_spacing : t -> int -> (unit, Error.t) result
val fast_scroll_step : t -> int
val set_fast_scroll_step : t -> int -> (unit, Error.t) result
val set_key_bindings : t -> key_binding list -> unit

val on_selection_changed : t -> (selection_change -> unit) -> Event_subscription.t
val on_item_selected : t -> (selection_change -> unit) -> Event_subscription.t
val destroy : t -> unit
