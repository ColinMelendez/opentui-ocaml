(** Horizontal tab selector renderable. *)

type option_item = Select.option_item
type action = Move_left | Move_right | Select_current
type key_binding = action Lib.Keybinding.binding
type selection_change = { index : int; option : option_item option }
type t

val create :
  Render_context.t ->
  ?id:string ->
  ?options:option_item list ->
  ?tab_width:int ->
  ?background_color:Color.t ->
  ?text_color:Color.t ->
  ?focused_background_color:Color.t ->
  ?focused_text_color:Color.t ->
  ?selected_background_color:Color.t ->
  ?selected_text_color:Color.t ->
  ?selected_description_color:Color.t ->
  ?show_scroll_arrows:bool ->
  ?show_description:bool ->
  ?show_underline:bool ->
  ?wrap_selection:bool ->
  ?key_bindings:key_binding list ->
  ?width:Yoga.value ->
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
val selected_description_color : t -> Color.t
val set_selected_description_color : t -> Color.t -> (unit, Error.t) result
val move_left : t -> (unit, Error.t) result
val move_right : t -> (unit, Error.t) result
val select_current : t -> (unit, Error.t) result
val handle_key_press : t -> Lib.Key_handler.key_event -> bool

val tab_width : t -> int
val set_tab_width : t -> int -> (unit, Error.t) result
val show_scroll_arrows : t -> bool
val set_show_scroll_arrows : t -> bool -> (unit, Error.t) result
val show_description : t -> bool
val set_show_description : t -> bool -> (unit, Error.t) result
val show_underline : t -> bool
val set_show_underline : t -> bool -> (unit, Error.t) result
val wrap_selection : t -> bool
val set_wrap_selection : t -> bool -> unit
val set_key_bindings : t -> key_binding list -> unit

val on_selection_changed : t -> (selection_change -> unit) -> Event_subscription.t
val on_item_selected : t -> (selection_change -> unit) -> Event_subscription.t
val destroy : t -> unit
