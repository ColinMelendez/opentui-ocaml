type owner = unit ref

type resize_event = Renderer_events.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Renderer_events.frame_event = {
  frame_id : int64;
}

type t = {
  owner : owner;
  mutable width : int32;
  mutable height : int32;
  mutable frame_id : int64;
  mutable render_requested : bool;
  mutable closed : bool;
  events : Renderer_events.t;
}

let same_owner left right = left.owner == right.owner

let ensure_open context =
  if context.closed then Error Error.Closed else Ok ()

let width context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.width

let height context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.height

let frame_id context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.frame_id

let request_render context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () ->
      context.render_requested <- true;
      Ok ()

let has_pending_render context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.render_requested

let on_resize context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.on_resize context.events callback)

let once_resize context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.once_resize context.events callback)

let prepend_resize context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.prepend_resize context.events callback)

let on_frame context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.on_frame context.events callback)

module Private = struct
  let new_owner () = ref ()

  let create ~owner ~width ~height =
    {
      owner;
      width;
      height;
      frame_id = 0L;
      render_requested = false;
      closed = false;
      events = Renderer_events.Private.create ();
    }

  let resize context ~width ~height =
    context.width <- width;
    context.height <- height

  let advance_frame context =
    context.frame_id <- Int64.add context.frame_id 1L;
    context.frame_id

  let request_render context = context.render_requested <- true
  let has_pending_render context = context.render_requested

  let clear_render_request context = context.render_requested <- false

  let close context =
    if not context.closed then begin
      context.closed <- true;
      context.render_requested <- false;
      Renderer_events.Private.clear context.events
    end

  let is_open context = not context.closed
  let events context = context.events
end
