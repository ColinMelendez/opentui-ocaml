(** Native measurement view over one {!Text_buffer} value. *)

type wrap_mode = No_wrap | Char | Word
(** The reference text wrapping modes. *)

type measure = {
  line_count : int32;
  width_cols_max : int32;
}

type line_info = {
  line_start_cols : int array;
  line_width_cols : int array;
  line_width_cols_max : int;
  line_sources : int array;
  line_wraps : int array;
}

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
(** The dimensions produced by native text measurement. *)

type t = Text_buffer_view_internal.t
(** An explicitly owned view whose text storage belongs to its parent buffer. *)

val create : Text_buffer.t -> (t, Error.t) result
(** [create buffer] creates a view over [buffer]. *)

val set_wrap_width : t -> int32 option -> (unit, Error.t) result
(** [set_wrap_width view width] selects the wrapping width; [None] selects
    intrinsic-width measurement. *)

val set_wrap_mode : t -> wrap_mode -> (unit, Error.t) result
val set_first_line_offset : t -> int32 -> (unit, Error.t) result

val set_selection :
  t -> start:int -> end_:int -> ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (unit, Error.t) result
val update_selection :
  t -> end_:int -> ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (unit, Error.t) result
val reset_selection : t -> (unit, Error.t) result
val selection : t -> (selection option, Error.t) result
val has_selection : t -> (bool, Error.t) result
val set_local_selection :
  t -> anchor_x:int -> anchor_y:int -> focus_x:int -> focus_y:int ->
  ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (bool, Error.t) result
val update_local_selection :
  t -> anchor_x:int -> anchor_y:int -> focus_x:int -> focus_y:int ->
  ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (bool, Error.t) result
val reset_local_selection : t -> (unit, Error.t) result
val selected_text : t -> (string, Error.t) result
val plain_text : t -> (string, Error.t) result

val set_viewport_size : t -> width:int32 -> height:int32 -> (unit, Error.t) result
val set_viewport : t -> x:int32 -> y:int32 -> width:int32 -> height:int32 -> (unit, Error.t) result
val viewport : t -> (int32 * int32 * int32 * int32, Error.t) result
val line_info : t -> (line_info, Error.t) result
val logical_line_info : t -> (line_info, Error.t) result
val virtual_line_count : t -> (int, Error.t) result

val set_tab_indicator : t -> string -> (unit, Error.t) result
val tab_indicator : t -> (string, Error.t) result
val set_tab_indicator_color : t -> Color.t -> (unit, Error.t) result
val tab_indicator_color : t -> (Color.t option, Error.t) result
val set_truncate : t -> bool -> (unit, Error.t) result
val truncate : t -> (bool, Error.t) result

val measure_for_dimensions :
  t -> width:int32 -> height:int32 -> (measure, Error.t) result
(** [measure_for_dimensions] invokes the native measurement path without
    exposing native handles or callbacks. *)

val close : t -> (unit, Error.t) result
(** [close view] releases [view] when no native measure owner uses it. *)
