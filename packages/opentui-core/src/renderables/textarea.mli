(** Multiline editor wrapper with placeholder, focus colors, and typed submit
    events. *)

type action = Edit_buffer_renderable.action
type key_binding = Edit_buffer_renderable.key_binding
type cursor_style = Edit_buffer_renderable.cursor_style
type t

val create :
  Render_context.t ->
  ?id:string ->
  ?initial_value:string ->
  ?placeholder:string ->
  ?placeholder_color:Color.t ->
  ?background_color:Color.t ->
  ?text_color:Color.t ->
  ?focused_background_color:Color.t ->
  ?focused_text_color:Color.t ->
  ?selection_bg:Color.t ->
  ?selection_fg:Color.t ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?selectable:bool ->
  ?attributes:int ->
  ?scroll_margin:float ->
  ?scroll_speed:float ->
  ?show_cursor:bool ->
  ?cursor_color:Color.t ->
  ?cursor_style:cursor_style ->
  ?tab_indicator:string ->
  ?tab_indicator_color:Color.t ->
  ?focusable:bool ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  ?key_bindings:key_binding list ->
  ?on_submit:(unit -> unit) ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val editor : t -> Edit_buffer_renderable.t
val text : t -> (string, Error.t) result
val value : t -> (string, Error.t) result
val set_text : t -> string -> (unit, Error.t) result
val replace_text : t -> string -> (unit, Error.t) result
val clear : t -> (unit, Error.t) result
val insert_text : t -> string -> (unit, Error.t) result
val insert_char : t -> string -> (unit, Error.t) result
val new_line : t -> (unit, Error.t) result
val delete_char : t -> (unit, Error.t) result
val delete_char_backward : t -> (unit, Error.t) result
val delete_line : t -> (unit, Error.t) result
val delete_to_line_start : t -> (unit, Error.t) result
val delete_to_line_end : t -> (unit, Error.t) result
val delete_word_forward : t -> (unit, Error.t) result
val delete_word_backward : t -> (unit, Error.t) result
val undo : t -> (string option, Error.t) result
val redo : t -> (string option, Error.t) result
val delete_selection : t -> (bool, Error.t) result
val selected_text : t -> (string, Error.t) result
val has_selection : t -> bool
val selection : t -> (int * int) option
val set_selection : t -> start:int -> end_:int -> (unit, Error.t) result
val set_selection_inclusive : t -> start:int -> end_:int -> (unit, Error.t) result
val clear_selection : t -> (bool, Error.t) result

val move_cursor_left : t -> ?select:bool -> unit -> (unit, Error.t) result
val move_cursor_right : t -> ?select:bool -> unit -> (unit, Error.t) result
val move_cursor_up : t -> ?select:bool -> unit -> (unit, Error.t) result
val move_cursor_down : t -> ?select:bool -> unit -> (unit, Error.t) result
val move_word_forward : t -> ?select:bool -> unit -> (unit, Error.t) result
val move_word_backward : t -> ?select:bool -> unit -> (unit, Error.t) result
val goto_line_home : t -> ?select:bool -> unit -> (unit, Error.t) result
val goto_line_end : t -> ?select:bool -> unit -> (unit, Error.t) result
val goto_visual_line_home : t -> ?select:bool -> unit -> (unit, Error.t) result
val goto_visual_line_end : t -> ?select:bool -> unit -> (unit, Error.t) result
val goto_buffer_home : t -> ?select:bool -> unit -> (unit, Error.t) result
val goto_buffer_end : t -> ?select:bool -> unit -> (unit, Error.t) result
val goto_line_start : t -> (unit, Error.t) result
val goto_line_text_end : t -> (unit, Error.t) result
val goto_line : t -> int -> (unit, Error.t) result
val cursor : t -> (Edit_buffer.cursor, Error.t) result
val visual_cursor : t -> (Editor_view.visual_cursor, Error.t) result
val set_cursor : t -> line:int -> col:int -> (unit, Error.t) result
val set_cursor_by_offset : t -> int -> (unit, Error.t) result
val select_all : t -> (unit, Error.t) result

val line_count : t -> (int, Error.t) result
val line_info : t -> Editor_view.line_info
val logical_line_info : t -> Editor_view.line_info
val virtual_line_count : t -> int
val scroll_y : t -> int
val viewport : t -> Editor_view.viewport
val set_viewport : t -> x:int -> y:int -> width:int -> height:int -> unit

val placeholder : t -> string option
val set_placeholder : t -> string option -> (unit, Error.t) result
val placeholder_color : t -> Color.t
val set_placeholder_color : t -> Color.t -> (unit, Error.t) result
val background_color : t -> Color.t
val set_background_color : t -> Color.t -> (unit, Error.t) result
val text_color : t -> Color.t
val set_text_color : t -> Color.t -> (unit, Error.t) result
val focused_background_color : t -> Color.t
val set_focused_background_color : t -> Color.t -> (unit, Error.t) result
val focused_text_color : t -> Color.t
val set_focused_text_color : t -> Color.t -> (unit, Error.t) result
val focused : t -> bool
val focus : t -> (unit, Error.t) result
val blur : t -> (unit, Error.t) result
val selectable : t -> bool
val set_selectable : t -> bool -> (unit, Error.t) result
val show_cursor : t -> bool
val set_show_cursor : t -> bool -> (unit, Error.t) result
val cursor_style : t -> cursor_style
val set_cursor_style : t -> cursor_style -> (unit, Error.t) result
val cursor_color : t -> Color.t
val set_cursor_color : t -> Color.t -> (unit, Error.t) result
val selection_bg : t -> Color.t option
val set_selection_bg : t -> Color.t option -> (unit, Error.t) result
val selection_fg : t -> Color.t option
val set_selection_fg : t -> Color.t option -> (unit, Error.t) result
val wrap_mode : t -> Text_buffer_view.wrap_mode
val set_wrap_mode : t -> Text_buffer_view.wrap_mode -> (unit, Error.t) result
val scroll_margin : t -> float
val set_scroll_margin : t -> float -> unit
val scroll_speed : t -> float
val set_scroll_speed : t -> float -> unit
val set_key_bindings : t -> key_binding list -> unit
val set_traits : t -> Edit_buffer_renderable.traits -> unit
val traits : t -> Edit_buffer_renderable.traits

val on_submit : t -> (unit -> unit) -> Event_subscription.t
val on_content_change : t -> (unit -> unit) -> Event_subscription.t
val on_cursor_change :
  t -> (Edit_buffer_renderable.cursor_change -> unit) -> Event_subscription.t

val submit : t -> (unit, Error.t) result
val handle_key_press : t -> Lib.Key_handler.key_event -> bool
val handle_paste : t -> Lib.Key_handler.paste_event -> unit
val destroy : t -> unit
