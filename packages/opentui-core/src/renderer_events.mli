(** Typed notifications owned by one renderer and shared by its normal
    render context. *)

type resize_event = {
  width : int32;
  height : int32;
}

type frame_event = {
  frame_id : int64;
}

type capabilities_event = Terminal_capabilities.t
type palette_event = Lib.Terminal_palette.normalized
type theme_mode_event = Renderer_theme_mode.mode
type selection_event = Lib.Selection.t option

type focus_event = {
  current : int option;
  previous : int option;
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
val on_capabilities : t -> (capabilities_event -> unit) -> Event_subscription.t
val once_capabilities : t -> (capabilities_event -> unit) -> Event_subscription.t
val prepend_capabilities :
  t -> (capabilities_event -> unit) -> Event_subscription.t
val on_palette : t -> (palette_event -> unit) -> Event_subscription.t
val once_palette : t -> (palette_event -> unit) -> Event_subscription.t
val prepend_palette : t -> (palette_event -> unit) -> Event_subscription.t
val on_theme_mode : t -> (theme_mode_event -> unit) -> Event_subscription.t
val once_theme_mode : t -> (theme_mode_event -> unit) -> Event_subscription.t
val prepend_theme_mode : t -> (theme_mode_event -> unit) -> Event_subscription.t
val on_selection : t -> (selection_event -> unit) -> Event_subscription.t
val once_selection : t -> (selection_event -> unit) -> Event_subscription.t
val prepend_selection : t -> (selection_event -> unit) -> Event_subscription.t
val on_focus : t -> (focus_event -> unit) -> Event_subscription.t
val once_focus : t -> (focus_event -> unit) -> Event_subscription.t
val prepend_focus : t -> (focus_event -> unit) -> Event_subscription.t
val on_destroy : t -> (unit -> unit) -> Event_subscription.t
val once_destroy : t -> (unit -> unit) -> Event_subscription.t
val prepend_destroy : t -> (unit -> unit) -> Event_subscription.t
val on_handler_error : t -> (handler_error -> unit) -> Event_subscription.t
val once_handler_error : t -> (handler_error -> unit) -> Event_subscription.t
val prepend_handler_error : t -> (handler_error -> unit) -> Event_subscription.t

module Private : sig
  val create : unit -> t
  val emit_resize : t -> resize_event -> bool
  val emit_frame : t -> frame_event -> bool
  val emit_capabilities : t -> capabilities_event -> bool
  val emit_palette : t -> palette_event -> bool
  val emit_theme_mode : t -> theme_mode_event -> bool
  val emit_selection : t -> selection_event -> bool
  val emit_focus : t -> focus_event -> bool
  val emit_destroy : t -> unit -> bool
  val emit_handler_error : t -> handler_error -> bool
  val clear : t -> unit
end
