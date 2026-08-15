(** Grapheme-aware editing state used by editor renderables.

    The implementation keeps the edit model in OCaml while using the same
    display-column convention as the reference native editor: newlines count
    as one cursor column and offsets are display offsets, not byte offsets. *)

type width_method = Wcwidth | Unicode

type cursor = { row : int; col : int; offset : int }

type highlight = {
  start : int;
  end_ : int;
  style_id : int;
  priority : int option;
  hl_ref : int option;
}

type change = { start : int; deleted : int; inserted : int }

type t

val create : width_method -> t
val width_method : t -> width_method
val set_text : t -> string -> (unit, Error.t) result
val replace_text : t -> string -> (unit, Error.t) result
val line_count : t -> (int, Error.t) result
val text : t -> (string, Error.t) result

val insert_char : t -> string -> (unit, Error.t) result
val insert_text : t -> string -> (unit, Error.t) result
val delete_char : t -> (unit, Error.t) result
val delete_char_backward : t -> (unit, Error.t) result
val delete_range : t -> start_row:int -> start_col:int -> end_row:int -> end_col:int -> (unit, Error.t) result
val new_line : t -> (unit, Error.t) result
val delete_line : t -> (unit, Error.t) result

val move_cursor_left : t -> (unit, Error.t) result
val move_cursor_right : t -> (unit, Error.t) result
val move_cursor_up : t -> (unit, Error.t) result
val move_cursor_down : t -> (unit, Error.t) result
val goto_line : t -> int -> (unit, Error.t) result
val set_cursor : t -> line:int -> col:int -> (unit, Error.t) result
val set_cursor_to_line_col : t -> line:int -> col:int -> (unit, Error.t) result
val set_cursor_by_offset : t -> int -> (unit, Error.t) result
val cursor : t -> (cursor, Error.t) result
val next_word_boundary : t -> (cursor, Error.t) result
val previous_word_boundary : t -> (cursor, Error.t) result
val eol : t -> (cursor, Error.t) result
val offset_to_position : t -> int -> ((int * int) option, Error.t) result
val position_to_offset : t -> row:int -> col:int -> (int, Error.t) result
val line_start_offset : t -> int -> (int, Error.t) result
val text_range : t -> start_offset:int -> end_offset:int -> (string, Error.t) result
val text_range_by_coords : t -> start_row:int -> start_col:int -> end_row:int -> end_col:int -> (string, Error.t) result

val undo : t -> (string option, Error.t) result
val redo : t -> (string option, Error.t) result
val can_undo : t -> (bool, Error.t) result
val can_redo : t -> (bool, Error.t) result
val clear_history : t -> (unit, Error.t) result

val set_default_fg : t -> Lib.Rgba.t option -> (unit, Error.t) result
val set_default_bg : t -> Lib.Rgba.t option -> (unit, Error.t) result
val set_default_attributes : t -> int option -> (unit, Error.t) result
val reset_defaults : t -> (unit, Error.t) result
val default_fg : t -> (Lib.Rgba.t option, Error.t) result
val default_bg : t -> (Lib.Rgba.t option, Error.t) result
val default_attributes : t -> (int option, Error.t) result

val set_syntax_style : t -> Syntax_style.t option -> (unit, Error.t) result
val syntax_style : t -> (Syntax_style.t option, Error.t) result
val extmarks : t -> (Lib.Extmarks.t, Error.t) result
val add_highlight : t -> line:int -> highlight -> (unit, Error.t) result
val add_highlight_by_char_range : t -> highlight -> (unit, Error.t) result
val remove_highlights_by_ref : t -> int -> (unit, Error.t) result
val clear_line_highlights : t -> int -> (unit, Error.t) result
val clear_all_highlights : t -> (unit, Error.t) result
val line_highlights : t -> int -> (highlight list, Error.t) result

val on_change : t -> (change -> unit) -> Event_subscription.t
val clear : t -> (unit, Error.t) result
val destroy : t -> unit
val is_destroyed : t -> bool
