(** Portable ANSI vocabulary from the reference core. *)

val alternate_screen : string
val main_screen : string
val reset : string
val reset_scroll_region : string
val cursor_home : string
val clear_screen : string
val clear_saved_lines : string
val bracketed_paste_start : string
val bracketed_paste_end : string

val scroll_region : top:int -> bottom:int -> (string, string) result
val cursor_position : row:int -> column:int -> (string, string) result
val cursor_move : row:int -> column:int -> (string, string) result
val scroll_up : lines:int -> (string, string) result
val scroll_down : lines:int -> (string, string) result
val move_cursor : row:int -> column:int -> (string, string) result
val move_cursor_and_clear : row:int -> column:int -> (string, string) result
val rgb_background : red:int -> green:int -> blue:int -> (string, string) result
val reset_background : string
