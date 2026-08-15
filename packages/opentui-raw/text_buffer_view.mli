(** A view over one native {!Text_buffer}. *)

type wrap_mode = No_wrap | Char | Word
(** The reference text wrapping modes. *)

type measure = {
  line_count : int32;
  width_cols_max : int32;
}
(** The native measurement result used by Yoga. *)

type line_info = {
  line_start_cols : int32 array;
  line_width_cols : int32 array;
  line_width_cols_max : int32;
  line_sources : int32 array;
  line_wraps : int32 array;
}

type selection = {
  start : int;
  end_ : int;
}
(** A non-empty native text selection. *)

type t
(** An explicitly owned view. The parent text buffer remains the owner of the
    underlying text storage. *)

val create : Text_buffer.t -> (t, Error.t) result
(** [create buffer] creates a view over [buffer]. *)

val set_wrap_width : t -> int32 option -> (unit, Error.t) result
(** [set_wrap_width view None] selects intrinsic width measurement. *)

val set_wrap_mode : t -> wrap_mode -> (unit, Error.t) result
val set_first_line_offset : t -> int32 -> (unit, Error.t) result
val set_selection :
  t -> start:int -> end_:int -> ?bg_color:Color.t -> ?fg_color:Color.t ->
  unit -> (unit, Error.t) result
val update_selection :
  t -> end_:int -> ?bg_color:Color.t -> ?fg_color:Color.t ->
  unit -> (unit, Error.t) result
val reset_selection : t -> (unit, Error.t) result
val selection : t -> (selection option, Error.t) result
val set_local_selection :
  t -> anchor_x:int -> anchor_y:int -> focus_x:int -> focus_y:int ->
  ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (bool, Error.t) result
val update_local_selection :
  t -> anchor_x:int -> anchor_y:int -> focus_x:int -> focus_y:int ->
  ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (bool, Error.t) result
val reset_local_selection : t -> (unit, Error.t) result
val selected_text : t -> capacity:int -> (string, Error.t) result
val set_viewport_size : t -> width:int32 -> height:int32 -> (unit, Error.t) result
val set_viewport :
  t -> x:int32 -> y:int32 -> width:int32 -> height:int32 ->
  (unit, Error.t) result
val virtual_line_count : t -> (int, Error.t) result
val set_tab_indicator : t -> int32 -> (unit, Error.t) result
val set_tab_indicator_color : t -> Color.t -> (unit, Error.t) result
val set_truncate : t -> bool -> (unit, Error.t) result

val measure_for_dimensions :
  t -> width:int32 -> height:int32 -> (measure, Error.t) result
(** [measure_for_dimensions] measures without committing virtual-line drawing
    state, matching the native Yoga measurement path. *)

val line_info : t -> (line_info, Error.t) result
val logical_line_info : t -> (line_info, Error.t) result

val close : t -> (unit, Error.t) result
(** [close view] releases a view that is not attached to native measurement. *)

module Private : sig
  val with_open :
    t ->
    (Native_token.Text_buffer_view.t -> ('a, Error.t) result) ->
    ('a, Error.t) result
  val claim_measure_user : t -> (unit, Error.t) result
  val release_measure_user : t -> unit
end
