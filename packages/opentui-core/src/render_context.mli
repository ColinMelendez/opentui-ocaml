(** Renderer-owned capabilities shared by retained renderables. *)

type t
(** A capability view over one renderer owner. *)

type owner
(** The identity shared by contexts belonging to one renderer. *)

type resize_event = Renderer_events.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Renderer_events.frame_event = {
  frame_id : int64;
}

(** [same_owner left right] is true when both contexts belong to the same
    renderer. *)
val same_owner : t -> t -> bool

(** The current renderer width. *)
val width : t -> (int32, Error.t) result

(** The current renderer height. *)
val height : t -> (int32, Error.t) result

(** The monotonically increasing frame identifier. *)
val frame_id : t -> (int64, Error.t) result

(** [request_render context] records one coalesced future render request. *)
val request_render : t -> (unit, Error.t) result

(** [has_pending_render context] reports whether a coalesced render request is
    waiting for the renderer scheduler. *)
val has_pending_render : t -> (bool, Error.t) result

(** Register for renderer resize notifications. *)
val on_resize :
  t -> (resize_event -> unit) -> (Event_subscription.t, Error.t) result

(** Register a resize callback that is removed before its first call. *)
val once_resize :
  t -> (resize_event -> unit) -> (Event_subscription.t, Error.t) result

(** Register a resize callback before existing callbacks. *)
val prepend_resize :
  t -> (resize_event -> unit) -> (Event_subscription.t, Error.t) result

(** Register for successful frame notifications. *)
val on_frame :
  t -> (frame_event -> unit) -> (Event_subscription.t, Error.t) result

module Private : sig
  (** Construction and mutation used by {!Renderer}. *)
  val new_owner : unit -> owner
  val create : owner:owner -> width:int32 -> height:int32 -> t
  val resize : t -> width:int32 -> height:int32 -> unit
  val advance_frame : t -> int64
  val request_render : t -> unit
  val has_pending_render : t -> bool
  val clear_render_request : t -> unit
  val close : t -> unit
  val is_open : t -> bool
  val events : t -> Renderer_events.t
end
