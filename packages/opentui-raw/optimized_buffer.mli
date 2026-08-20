(** An explicitly owned standalone optimized drawing buffer. *)

type t

val create :
  width:int32 ->
  height:int32 ->
  respect_alpha:bool ->
  width_method:int32 ->
  id:string ->
  (t, Error.t) result

val width : t -> (int32, Error.t) result
val height : t -> (int32, Error.t) result
val clear : t -> Color.t -> (unit, Error.t) result
type cell = int32 * int32 * int32 * Color.t * Color.t * int32
type text = string * int32 * int32 * Color.t * Color.t * int32
val set_cell : t -> cell -> (unit, Error.t) result
val set_cell_with_alpha_blending : t -> cell -> (unit, Error.t) result
val draw_text : t -> text -> (unit, Error.t) result
val draw_text_buffer_view :
  t -> Text_buffer_view.t -> int32 -> int32 -> (unit, Error.t) result
val fill_rect : t -> int32 * int32 * int32 * int32 * Color.t -> (unit, Error.t) result
val draw_grayscale_buffer :
  t ->
  int32 * int32 * floatarray * int32 * int32 * Color.t option * Color.t option ->
  (unit, Error.t) result
val draw_grayscale_buffer_supersampled :
  t ->
  int32 * int32 * floatarray * int32 * int32 * Color.t option * Color.t option ->
  (unit, Error.t) result
val draw_frame_buffer :
  t -> int32 * int32 * t * int32 * int32 * int32 * int32 -> (unit, Error.t) result
val draw_grid :
  t ->
  int32 array * Color.t * Color.t * int32 array * int32 array * bool * bool ->
  (unit, Error.t) result
val draw_image :
  t ->
  (int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 *
   int32 * Native_token.Image.t) -> (unit, Error.t) result
val resize : t -> int32 -> int32 -> (unit, Error.t) result
type snapshot = int32 array * int32 array * int32 array * int32 array
val snapshot : t -> (snapshot, Error.t) result
val restore : t -> snapshot -> (unit, Error.t) result
val close : t -> unit

module Private : sig
  val with_open : t -> (Native_token.Optimized_buffer.t -> ('a, Error.t) result) -> ('a, Error.t) result
  val handle : t -> Native_token.Optimized_buffer.t
  val owner : t -> Native_owner.t
end
