(** A renderer-owned buffer view. The view becomes closed when its renderer
    closes; callers must not retain it as an independent owner. *)
type t

(** [width buffer] returns the current buffer width. *)
val width : t -> (int32, Error.t) result

(** [height buffer] returns the current buffer height. *)
val height : t -> (int32, Error.t) result

(** [clear buffer ~background] fills the buffer. *)
val clear : t -> background:Color.t -> (unit, Error.t) result

(** [set_cell buffer ...] updates one cell synchronously. *)
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

(** [draw_box buffer ...] draws a native box using an eleven-codepoint border
    array and packed border, fill, and title-alignment options. The title
    strings are consumed synchronously. *)
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

(** [draw_text_buffer_view buffer view ~x ~y] draws the visible native text
    view at the signed destination origin. The view remains owned by its text
    buffer and the buffer remains owned by its renderer. *)
val draw_text_buffer_view :
  t ->
  Text_buffer_view.t ->
  x:int32 ->
  y:int32 ->
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

val draw_frame_buffer :
  t ->
  source:Optimized_buffer.t ->
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

(** [write_resolved_chars buffer ~output ~add_line_breaks] writes the resolved
    output into caller-owned [output]. On success only the prefix reported by
    the returned count is defined; insufficient capacity is an error rather
    than a short write. *)
val write_resolved_chars :
  t ->
  output:bytes ->
  add_line_breaks:bool ->
  (int32, Error.t) result

val draw_image :
  t ->
  image:Native_token.Image.t ->
  x:int32 ->
  y:int32 ->
  width:int32 ->
  height:int32 ->
  pixel_width:int32 ->
  pixel_height:int32 ->
  source_x:int32 ->
  source_y:int32 ->
  source_width:int32 ->
  source_height:int32 ->
  protocol:int32 ->
  (unit, Error.t) result

val color_matrix :
  t -> matrix:floatarray -> cell_mask:floatarray -> strength:float ->
  target:int -> (unit, Error.t) result

val color_matrix_uniform :
  t -> matrix:floatarray -> strength:float -> target:int ->
  (unit, Error.t) result

val push_scissor_rect :
  t -> x:int32 -> y:int32 -> width:int32 -> height:int32 ->
  (unit, Error.t) result
val pop_scissor_rect : t -> (unit, Error.t) result
val clear_scissor_rects : t -> (unit, Error.t) result
val push_opacity : t -> float -> (unit, Error.t) result
val pop_opacity : t -> (unit, Error.t) result
val current_opacity : t -> (float, Error.t) result
val clear_opacity : t -> (unit, Error.t) result

type snapshot = int32 array * int32 array * int32 array * int32 array
val snapshot : t -> (snapshot, Error.t) result
val restore : t -> snapshot -> (unit, Error.t) result

module Private : sig
  (** Internal construction of a renderer-owned view. *)
  val of_native : Native_token.Buffer.t -> Native_owner.t -> t
end
