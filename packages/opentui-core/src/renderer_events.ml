type resize_event = {
  width : int32;
  height : int32;
}

type frame_event = {
  frame_id : int64;
}

type render_error_event = {
  error : Error.t;
  renderable_num : int option;
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

type t = {
  resize : resize_event Event_kernel.t;
  frame : frame_event Event_kernel.t;
  render_error : render_error_event Event_kernel.t;
  capabilities : capabilities_event Event_kernel.t;
  palette : palette_event Event_kernel.t;
  theme_mode : theme_mode_event Event_kernel.t;
  selection : selection_event Event_kernel.t;
  focus : focus_event Event_kernel.t;
  destroy : unit Event_kernel.t;
  handler_error : handler_error Event_kernel.t;
}

let on_resize events callback = Event_kernel.on events.resize callback
let once_resize events callback = Event_kernel.once events.resize callback
let prepend_resize events callback = Event_kernel.prepend events.resize callback
let on_frame events callback = Event_kernel.on events.frame callback
let once_frame events callback = Event_kernel.once events.frame callback
let prepend_frame events callback = Event_kernel.prepend events.frame callback
let adapt_render_error_callback callback event =
  match callback event with
  | Ok () -> ()
  | Error error -> ignore error

let on_render_error events callback =
  Event_kernel.on events.render_error (adapt_render_error_callback callback)

let once_render_error events callback =
  Event_kernel.once events.render_error (adapt_render_error_callback callback)

let prepend_render_error events callback =
  Event_kernel.prepend events.render_error (adapt_render_error_callback callback)
let on_capabilities events callback =
  Event_kernel.on events.capabilities callback
let once_capabilities events callback =
  Event_kernel.once events.capabilities callback
let prepend_capabilities events callback =
  Event_kernel.prepend events.capabilities callback
let on_palette events callback = Event_kernel.on events.palette callback
let once_palette events callback = Event_kernel.once events.palette callback
let prepend_palette events callback = Event_kernel.prepend events.palette callback
let on_theme_mode events callback = Event_kernel.on events.theme_mode callback
let once_theme_mode events callback = Event_kernel.once events.theme_mode callback
let prepend_theme_mode events callback = Event_kernel.prepend events.theme_mode callback
let on_selection events callback = Event_kernel.on events.selection callback
let once_selection events callback = Event_kernel.once events.selection callback
let prepend_selection events callback = Event_kernel.prepend events.selection callback
let on_focus events callback = Event_kernel.on events.focus callback
let once_focus events callback = Event_kernel.once events.focus callback
let prepend_focus events callback = Event_kernel.prepend events.focus callback
let on_destroy events callback = Event_kernel.on events.destroy callback
let once_destroy events callback = Event_kernel.once events.destroy callback
let prepend_destroy events callback = Event_kernel.prepend events.destroy callback
let on_handler_error events callback = Event_kernel.on events.handler_error callback
let once_handler_error events callback = Event_kernel.once events.handler_error callback
let prepend_handler_error events callback =
  Event_kernel.prepend events.handler_error callback

module Private = struct
  let create () =
    {
      resize = Event_kernel.create ();
      frame = Event_kernel.create ();
      render_error = Event_kernel.create ();
      capabilities = Event_kernel.create ();
      palette = Event_kernel.create ();
      theme_mode = Event_kernel.create ();
      selection = Event_kernel.create ();
      focus = Event_kernel.create ();
      destroy = Event_kernel.create ();
      handler_error = Event_kernel.create ();
    }

  let emit_resize events event = Event_kernel.emit events.resize event
  let emit_frame events event = Event_kernel.emit events.frame event
  let emit_render_error events event = Event_kernel.emit events.render_error event
  let emit_capabilities events event = Event_kernel.emit events.capabilities event
  let emit_palette events event = Event_kernel.emit events.palette event
  let emit_theme_mode events event = Event_kernel.emit events.theme_mode event
  let emit_selection events event = Event_kernel.emit events.selection event
  let emit_focus events event = Event_kernel.emit events.focus event
  let emit_destroy events event = Event_kernel.emit events.destroy event
  let emit_handler_error events event = Event_kernel.emit events.handler_error event

  let clear events =
    Event_kernel.clear events.resize;
    Event_kernel.clear events.frame;
    Event_kernel.clear events.render_error;
    Event_kernel.clear events.capabilities;
    Event_kernel.clear events.palette;
    Event_kernel.clear events.theme_mode;
    Event_kernel.clear events.selection;
    Event_kernel.clear events.focus;
    Event_kernel.clear events.destroy;
    Event_kernel.clear events.handler_error
end
