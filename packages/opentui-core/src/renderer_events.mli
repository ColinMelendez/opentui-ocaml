(** Typed notifications owned by one renderer and shared by its normal
    render context. *)

type resize_event = {
  width : int32;
  height : int32;
}

type frame_event = {
  frame_id : int64;
}

type handler_source = Keyboard | Pointer
type handler_scope = Global | Renderable
type handler_kind = Keypress | Keyrelease | Paste | Mouse

type handler_error = {
  source : handler_source;
  scope : handler_scope;
  kind : handler_kind;
  owner_num : int option;
  exception_value : exn;
}

type t

val on_resize : t -> (resize_event -> unit) -> Event_subscription.t
val once_resize : t -> (resize_event -> unit) -> Event_subscription.t
val prepend_resize : t -> (resize_event -> unit) -> Event_subscription.t
val on_frame : t -> (frame_event -> unit) -> Event_subscription.t
val once_frame : t -> (frame_event -> unit) -> Event_subscription.t
val prepend_frame : t -> (frame_event -> unit) -> Event_subscription.t
val on_handler_error : t -> (handler_error -> unit) -> Event_subscription.t
val once_handler_error : t -> (handler_error -> unit) -> Event_subscription.t
val prepend_handler_error : t -> (handler_error -> unit) -> Event_subscription.t

module Private : sig
  val create : unit -> t
  val emit_resize : t -> resize_event -> bool
  val emit_frame : t -> frame_event -> bool
  val emit_handler_error : t -> handler_error -> bool
  val clear : t -> unit
end
