(** Explicitly owned off-screen optimized buffers.

    Renderer buffers remain borrowed through {!Buffer}. This module owns the
    standalone native buffers used by framebuffer-backed renderables and font
    rasterizers. *)

type t

val create :
  ?id:string ->
  ?respect_alpha:bool ->
  ?width_method:Text_buffer.width_method ->
  width:int ->
  height:int ->
  unit ->
  (t, Error.t) result

val width : t -> (int, Error.t) result
val height : t -> (int, Error.t) result
val clear : t -> background:Color.t -> (unit, Error.t) result

val set_cell :
  t ->
  x:int ->
  y:int ->
  character:int32 ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
  (unit, Error.t) result

val set_cell_with_alpha_blending :
  t ->
  x:int ->
  y:int ->
  character:int32 ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
  (unit, Error.t) result

val draw_text :
  t ->
  text:string ->
  x:int ->
  y:int ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
  (unit, Error.t) result

val draw_text_buffer_view :
  t -> view:Text_buffer_view.t -> x:int -> y:int -> (unit, Error.t) result

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

val fill_rect :
  t ->
  x:int ->
  y:int ->
  width:int ->
  height:int ->
  background:Color.t ->
  (unit, Error.t) result

val draw_grayscale_buffer :
  t ->
  x:int ->
  y:int ->
  intensities:floatarray ->
  width:int ->
  height:int ->
  ?foreground:Color.t ->
  ?background:Color.t ->
  unit ->
  (unit, Error.t) result

val draw_grayscale_buffer_supersampled :
  t ->
  x:int ->
  y:int ->
  intensities:floatarray ->
  width:int ->
  height:int ->
  ?foreground:Color.t ->
  ?background:Color.t ->
  unit ->
  (unit, Error.t) result

val draw_frame_buffer :
  t ->
  source:t ->
  x:int ->
  y:int ->
  ?source_x:int ->
  ?source_y:int ->
  ?source_width:int ->
  ?source_height:int ->
  unit ->
  (unit, Error.t) result

val draw_image :
  t ->
  image:Image.t ->
  x:int ->
  y:int ->
  width:int ->
  height:int ->
  pixel_width:int ->
  pixel_height:int ->
  ?source_x:int ->
  ?source_y:int ->
  ?source_width:int ->
  ?source_height:int ->
  ?protocol:Image.protocol ->
  unit ->
  (unit, Error.t) result

val resize : t -> width:int -> height:int -> (unit, Error.t) result

type snapshot = int32 array * int32 array * int32 array * int32 array
val snapshot : t -> (snapshot, Error.t) result
val restore : t -> snapshot -> (unit, Error.t) result

val close : t -> unit

val raw : t -> Opentui_raw.Optimized_buffer.t
