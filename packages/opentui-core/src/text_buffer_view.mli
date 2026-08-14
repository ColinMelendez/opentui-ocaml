(** Native measurement view over one {!Text_buffer} value. *)

type wrap_mode = No_wrap | Char | Word
(** The reference text wrapping modes. *)

type measure = {
  line_count : int32;
  width_cols_max : int32;
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

val measure_for_dimensions :
  t -> width:int32 -> height:int32 -> (measure, Error.t) result
(** [measure_for_dimensions] invokes the native measurement path without
    exposing native handles or callbacks. *)

val close : t -> (unit, Error.t) result
(** [close view] releases [view] when no native measure owner uses it. *)
