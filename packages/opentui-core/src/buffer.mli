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

(** [write_resolved_chars buffer ~output ~add_line_breaks] writes the
    resolved native output into caller-owned [output]. The returned count is
    the defined prefix length; insufficient capacity is a structured error. *)
val write_resolved_chars :
  t -> output:bytes -> add_line_breaks:bool -> (int32, Error.t) result
