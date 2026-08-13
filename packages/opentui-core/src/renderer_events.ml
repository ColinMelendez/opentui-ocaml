type resize_event = {
  width : int32;
  height : int32;
}

type frame_event = {
  frame_id : int64;
}

type t = {
  resize : resize_event Event_kernel.t;
  frame : frame_event Event_kernel.t;
}

let on_resize events callback = Event_kernel.on events.resize callback
let once_resize events callback = Event_kernel.once events.resize callback
let prepend_resize events callback = Event_kernel.prepend events.resize callback
let on_frame events callback = Event_kernel.on events.frame callback

module Private = struct
  let create () =
    { resize = Event_kernel.create (); frame = Event_kernel.create () }

  let emit_resize events event = Event_kernel.emit events.resize event
  let emit_frame events event = Event_kernel.emit events.frame event

  let clear events =
    Event_kernel.clear events.resize;
    Event_kernel.clear events.frame
end
