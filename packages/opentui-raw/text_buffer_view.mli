(** A view over one native {!Text_buffer}. *)

type wrap_mode = No_wrap | Char | Word
(** The reference text wrapping modes. *)

type measure = {
  line_count : int32;
  width_cols_max : int32;
}
(** The native measurement result used by Yoga. *)

type t
(** An explicitly owned view. The parent text buffer remains the owner of the
    underlying text storage. *)

val create : Text_buffer.t -> (t, Error.t) result
(** [create buffer] creates a view over [buffer]. *)

val set_wrap_width : t -> int32 option -> (unit, Error.t) result
(** [set_wrap_width view None] selects intrinsic width measurement. *)

val set_wrap_mode : t -> wrap_mode -> (unit, Error.t) result
val set_first_line_offset : t -> int32 -> (unit, Error.t) result

val measure_for_dimensions :
  t -> width:int32 -> height:int32 -> (measure, Error.t) result
(** [measure_for_dimensions] measures without committing virtual-line drawing
    state, matching the native Yoga measurement path. *)

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
