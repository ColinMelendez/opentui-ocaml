(** Unified visual-line metadata consumed by gutter renderables. *)

type t = {
  line_start_cols : int array;
  line_width_cols : int array;
  line_width_cols_max : int;
  line_sources : int array;
  line_wraps : int array;
}

val of_text_buffer_view : Text_buffer_view.line_info -> t
val of_editor_view : Editor_view.line_info -> t
val line_count : t -> int
