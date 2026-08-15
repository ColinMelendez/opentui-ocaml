(** Interactive text editing composed from {!Edit_buffer}, {!Editor_view}, and
    the native {!Text_buffer_renderable} drawing path. *)

type action =
  | Move_left
  | Move_right
  | Move_up
  | Move_down
  | Select_left
  | Select_right
  | Select_up
  | Select_down
  | Line_home
  | Line_end
  | Select_line_home
  | Select_line_end
  | Visual_line_home
  | Visual_line_end
  | Select_visual_line_home
  | Select_visual_line_end
  | Buffer_home
  | Buffer_end
  | Select_buffer_home
  | Select_buffer_end
  | Delete_line
  | Delete_to_line_end
  | Delete_to_line_start
  | Backspace
  | Delete
  | Newline
  | Undo
  | Redo
  | Word_forward
  | Word_backward
  | Select_word_forward
  | Select_word_backward
  | Delete_word_forward
  | Delete_word_backward
  | Select_all
  | Submit

type key_binding = action Lib.Keybinding.binding

type capture = Escape | Navigate | Submit | Tab

type traits = {
  capture : capture list;
  suspend : bool;
  status : string option;
}

type cursor_style = Block | Underline | Bar

type cursor_change = {
  line : int;
  visual_column : int;
}

type t

val create :
  Render_context.t ->
  ?id:string ->
  ?width_method:Edit_buffer.width_method ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?initial_text:string ->
  ?text_color:Color.t ->
  ?background_color:Color.t ->
  ?selection_bg:Color.t ->
  ?selection_fg:Color.t ->
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
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val text_renderable : t -> Text_buffer_renderable.t
val edit_buffer : t -> Edit_buffer.t
val editor_view : t -> Editor_view.t

val text : t -> (string, Error.t) result
val set_text : t -> string -> (unit, Error.t) result
val replace_text : t -> string -> (unit, Error.t) result
val clear : t -> (unit, Error.t) result
val insert_char : t -> string -> (unit, Error.t) result
val insert_text : t -> string -> (unit, Error.t) result
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

val set_selection : t -> start:int -> end_:int -> (unit, Error.t) result
val set_selection_inclusive : t -> start:int -> end_:int -> (unit, Error.t) result
val clear_selection : t -> (bool, Error.t) result
val delete_selection : t -> (bool, Error.t) result
val selection : t -> (int * int) option
val has_selection : t -> bool
val selected_text : t -> (string, Error.t) result

val line_count : t -> (int, Error.t) result
val line_info : t -> Editor_view.line_info
val logical_line_info : t -> Editor_view.line_info
val virtual_line_count : t -> int
val scroll_y : t -> int
val set_viewport : t -> x:int -> y:int -> width:int -> height:int -> unit
val viewport : t -> Editor_view.viewport

val selectable : t -> bool
val set_selectable : t -> bool -> (unit, Error.t) result
val show_cursor : t -> bool
val set_show_cursor : t -> bool -> (unit, Error.t) result
val cursor_style : t -> cursor_style
val set_cursor_style : t -> cursor_style -> (unit, Error.t) result
val cursor_color : t -> Color.t
val set_cursor_color : t -> Color.t -> (unit, Error.t) result
val text_color : t -> Color.t
val set_text_color : t -> Color.t -> (unit, Error.t) result
val background_color : t -> Color.t
val set_background_color : t -> Color.t -> (unit, Error.t) result
val selection_bg : t -> Color.t option
val set_selection_bg : t -> Color.t option -> (unit, Error.t) result
val selection_fg : t -> Color.t option
val set_selection_fg : t -> Color.t option -> (unit, Error.t) result
val set_wrap_mode : t -> Text_buffer_view.wrap_mode -> (unit, Error.t) result
val wrap_mode : t -> Text_buffer_view.wrap_mode
val set_scroll_margin : t -> float -> unit
val scroll_margin : t -> float
val set_scroll_speed : t -> float -> unit
val scroll_speed : t -> float

val traits : t -> traits
val set_traits : t -> traits -> unit
val set_key_bindings : t -> key_binding list -> unit

val on_cursor_change : t -> (cursor_change -> unit) -> Event_subscription.t
val on_content_change : t -> (unit -> unit) -> Event_subscription.t
val on_submit_action : t -> (unit -> unit) -> Event_subscription.t
val on_traits_change : t -> (traits -> unit) -> Event_subscription.t

val handle_key_press : t -> Lib.Key_handler.key_event -> bool
val handle_paste : t -> Lib.Key_handler.paste_event -> unit
val destroy : t -> unit
