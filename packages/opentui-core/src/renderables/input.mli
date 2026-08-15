(** Single-line text input built on {!Textarea}. *)

type action = Textarea.action
type key_binding = Textarea.key_binding
type t

val create :
  Render_context.t ->
  ?id:string ->
  ?value:string ->
  ?placeholder:string ->
  ?placeholder_color:Color.t ->
  ?background_color:Color.t ->
  ?text_color:Color.t ->
  ?focused_background_color:Color.t ->
  ?focused_text_color:Color.t ->
  ?selection_bg:Color.t ->
  ?selection_fg:Color.t ->
  ?min_length:int ->
  ?max_length:int ->
  ?focusable:bool ->
  ?cursor_color:Color.t ->
  ?cursor_style:Textarea.cursor_style ->
  ?key_bindings:key_binding list ->
  ?on_input:(string -> unit) ->
  ?on_change:(string -> unit) ->
  ?on_enter:(string -> unit) ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val textarea : t -> Textarea.t
val value : t -> (string, Error.t) result
val text : t -> (string, Error.t) result
val set_value : t -> string -> (unit, Error.t) result
val set_text : t -> string -> (unit, Error.t) result
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
val show_cursor : t -> bool
val set_show_cursor : t -> bool -> (unit, Error.t) result
val cursor_style : t -> Textarea.cursor_style
val set_cursor_style : t -> Textarea.cursor_style -> (unit, Error.t) result
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
val min_length : t -> int
val set_min_length : t -> int -> (unit, Error.t) result
val max_length : t -> int
val set_max_length : t -> int -> (unit, Error.t) result
val focus : t -> (unit, Error.t) result
val blur : t -> (unit, Error.t) result
val focused : t -> bool
val submit : t -> (unit, Error.t) result
val handle_key_press : t -> Lib.Key_handler.key_event -> bool
val handle_paste : t -> Lib.Key_handler.paste_event -> unit

val on_input : t -> (string -> unit) -> Event_subscription.t
val on_change : t -> (string -> unit) -> Event_subscription.t
val on_enter : t -> (string -> unit) -> Event_subscription.t

val destroy : t -> unit
