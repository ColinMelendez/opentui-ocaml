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

(** [write_resolved_chars buffer ~output ~add_line_breaks] writes the resolved
    output into caller-owned [output]. On success only the prefix reported by
    the returned count is defined; insufficient capacity is an error rather
    than a short write. *)
val write_resolved_chars :
  t ->
  output:bytes ->
  add_line_breaks:bool ->
  (int32, Error.t) result

module Private : sig
  (** Internal construction of a renderer-owned view. *)
  val of_native : Native_token.Buffer.t -> Native_owner.t -> t
end
