type owner = unit ref

type resize_event = Renderer_events.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Renderer_events.frame_event = {
  frame_id : int64;
}

type lifecycle_pass = {
  id : int;
  callback : unit -> unit;
}

type focused_renderable = {
  id : int;
  blur : unit -> unit;
}

type live_control = Idle | Auto_started | Explicit_started

type t = {
  owner : owner;
  mutable width : int32;
  mutable height : int32;
  mutable frame_id : int64;
  mutable layout_generation : int64;
  mutable render_list_revision : int64;
  mutable render_requested : bool;
  mutable live_control : live_control;
  mutable lifecycle_passes : lifecycle_pass list;
  mutable focused : focused_renderable option;
  mutable live_request_count : int;
  mutable hit_grid_count : int;
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

let layout_generation context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.layout_generation

let render_list_revision context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.render_list_revision

let focused_num context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () ->
      Ok (Option.map (fun focused -> focused.id) context.focused)

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
      layout_generation = 0L;
      render_list_revision = 0L;
      render_requested = false;
      live_control = Idle;
      lifecycle_passes = [];
      focused = None;
      live_request_count = 0;
      hit_grid_count = 0;
      closed = false;
      events = Renderer_events.Private.create ();
    }

  let resize context ~width ~height =
    context.width <- width;
    context.height <- height

  let advance_frame context =
    context.frame_id <- Int64.add context.frame_id 1L;
    context.frame_id

  let bump_layout_generation context =
    context.layout_generation <- Int64.add context.layout_generation 1L;
    context.layout_generation

  let bump_render_list_revision context =
    context.render_list_revision <-
      Int64.add context.render_list_revision 1L;
    context.render_list_revision

  let layout_generation (context : t) = context.layout_generation
  let render_list_revision (context : t) = context.render_list_revision

  let request_render context = context.render_requested <- true
  let has_pending_render context = context.render_requested

  let clear_render_request context = context.render_requested <- false

  let register_lifecycle_pass (context : t) ~id callback =
    let entry = { id; callback } in
    context.lifecycle_passes <-
      entry
      :: List.filter
           (fun (current : lifecycle_pass) -> not (Int.equal current.id id))
           context.lifecycle_passes

  let unregister_lifecycle_pass (context : t) ~id =
    context.lifecycle_passes <-
      List.filter
        (fun (current : lifecycle_pass) -> not (Int.equal current.id id))
        context.lifecycle_passes

  let lifecycle_passes (context : t) =
    List.rev_map
      (fun (entry : lifecycle_pass) -> entry.callback)
      context.lifecycle_passes

  let focus_renderable context ~id ~blur =
    match context.focused with
    | Some current when Int.equal current.id id -> ()
    | previous ->
        context.focused <- Some { id; blur };
        Option.iter (fun current -> current.blur ()) previous

  let blur_renderable context ~id =
    match context.focused with
    | Some current when Int.equal current.id id -> context.focused <- None
    | Some _ | None -> ()

  let focused_num context =
    Option.map (fun focused -> focused.id) context.focused

  let request_live context =
    context.live_request_count <- context.live_request_count + 1;
    context.render_requested <- true;
    (match context.live_control with
    | Idle -> context.live_control <- Auto_started
    | Auto_started | Explicit_started -> ())

  let drop_live context =
    context.live_request_count <- max 0 (context.live_request_count - 1);
    (match context.live_control with
    | Auto_started when Int.equal context.live_request_count 0 ->
        context.live_control <- Idle
    | Idle | Auto_started | Explicit_started -> ())

  let live_request_count context = context.live_request_count

  let mark_explicit_started context =
    context.live_control <- Explicit_started

  let live_is_auto_started context =
    match context.live_control with
    | Auto_started -> true
    | Idle | Explicit_started -> false

  let clear_hit_grid context = context.hit_grid_count <- 0

  let add_hit_grid context ~x:_ ~y:_ ~width:_ ~height:_ ~id:_ =
    context.hit_grid_count <- context.hit_grid_count + 1

  let hit_grid_count context = context.hit_grid_count

  let close context =
    if not context.closed then begin
      context.closed <- true;
      context.render_requested <- false;
      context.lifecycle_passes <- [];
      context.focused <- None;
      context.live_request_count <- 0;
      context.live_control <- Idle;
      context.hit_grid_count <- 0;
      Renderer_events.Private.clear context.events
    end

  let is_open context = not context.closed
  let events context = context.events
end
