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

type render_error_event = Renderer_events.render_error_event = {
  error : Error.t;
  renderable_num : int option;
}

type capabilities_event = Renderer_events.capabilities_event
type palette_event = Renderer_events.palette_event
type theme_mode = Renderer_theme_mode.mode
type theme_mode_event = Renderer_events.theme_mode_event
type selection_event = Renderer_events.selection_event
type focus_event = Renderer_events.focus_event

type pixel_resolution = {
  width : int32;
  height : int32;
}

type render_geometry = Lib.Render_geometry.t

type handler_source = Renderer_events.handler_source = Keyboard | Pointer
type handler_scope = Renderer_events.handler_scope = Global | Renderable
type handler_kind = Renderer_events.handler_kind = Keypress | Keyrelease | Paste | Mouse

type handler_error = Renderer_events.handler_error = {
  source : handler_source;
  scope : handler_scope;
  kind : handler_kind;
  owner_num : int option;
  exception_value : exn;
}

(** [same_owner left right] is true when both contexts belong to the same
    renderer. *)
val same_owner : t -> t -> bool

(** The current renderer width. *)
val width : t -> (int32, Error.t) result
val terminal_width : t -> (int32, Error.t) result

(** The current renderer height. *)
val height : t -> (int32, Error.t) result
val terminal_height : t -> (int32, Error.t) result

(** The monotonically increasing frame identifier. *)
val frame_id : t -> (int64, Error.t) result

(** The latest copied terminal capability snapshot, when one is available. *)
val capabilities : t -> (Terminal_capabilities.t option, Error.t) result
val width_method : t -> (Terminal_capabilities.unicode, Error.t) result
val palette : t -> (Lib.Terminal_palette.normalized option, Error.t) result
val theme_mode : t -> (theme_mode option, Error.t) result
val pixel_resolution : t -> (pixel_resolution option, Error.t) result
val render_geometry : t -> (render_geometry, Error.t) result

(** The layout generation used to validate cached layout-dependent traversal. *)
val layout_generation : t -> (int64, Error.t) result

(** The render-list revision used to validate cached traversal structure. *)
val render_list_revision : t -> (int64, Error.t) result

(** The numeric identity of the currently focused renderable, when one is
    focused. *)
val focused_num : t -> (int option, Error.t) result

(** The optional owner-local clock capability. [None] means this context was
    created for synchronous operation without timing services. *)
val clock : t -> (Lib.Clock.t option, Error.t) result

(** [request_render context] records one coalesced future render request. *)
val request_render : t -> (unit, Error.t) result

(** [request_selection_update context] asks the renderer to reapply its active
    pointer selection after an owner-local translation change. *)
val request_selection_update : t -> (unit, Error.t) result

(** [has_pending_render context] reports whether a coalesced render request is
    waiting for the renderer scheduler. *)
val has_pending_render : t -> (bool, Error.t) result
val request_live : t -> (unit, Error.t) result
val drop_live : t -> (unit, Error.t) result
val live_request_count : t -> (int, Error.t) result

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

(** Frame registrations have the same order, one-shot, and prepend semantics as
    resize registrations. *)
val once_frame :
  t -> (frame_event -> unit) -> (Event_subscription.t, Error.t) result

val prepend_frame :
  t -> (frame_event -> unit) -> (Event_subscription.t, Error.t) result

(** A failed frame attempt is reported with no renderable attribution unless a
    future renderer traversal can establish one without guessing. A callback
    may return a typed recoverable error without blocking later callbacks.
    Programmer exceptions follow the surrounding owner/Eio failure policy. *)
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

val register_lifecycle_pass :
  t -> id:int -> (unit -> unit) -> (unit, Error.t) result
val unregister_lifecycle_pass : t -> id:int -> (unit, Error.t) result
val lifecycle_pass_count : t -> (int, Error.t) result

val on_handler_error :
  t -> (handler_error -> unit) -> (Event_subscription.t, Error.t) result

val once_handler_error :
  t -> (handler_error -> unit) -> (Event_subscription.t, Error.t) result

val prepend_handler_error :
  t -> (handler_error -> unit) -> (Event_subscription.t, Error.t) result

(** Register global keyboard handlers on the renderer-owned dispatcher. *)
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

module Private : sig
  type scheduler_wakeup

  (** Construction and mutation used by {!Renderer}. *)
  val new_owner : unit -> owner
  val create :
    owner:owner -> width:int32 -> height:int32 ->
    capabilities:Terminal_capabilities.t option ->
    clock:Lib.Clock.t option ->
    hit_grid:Opentui_raw.Renderer.Hit_grid.t -> t
  val set_capabilities : t -> Terminal_capabilities.t -> unit
  val set_palette : t -> Lib.Terminal_palette.normalized -> unit
  val set_theme_mode : t -> theme_mode -> unit
  val set_pixel_resolution : t -> pixel_resolution option -> unit
  val set_render_geometry :
    t -> Lib.Render_geometry.screen_mode -> footer_height:int -> unit
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
  val key_handler : t -> Lib.Key_handler.t
  val request_live : t -> unit
  val drop_live : t -> unit
  val live_request_count : t -> int
  val install_scheduler_wakeup : t -> (unit -> unit) -> scheduler_wakeup option
  val remove_scheduler_wakeup : t -> scheduler_wakeup -> unit
  val set_selection_update : t -> (unit -> unit) -> unit
  val clear_hit_grid_scissors : t -> unit
  val push_hit_scissor :
    t -> x:int -> y:int -> width:int -> height:int -> unit
  val pop_hit_scissor : t -> unit
  val add_hit_grid :
    t -> x:int -> y:int -> width:int -> height:int -> id:int -> unit
  val abort_hit_grid : t -> unit
  val hit_grid_dirty : t -> bool
  val set_captured_num : t -> int option -> unit
  val hit_test : t -> x:int -> y:int -> int option
  val close : t -> unit
  val is_open : t -> bool
  val events : t -> Renderer_events.t
end
