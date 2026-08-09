type t

type render_status = Rendered | Skipped | Failed

module Frame : sig
  type t

  val clear :
    t ->
    background:Opentui_raw.Color.t ->
    (unit, Error.t) result

  val set_cell :
    t ->
    x:int32 ->
    y:int32 ->
    character:int32 ->
    foreground:Opentui_raw.Color.t ->
    background:Opentui_raw.Color.t ->
    attributes:int32 ->
    (unit, Error.t) result

  val draw_text :
    t ->
    text:string ->
    x:int32 ->
    y:int32 ->
    foreground:Opentui_raw.Color.t ->
    background:Opentui_raw.Color.t ->
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

val create : width:int32 -> height:int32 -> (t, Error.t) result
val resize : t -> width:int32 -> height:int32 -> (unit, Error.t) result
val close : t -> unit
val begin_frame : t -> (Frame.t, Error.t) result
val present : Frame.t -> force:bool -> (render_status, Error.t) result
