type t = {
  line_start_cols : int array;
  line_width_cols : int array;
  line_width_cols_max : int;
  line_sources : int array;
  line_wraps : int array;
}

let of_text_buffer_view (value : Text_buffer_view.line_info) =
  {
    line_start_cols = value.line_start_cols;
    line_width_cols = value.line_width_cols;
    line_width_cols_max = value.line_width_cols_max;
    line_sources = value.line_sources;
    line_wraps = value.line_wraps;
  }

let of_editor_view (value : Editor_view.line_info) =
  {
    line_start_cols = value.line_start_cols;
    line_width_cols = value.line_width_cols;
    line_width_cols_max = value.line_width_cols_max;
    line_sources = value.line_sources;
    line_wraps = value.line_wraps;
  }

let line_count value = Array.length value.line_sources
