type t

type wrap_mode = No_wrap | Char | Word

type selection = {
  start : int;
  end_ : int;
  bg_color : Color.t option;
  fg_color : Color.t option;
}

type local_selection = {
  anchor_x : int;
  anchor_y : int;
  focus_x : int;
  focus_y : int;
  bg_color : Color.t option;
  fg_color : Color.t option;
}

val of_raw : Opentui_raw.Text_buffer_view.t -> Text_buffer_internal.t -> t
val raw : t -> Opentui_raw.Text_buffer_view.t
val buffer : t -> Text_buffer_internal.t
val is_open : t -> bool
val mark_closed : t -> unit
val wrap_width : t -> int32 option
val set_wrap_width : t -> int32 option -> unit
val wrap_mode : t -> wrap_mode
val set_wrap_mode : t -> wrap_mode -> unit
val first_line_offset : t -> int32
val set_first_line_offset : t -> int32 -> unit
val viewport : t -> int32 * int32 * int32 * int32
val set_viewport : t -> x:int32 -> y:int32 -> width:int32 -> height:int32 -> unit
val selection : t -> selection option
val set_selection : t -> selection option -> unit
val local_selection : t -> local_selection option
val set_local_selection : t -> local_selection option -> unit
val tab_indicator : t -> string
val set_tab_indicator : t -> string -> unit
val tab_indicator_color : t -> Color.t option
val set_tab_indicator_color : t -> Color.t option -> unit
val truncate : t -> bool
val set_truncate : t -> bool -> unit
