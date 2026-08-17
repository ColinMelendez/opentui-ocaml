(** High-level renderer ownership over the pinned native OpenTUI renderer. *)

type t
(** A renderer owner. It owns the native renderer, render context, and its
    current and next borrowed buffer views. *)

type render_status = Rendered | Skipped | Failed
(** The native outcome of one explicit frame execution. *)

type post_process =
  Buffer.t -> delta_time:float -> (unit, Error.t) result
(** A synchronous, owner-local post-process applied to the next buffer after
    retained renderables and before the diagnostic console draws. The delta is
    measured in seconds by the caller-owned renderer scheduler. *)

type post_process_id

type resize_event = Render_context.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Render_context.frame_event = {
  frame_id : int64;
}

type render_error_event = Render_context.render_error_event = {
  error : Error.t;
  renderable_num : int option;
}

type capabilities_event = Render_context.capabilities_event
type palette_event = Render_context.palette_event
type theme_mode = Render_context.theme_mode
type theme_mode_event = Render_context.theme_mode_event
type selection_event = Render_context.selection_event
type focus_event = Render_context.focus_event
type theme_waiter = Renderer_theme_mode.waiter
type pixel_resolution = Render_context.pixel_resolution
type render_geometry = Render_context.render_geometry

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

(** [create_with_clock] injects the clock used for theme query timeouts. *)
val create_with_clock :
  clock:Lib.Clock.t -> width:int32 -> height:int32 -> (t, Error.t) result

(** [context renderer] returns the shared capability view used by renderables. *)
val context : t -> Render_context.t

(** The retained root owned by the renderer. *)
val root : t -> Renderable.t

(** The root's physical layout-child capability. *)
val children : t -> Layout_children.t

(** The renderer-owned diagnostic console.  It is explicit and owner-local;
    creating or destroying a renderer does not replace process-global output
    functions. *)
val console : t -> Console.t

(** Current renderer dimensions. *)
val width : t -> (int32, Error.t) result
val height : t -> (int32, Error.t) result
val terminal_width : t -> (int32, Error.t) result
val terminal_height : t -> (int32, Error.t) result

(** The current frame identifier. *)
val frame_id : t -> (int64, Error.t) result

(** The latest copied terminal capability snapshot. *)
val capabilities : t -> (Terminal_capabilities.t option, Error.t) result
val width_method : t -> (Terminal_capabilities.unicode, Error.t) result
val palette : t -> (Lib.Terminal_palette.normalized option, Error.t) result
val theme_mode : t -> (theme_mode option, Error.t) result
val pixel_resolution : t -> (pixel_resolution option, Error.t) result
val render_geometry : t -> (render_geometry, Error.t) result

(** [has_pending_render renderer] reports whether a coalesced render request is
    waiting for the renderer scheduler. *)
val has_pending_render : t -> (bool, Error.t) result

(** Renderer-owned current and next buffers borrowed through {!Buffer}. *)
val current_buffer : t -> (Buffer.t, Error.t) result
val next_buffer : t -> (Buffer.t, Error.t) result

(** [request_render renderer] records one coalesced future render request. It
    does not execute a frame or start an Eio fiber. *)
val request_render : t -> (unit, Error.t) result
val request_live : t -> (unit, Error.t) result
val drop_live : t -> (unit, Error.t) result
val live_request_count : t -> (int, Error.t) result

val add_post_process : t -> post_process -> (post_process_id, Error.t) result
val remove_post_process : t -> post_process_id -> (unit, Error.t) result
val clear_post_processes : t -> (unit, Error.t) result

(** The current pointer selection, if one is active. *)
val selection : t -> (Lib.Selection.t option, Error.t) result

(** Clear the pointer selection and notify the selectable renderable that owns
    it. *)
val clear_selection : t -> (unit, Error.t) result

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

(** Register for recoverable frame failures. A callback may return a typed
    recoverable error without blocking later callbacks or scheduler recovery.
    Programmer exceptions follow the surrounding owner/Eio failure policy.
    [renderable_num] is [None] when the synchronous pipeline cannot attribute
    the failure without guessing. *)
val on_render_error :
  t ->
  (render_error_event -> (unit, Error.t) result) ->
  (Event_subscription.t, Error.t) result
val once_render_error :
  t ->
  (render_error_event -> (unit, Error.t) result) ->
  (Event_subscription.t, Error.t) result
val prepend_render_error :
  t ->
  (render_error_event -> (unit, Error.t) result) ->
  (Event_subscription.t, Error.t) result

val on_capabilities :
  t -> (capabilities_event -> unit) -> (Event_subscription.t, Error.t) result
val once_capabilities :
  t -> (capabilities_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_capabilities :
  t -> (capabilities_event -> unit) -> (Event_subscription.t, Error.t) result
val on_palette :
  t -> (palette_event -> unit) -> (Event_subscription.t, Error.t) result
val once_palette :
  t -> (palette_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_palette :
  t -> (palette_event -> unit) -> (Event_subscription.t, Error.t) result
val on_theme_mode :
  t -> (theme_mode_event -> unit) -> (Event_subscription.t, Error.t) result
val once_theme_mode :
  t -> (theme_mode_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_theme_mode :
  t -> (theme_mode_event -> unit) -> (Event_subscription.t, Error.t) result
val on_selection :
  t -> (selection_event -> unit) -> (Event_subscription.t, Error.t) result
val once_selection :
  t -> (selection_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_selection :
  t -> (selection_event -> unit) -> (Event_subscription.t, Error.t) result
val on_focus :
  t -> (focus_event -> unit) -> (Event_subscription.t, Error.t) result
val once_focus :
  t -> (focus_event -> unit) -> (Event_subscription.t, Error.t) result
val prepend_focus :
  t -> (focus_event -> unit) -> (Event_subscription.t, Error.t) result
val on_destroy :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val once_destroy :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val prepend_destroy :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result

val palette_query : t -> ?size:int -> ?legacy_tmux:bool -> unit -> string
val special_palette_query : t -> ?is_tmux:bool -> unit -> string
val osc_support_query : t -> string
val pixel_resolution_query : t -> string
val kitty_keyboard_flags :
  ?disambiguate:bool ->
  ?alternate_keys:bool ->
  ?events:bool ->
  ?all_keys_as_escapes:bool ->
  ?report_text:bool ->
  unit -> int
val kitty_keyboard_push : t -> ?events:bool -> unit -> bytes
val kitty_keyboard_pop : t -> bytes
val request_theme_query : t -> (unit, Error.t) result
val theme_query : t -> string option
val wait_for_theme_mode :
  t -> timeout_ms:int -> on_result:(theme_mode option -> unit) ->
  (theme_waiter, Error.t) result
val cancel_theme_waiter : t -> theme_waiter -> (unit, Error.t) result
val feed_palette_response : t -> string -> (bool, Error.t) result

val set_render_geometry :
  t -> Lib.Render_geometry.screen_mode -> footer_height:int -> (unit, Error.t) result

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
val render :
  ?delta_time:float -> t -> force:bool -> (render_status, Error.t) result

(** [destroy renderer] releases native resources and closes its context. It is
    idempotent and invalidates all borrowed buffers. *)
val destroy : t -> unit

(** [is_destroyed renderer] reports whether [destroy] has closed the owner. *)
val is_destroyed : t -> bool
