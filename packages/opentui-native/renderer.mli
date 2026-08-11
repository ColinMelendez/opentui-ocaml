(** Imperative frame renderer over the audited native OpenTUI buffer ABI.

    A renderer has at most one open frame. Frames are borrowed, become
    inactive after {!present}, and are invalidated when the renderer closes. *)

type t
(** A renderer owner. *)

type render_status = Rendered | Skipped | Failed
(** The result of presenting a frame. *)

module Frame : sig
  (** A single mutable frame owned by one renderer. *)
  type t

  (** [clear frame ~background] fills the frame with [background]. *)
  val clear :
    t ->
    background:Color.t ->
    (unit, Error.t) result

  (** [set_cell frame ...] updates one cell in the frame. *)
  val set_cell :
    t ->
    x:int32 ->
    y:int32 ->
    character:int32 ->
    foreground:Color.t ->
    background:Color.t ->
    attributes:int32 ->
    (unit, Error.t) result

  (** [draw_text frame ...] draws text synchronously into the frame. *)
  val draw_text :
    t ->
    text:string ->
    x:int32 ->
    y:int32 ->
    foreground:Color.t ->
    background:Color.t ->
    attributes:int32 ->
    (unit, Error.t) result

  (** [Ok count] reports the number of output bytes written. On success, the
      defined output is the prefix [output[0, count)]. Insufficient capacity
      returns [Error (Error.Native Output_too_small)] rather than a short
      write. *)
  val write_resolved_chars :
    t ->
    output:bytes ->
    add_line_breaks:bool ->
    (int32, Error.t) result
end

(** [create ~width ~height] creates a renderer with positive dimensions. *)
val create : width:int32 -> height:int32 -> (t, Error.t) result

(** [resize renderer ...] resizes the renderer when no frame is open. *)
val resize : t -> width:int32 -> height:int32 -> (unit, Error.t) result

(** [close renderer] releases native resources and invalidates open frames. It
    is idempotent. *)
val close : t -> unit

(** [begin_frame renderer] opens the renderer's single mutable frame. *)
val begin_frame : t -> (Frame.t, Error.t) result

(** [present frame ~force] renders the open frame and closes it, including when
    the native renderer reports [Skipped] or [Failed]. *)
val present : Frame.t -> force:bool -> (render_status, Error.t) result

(** [run_frame renderer ~draw] opens a frame, invokes [draw], and presents it
    on success. The frame is discarded on an error or exception; callback
    exceptions propagate after frame cleanup. *)
val run_frame :
  t ->
  force:bool ->
  draw:(Frame.t -> (unit, Error.t) result) ->
  (render_status, Error.t) result
