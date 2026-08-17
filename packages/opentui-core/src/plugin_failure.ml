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

let make ?plugin ?slot ~phase ~origin ~cause () =
  { plugin; slot; phase; origin; cause }

let with_context failure ?plugin ?slot ~phase ~origin () =
  {
    plugin = (match plugin with Some value -> Some value | None -> failure.plugin);
    slot = (match slot with Some value -> Some value | None -> failure.slot);
    phase;
    origin;
    cause = failure.cause;
  }

let callback_exception ?plugin ?slot ~phase ~origin exception_value () =
  make ?plugin ?slot ~phase ~origin
    ~cause:
      (Callback_exception
         { exception_value; backtrace = Printexc.get_raw_backtrace () })
    ()

let phase_message phase =
  match phase with
  | Define -> "define"
  | Install -> "install"
  | Rollback -> "rollback"
  | Render -> "render"
  | Activate -> "activate"
  | Deactivate -> "deactivate"
  | Set_order -> "set_order"
  | Uninstall -> "uninstall"
  | Fallback -> "fallback"
  | Placeholder -> "placeholder"
  | Refresh -> "refresh"
  | Create -> "create"
  | Destroy -> "destroy"
  | Reporter -> "reporter"

let origin_message origin =
  match origin with
  | Plugin -> "plugin"
  | Host -> "host"
  | Retained_tree -> "retained_tree"
  | Reporter -> "reporter"

let view_error_message error =
  match error with
  | View_destroyed -> "the view renderable is destroyed"
  | View_attached -> "the view renderable is already attached"
  | View_wrong_renderer -> "the view renderable belongs to another renderer"
  | View_is_mount -> "the slot mount cannot be returned as a view"
  | View_already_claimed -> "the slot view was already accepted by a mount"
  | View_duplicate -> "the same renderable occurs more than once in the output"

let cause_message cause =
  match cause with
  | Invalid_id error -> Plugin_id.error_message error
  | Duplicate_plugin id ->
      Format.asprintf "plugin %S is already installed" (Plugin_id.to_string id)
  | Duplicate_slot id ->
      Format.asprintf "slot %S is already declared by this host"
        (Plugin_id.to_string id)
  | Scope_closed -> "the plugin installation scope is closed"
  | Host_closed -> "the plugin host is closed"
  | Wrong_host -> "the slot and installation scope belong to different hosts"
  | Busy -> "the plugin or slot operation is structurally re-entrant"
  | Already_uninstalled -> "the plugin instance is already uninstalled"
  | Invalid_view error -> view_error_message error
  | Renderer_error error -> Error.message error
  | Callback_exception { exception_value; backtrace } ->
      Format.asprintf "callback raised %s (%s)"
        (Printexc.to_string exception_value)
        (Printexc.raw_backtrace_to_string backtrace)
  | Reporter_exception { exception_value; backtrace } ->
      Format.asprintf "reporter raised %s (%s)"
        (Printexc.to_string exception_value)
        (Printexc.raw_backtrace_to_string backtrace)

let message failure =
  let context =
    match failure.plugin, failure.slot with
    | None, None -> ""
    | Some plugin, None ->
        Format.asprintf " for plugin %S" (Plugin_id.to_string plugin)
    | None, Some slot -> Format.asprintf " for slot %S" (Plugin_id.to_string slot)
    | Some plugin, Some slot ->
        Format.asprintf " for plugin %S in slot %S"
          (Plugin_id.to_string plugin) (Plugin_id.to_string slot)
  in
  Format.asprintf "%s failure%s: %s (%s)" (phase_message failure.phase) context
    (cause_message failure.cause) (origin_message failure.origin)

let pp formatter failure = Format.pp_print_string formatter (message failure)
