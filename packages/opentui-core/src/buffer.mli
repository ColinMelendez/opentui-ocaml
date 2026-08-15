(** Borrowed drawing surfaces owned by a renderer.

    A buffer is a checked core view over one native renderer buffer. The
    renderer owns the native storage; closing the renderer invalidates every
    buffer view obtained from it. *)

type t = Buffer_internal.t
(** A renderer-owned drawing surface. *)

(** [width buffer] returns the current number of columns. *)
val width : t -> (int32, Error.t) result

(** [height buffer] returns the current number of rows. *)
val height : t -> (int32, Error.t) result

(** [clear buffer ~background] fills the surface with [background]. *)
val clear : t -> background:Color.t -> (unit, Error.t) result

(** [set_cell buffer ...] writes one cell synchronously. *)
val set_cell :
  t ->
  x:int32 ->
  y:int32 ->
  character:int32 ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
    (unit, Error.t) result

(** [draw_text buffer ...] draws caller-owned text synchronously. *)
val draw_text :
  t ->
  text:string ->
  x:int32 ->
  y:int32 ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
    (unit, Error.t) result

(** [draw_box buffer ...] draws a box using the reference packed border
    representation. Border code points remain borrowed for the synchronous
    native call. *)
val draw_box :
  t ->
  x:int32 ->
  y:int32 ->
  width:int32 ->
  height:int32 ->
  border_chars:int32 array ->
  packed_options:int32 ->
  border_color:Color.t ->
  background_color:Color.t ->
  title_color:Color.t ->
  title:string option ->
  bottom_title:string option ->
  (unit, Error.t) result

(** [draw_text_buffer buffer view ~x ~y] draws the visible native text view at
    the signed destination origin. The renderer owns [buffer] and the text
    renderable owns [view]. *)
val draw_text_buffer :
  t ->
  view:Text_buffer_view.t ->
  x:int32 ->
  y:int32 ->
  (unit, Error.t) result

val draw_frame_buffer :
  t ->
  source:Owned_buffer.t ->
  x:int32 ->
  y:int32 ->
  ?source_x:int32 ->
  ?source_y:int32 ->
  ?source_width:int32 ->
  ?source_height:int32 ->
  unit ->
  (unit, Error.t) result

val draw_grid :
  t ->
  border_chars:int32 array ->
  border_foreground:Color.t ->
  border_background:Color.t ->
  column_offsets:int32 array ->
  row_offsets:int32 array ->
  draw_inner:bool ->
  draw_outer:bool ->
  (unit, Error.t) result

val set_cell_with_alpha_blending :
  t ->
  x:int32 ->
  y:int32 ->
  character:int32 ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
  (unit, Error.t) result

val fill_rect :
  t ->
  x:int32 ->
  y:int32 ->
  width:int32 ->
  height:int32 ->
  background:Color.t ->
  (unit, Error.t) result

(** [write_resolved_chars buffer ~output ~add_line_breaks] writes the
    resolved native output into caller-owned [output]. The returned count is
    the defined prefix length; insufficient capacity is a structured error. *)
val write_resolved_chars :
  t -> output:bytes -> add_line_breaks:bool -> (int32, Error.t) result

val draw_image :
  t ->
  image:Image.t ->
  x:int32 ->
  y:int32 ->
  width:int32 ->
  height:int32 ->
  pixel_width:int32 ->
  pixel_height:int32 ->
  ?source_x:int32 ->
  ?source_y:int32 ->
  ?source_width:int32 ->
  ?source_height:int32 ->
  ?protocol:Image.protocol ->
  unit -> (unit, Error.t) result

type color_target = Foreground | Background | Both

val color_matrix :
  t -> matrix:floatarray -> cell_mask:floatarray -> strength:float ->
  target:color_target -> (unit, Error.t) result

val color_matrix_uniform :
  t -> matrix:floatarray -> strength:float -> target:color_target ->
  (unit, Error.t) result

val push_scissor_rect :
  t -> x:int32 -> y:int32 -> width:int32 -> height:int32 -> (unit, Error.t) result
val pop_scissor_rect : t -> (unit, Error.t) result
val clear_scissor_rects : t -> (unit, Error.t) result
val push_opacity : t -> float -> (unit, Error.t) result
val pop_opacity : t -> (unit, Error.t) result
val current_opacity : t -> (float, Error.t) result
val clear_opacity : t -> (unit, Error.t) result

type snapshot = int32 array * int32 array * int32 array * int32 array
val snapshot : t -> (snapshot, Error.t) result
val restore : t -> snapshot -> (unit, Error.t) result

type cell_snapshot = {
  width : int32;
  height : int32;
  cells : snapshot;
}

val cell_snapshot : t -> (cell_snapshot, Error.t) result
