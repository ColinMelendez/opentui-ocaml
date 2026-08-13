(** Typed notifications owned by one renderer and shared by its normal
    render context. *)

type resize_event = {
  width : int32;
  height : int32;
}

type frame_event = {
  frame_id : int64;
}

type t

val on_resize : t -> (resize_event -> unit) -> Event_subscription.t
val once_resize : t -> (resize_event -> unit) -> Event_subscription.t
val prepend_resize : t -> (resize_event -> unit) -> Event_subscription.t
val on_frame : t -> (frame_event -> unit) -> Event_subscription.t

module Private : sig
  val create : unit -> t
  val emit_resize : t -> resize_event -> bool
  val emit_frame : t -> frame_event -> bool
  val clear : t -> unit
end
