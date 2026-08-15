type highlight = {
  start : int;
  end_ : int;
  style_id : int;
  priority : int option;
  hl_ref : int option;
}

type t

val of_raw : Opentui_raw.Text_buffer.t -> Lib.Text_metrics.width_method -> t
val raw : t -> Opentui_raw.Text_buffer.t
val is_open : t -> bool
val width_method : t -> Lib.Text_metrics.width_method
val text : t -> string
val set_text : t -> string -> unit
val append_text : t -> string -> unit
val clear_text : t -> unit
val reset_text : t -> unit
val styled_text : t -> Lib.Styled_text.t option
val set_styled_text : t -> Lib.Styled_text.t -> unit
val default_fg : t -> Color.t option
val set_default_fg : t -> Color.t option -> unit
val default_bg : t -> Color.t option
val set_default_bg : t -> Color.t option -> unit
val default_attributes : t -> int option
val set_default_attributes : t -> int option -> unit
val reset_defaults : t -> unit
val syntax_style : t -> Syntax_style.t option
val set_syntax_style : t -> Syntax_style.t option -> unit
val tab_width : t -> int
val set_tab_width : t -> int -> unit
val add_highlight : t -> line:int -> highlight -> unit
val remove_highlights_by_ref : t -> int -> unit
val clear_line_highlights : t -> int -> unit
val clear_all_highlights : t -> unit
val line_highlights : t -> int -> highlight list
val highlight_count : t -> int
