(** A viewport over {!Edit_buffer} with display-column wrapping and selection. *)

type viewport = { offset_y : int; offset_x : int; height : int; width : int }
type wrap_mode = No_wrap | Char | Word
type visual_cursor = {
  row : int;
  col : int;
  logical_row : int;
  logical_col : int;
  offset : int;
}

type line_info = {
  line_start_cols : int array;
  line_width_cols : int array;
  line_width_cols_max : int;
  line_sources : int array;
  line_wraps : int array;
}

type measure = { line_count : int; width_cols_max : int }
type t

val create : Edit_buffer.t -> viewport_width:int -> viewport_height:int -> t
val set_viewport_size : t -> width:int -> height:int -> unit
val set_viewport : t -> x:int -> y:int -> width:int -> height:int -> ?move_cursor:bool -> unit -> unit
val viewport : t -> viewport
val set_scroll_margin : t -> int -> unit
val set_wrap_mode : t -> wrap_mode -> unit
val wrap_mode : t -> wrap_mode
val virtual_line_count : t -> int
val total_virtual_line_count : t -> int

val set_selection : t -> start:int -> end_:int -> unit
val update_selection : t -> end_:int -> unit
val reset_selection : t -> unit
val selection : t -> (int * int) option
val selected_range : t -> (int * int) option
val has_selection : t -> bool
val set_local_selection :
  t -> anchor_x:int -> anchor_y:int -> focus_x:int -> focus_y:int -> unit
val update_local_selection :
  t -> anchor_x:int -> anchor_y:int -> focus_x:int -> focus_y:int -> unit
val reset_local_selection : t -> unit
val selected_text : t -> (string, Error.t) result

val cursor : t -> (int * int, Error.t) result
val text : t -> (string, Error.t) result
val visual_cursor : t -> (visual_cursor, Error.t) result
(** Returns viewport-relative visual coordinates plus logical coordinates. *)
val absolute_visual_cursor : t -> (visual_cursor, Error.t) result
(** Returns document-absolute visual coordinates for renderer scrolling. *)
val move_up_visual : t -> (unit, Error.t) result
val move_down_visual : t -> (unit, Error.t) result
val delete_selected_text : t -> (unit, Error.t) result
val set_cursor_by_offset : t -> int -> (unit, Error.t) result
val next_word_boundary : t -> (Edit_buffer.cursor, Error.t) result
val previous_word_boundary : t -> (Edit_buffer.cursor, Error.t) result
val eol : t -> (Edit_buffer.cursor, Error.t) result
val visual_sol : t -> (visual_cursor, Error.t) result
val visual_eol : t -> (visual_cursor, Error.t) result
val line_info : t -> line_info
val logical_line_info : t -> line_info

val set_placeholder_styled_text : t -> Lib.Styled_text.chunk list -> unit
val placeholder_styled_text : t -> Lib.Styled_text.chunk list
val set_tab_indicator : t -> string -> unit
val tab_indicator : t -> string
val set_tab_indicator_color : t -> Lib.Rgba.t -> unit
val tab_indicator_color : t -> Lib.Rgba.t option
val measure_for_dimensions : t -> width:int -> height:int -> measure
val edit_buffer : t -> Edit_buffer.t
val extmarks : t -> (Lib.Extmarks.t, Error.t) result
val destroy : t -> unit
val is_destroyed : t -> bool
