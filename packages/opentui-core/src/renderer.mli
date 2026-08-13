(** High-level renderer ownership over the pinned native OpenTUI renderer. *)

type t
(** A renderer owner. It owns the native renderer, render context, and its
    current and next borrowed buffer views. *)

type render_status = Rendered | Skipped | Failed
(** The native outcome of one explicit frame execution. *)

type resize_event = Render_context.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Render_context.frame_event = {
  frame_id : int64;
}

(** [create ~width ~height] creates a renderer with positive dimensions. *)
val create : width:int32 -> height:int32 -> (t, Error.t) result

(** [context renderer] returns the shared capability view used by renderables. *)
val context : t -> Render_context.t

(** Current renderer dimensions. *)
val width : t -> (int32, Error.t) result
val height : t -> (int32, Error.t) result

(** The current frame identifier. *)
val frame_id : t -> (int64, Error.t) result

(** [has_pending_render renderer] reports whether a coalesced render request is
    waiting for the renderer scheduler. *)
val has_pending_render : t -> (bool, Error.t) result

(** Renderer-owned current and next buffers borrowed through {!Buffer}. *)
val current_buffer : t -> (Buffer.t, Error.t) result
val next_buffer : t -> (Buffer.t, Error.t) result

(** [request_render renderer] records one coalesced future render request. It
    does not execute a frame or start an Eio fiber. *)
val request_render : t -> (unit, Error.t) result

(** Register for renderer notifications. The context and renderer functions
    register on the same owner-local event source. *)
val on_resize :
  t -> (resize_event -> unit) -> (Event_subscription.t, Error.t) result
val once_resize :
  t -> (resize_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_resize :
  t -> (resize_event -> unit) -> (Event_subscription.t, Error.t) result
val on_frame :
  t -> (frame_event -> unit) -> (Event_subscription.t, Error.t) result

(** [resize renderer ...] mutates the native renderer's buffers in place and
    publishes the new dimensions. Borrowed buffer values remain the same
    values and observe the new dimensions. *)
val resize : t -> width:int32 -> height:int32 -> (unit, Error.t) result

(** [render renderer ~force] executes one explicit native frame. It clears the
    pending request after the native call and emits a frame notification only
    for a rendered frame. *)
val render : t -> force:bool -> (render_status, Error.t) result

(** [destroy renderer] releases native resources and closes its context. It is
    idempotent and invalidates all borrowed buffers. *)
val destroy : t -> unit

(** [is_destroyed renderer] reports whether [destroy] has closed the owner. *)
val is_destroyed : t -> bool
