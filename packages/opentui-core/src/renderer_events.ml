type resize_event = {
  width : int32;
  height : int32;
}

type frame_event = {
  frame_id : int64;
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
  handler_error : handler_error Event_kernel.t;
}

let on_resize events callback = Event_kernel.on events.resize callback
let once_resize events callback = Event_kernel.once events.resize callback
let prepend_resize events callback = Event_kernel.prepend events.resize callback
let on_frame events callback = Event_kernel.on events.frame callback
let once_frame events callback = Event_kernel.once events.frame callback
let prepend_frame events callback = Event_kernel.prepend events.frame callback
let on_handler_error events callback = Event_kernel.on events.handler_error callback
let once_handler_error events callback = Event_kernel.once events.handler_error callback
let prepend_handler_error events callback =
  Event_kernel.prepend events.handler_error callback

module Private = struct
  let create () =
    {
      resize = Event_kernel.create ();
      frame = Event_kernel.create ();
      handler_error = Event_kernel.create ();
    }

  let emit_resize events event = Event_kernel.emit events.resize event
  let emit_frame events event = Event_kernel.emit events.frame event
  let emit_handler_error events event = Event_kernel.emit events.handler_error event

  let clear events =
    Event_kernel.clear events.resize;
    Event_kernel.clear events.frame;
    Event_kernel.clear events.handler_error
end
