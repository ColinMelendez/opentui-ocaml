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

type handler_source = Render_context.handler_source = Keyboard | Pointer
type handler_scope = Render_context.handler_scope = Global | Renderable
type handler_kind = Render_context.handler_kind = Keypress | Keyrelease | Paste | Mouse

type handler_error = Render_context.handler_error = {
  source : handler_source;
  scope : handler_scope;
  kind : handler_kind;
  owner_num : int option;
  exception_value : exn;
}

(** [create ~width ~height] creates a renderer with positive dimensions. *)
val create : width:int32 -> height:int32 -> (t, Error.t) result

(** [context renderer] returns the shared capability view used by renderables. *)
val context : t -> Render_context.t

(** The retained root owned by the renderer. *)
val root : t -> Renderable.t

(** The root's physical layout-child capability. *)
val children : t -> Layout_children.t

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
val once_frame :
  t -> (frame_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_frame :
  t -> (frame_event -> unit) -> (Event_subscription.t, Error.t) result

val on_handler_error :
  t -> (handler_error -> unit) -> (Event_subscription.t, Error.t) result
val once_handler_error :
  t -> (handler_error -> unit) -> (Event_subscription.t, Error.t) result
val prepend_handler_error :
  t -> (handler_error -> unit) -> (Event_subscription.t, Error.t) result

val on_keypress :
  t -> (Lib.Key_handler.key_event -> unit) -> (Event_subscription.t, Error.t) result
val once_keypress :
  t -> (Lib.Key_handler.key_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_keypress :
  t -> (Lib.Key_handler.key_event -> unit) -> (Event_subscription.t, Error.t) result
val on_keyrelease :
  t -> (Lib.Key_handler.key_event -> unit) -> (Event_subscription.t, Error.t) result
val once_keyrelease :
  t -> (Lib.Key_handler.key_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_keyrelease :
  t -> (Lib.Key_handler.key_event -> unit) -> (Event_subscription.t, Error.t) result
val on_paste :
  t -> (Lib.Key_handler.paste_event -> unit) -> (Event_subscription.t, Error.t) result
val once_paste :
  t -> (Lib.Key_handler.paste_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_paste :
  t -> (Lib.Key_handler.paste_event -> unit) -> (Event_subscription.t, Error.t) result

(** [handle_input renderer event] dispatches one already-framed parser event.
    Key and paste dispatch is synchronous. A mouse event uses the committed
    hit grid and retained-tree pointer route. The Boolean reports whether the
    parser event belongs to a dispatchable family. *)
val handle_input :
  t -> Lib.Stdin_parser.event -> (bool, Error.t) result

(** [hit_test renderer ~x ~y] looks up a renderable in the committed grid. *)
val hit_test :
  t -> x:int -> y:int -> (Renderable.t option, Error.t) result

(** [resize renderer ...] mutates the native renderer's buffers in place and
    publishes the new dimensions. Borrowed buffer values remain the same
    values and observe the new dimensions. *)
val resize : t -> width:int32 -> height:int32 -> (unit, Error.t) result

(** [render renderer ~force] executes one explicit native frame. It consumes
    the pending request before retained-tree collection so requests made during
    the frame remain pending for a later frame. A failed retained-tree or
    native presentation pass restores a pending request. A frame notification
    is emitted only for a rendered frame. *)
val render : t -> force:bool -> (render_status, Error.t) result

(** [destroy renderer] releases native resources and closes its context. It is
    idempotent and invalidates all borrowed buffers. *)
val destroy : t -> unit

(** [is_destroyed renderer] reports whether [destroy] has closed the owner. *)
val is_destroyed : t -> bool
