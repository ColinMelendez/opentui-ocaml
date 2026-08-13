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

(** The layout generation used to validate cached layout-dependent traversal. *)
val layout_generation : t -> (int64, Error.t) result

(** The render-list revision used to validate cached traversal structure. *)
val render_list_revision : t -> (int64, Error.t) result

(** The numeric identity of the currently focused renderable, when one is
    focused. *)
val focused_num : t -> (int option, Error.t) result

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
  val bump_layout_generation : t -> int64
  val bump_render_list_revision : t -> int64
  val layout_generation : t -> int64
  val render_list_revision : t -> int64
  val request_render : t -> unit
  val has_pending_render : t -> bool
  val clear_render_request : t -> unit
  val register_lifecycle_pass : t -> id:int -> (unit -> unit) -> unit
  val unregister_lifecycle_pass : t -> id:int -> unit
  val lifecycle_passes : t -> (unit -> unit) list
  val focus_renderable : t -> id:int -> blur:(unit -> unit) -> unit
  val blur_renderable : t -> id:int -> unit
  val focused_num : t -> int option
  val request_live : t -> unit
  val drop_live : t -> unit
  val live_request_count : t -> int
  val clear_hit_grid : t -> unit
  val add_hit_grid :
    t -> x:int -> y:int -> width:int -> height:int -> id:int -> unit
  val hit_grid_count : t -> int
  val close : t -> unit
  val is_open : t -> bool
  val events : t -> Renderer_events.t
end
