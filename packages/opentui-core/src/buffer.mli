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

(** [write_resolved_chars buffer ~output ~add_line_breaks] writes the
    resolved native output into caller-owned [output]. The returned count is
    the defined prefix length; insufficient capacity is a structured error. *)
val write_resolved_chars :
  t -> output:bytes -> add_line_breaks:bool -> (int32, Error.t) result
