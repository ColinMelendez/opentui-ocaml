(** Structured failures at plugin, slot, and retained-tree boundaries. *)

type phase =
  | Define
  | Install
  | Rollback
  | Render
  | Activate
  | Deactivate
  | Set_order
  | Uninstall
  | Fallback
  | Placeholder
  | Refresh
  | Create
  | Destroy
  | Reporter

type origin =
  | Plugin
  | Host
  | Retained_tree
  | Reporter

type view_error =
  | View_destroyed
  | View_attached
  | View_wrong_renderer
  | View_is_mount
  | View_already_claimed
  | View_duplicate

type cause =
  | Invalid_id of Plugin_id.error
  | Duplicate_plugin of Plugin_id.t
  | Duplicate_slot of Plugin_id.t
  | Scope_closed
  | Host_closed
  | Wrong_host
  | Busy
  | Already_uninstalled
  | Invalid_view of view_error
  | Renderer_error of Error.t
  | Callback_exception of {
      exception_value : exn;
      backtrace : Printexc.raw_backtrace;
    }
  | Reporter_exception of {
      exception_value : exn;
      backtrace : Printexc.raw_backtrace;
    }

type t = {
  plugin : Plugin_id.t option;
  slot : Plugin_id.t option;
  phase : phase;
  origin : origin;
  cause : cause;
}

val make :
  ?plugin:Plugin_id.t ->
  ?slot:Plugin_id.t ->
  phase:phase ->
  origin:origin ->
  cause:cause ->
  unit ->
  t

val with_context :
  t ->
  ?plugin:Plugin_id.t ->
  ?slot:Plugin_id.t ->
  phase:phase ->
  origin:origin ->
  unit ->
  t

val callback_exception :
  ?plugin:Plugin_id.t ->
  ?slot:Plugin_id.t ->
  phase:phase ->
  origin:origin ->
  exn ->
  unit ->
  t

val message : t -> string
val pp : Format.formatter -> t -> unit
val phase_message : phase -> string
val origin_message : origin -> string
val view_error_message : view_error -> string
