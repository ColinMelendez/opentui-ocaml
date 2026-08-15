type owner = unit ref

type resize_event = Renderer_events.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Renderer_events.frame_event = {
  frame_id : int64;
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
  mutable capabilities : Terminal_capabilities.t option;
  mutable palette : Lib.Terminal_palette.normalized option;
  mutable theme_mode : theme_mode option;
  mutable pixel_resolution : pixel_resolution option;
  mutable render_geometry : render_geometry;
  mutable screen_mode : Lib.Render_geometry.screen_mode;
  mutable footer_height : int;
  mutable layout_generation : int64;
  mutable render_list_revision : int64;
  mutable render_requested : bool;
  mutable live_control : live_control;
  mutable lifecycle_passes : lifecycle_pass list;
  mutable focused : focused_renderable option;
  mutable live_request_count : int;
  mutable hit_grid_count : int;
  mutable hit_grid_width : int;
  mutable hit_grid_height : int;
  mutable current_hit_grid : int array;
  mutable next_hit_grid : int array;
  mutable closed : bool;
  events : Renderer_events.t;
  key_handler : Lib.Key_handler.t;
}

let same_owner left right = left.owner == right.owner

let ensure_open context =
  if context.closed then Error Error.Closed else Ok ()

let width context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.width

let terminal_width context = width context

let height context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.height

let terminal_height context = height context

let frame_id context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.frame_id

let capabilities context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.capabilities

let width_method context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () ->
      (match context.capabilities with
      | None -> Error Error.Unsupported
      | Some capabilities -> Ok capabilities.unicode)

let palette context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.palette

let theme_mode context =
  match ensure_open context with Error error -> Error error | Ok () -> Ok context.theme_mode

let pixel_resolution context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.pixel_resolution

let render_geometry context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok context.render_geometry

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

let once_frame context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.once_frame context.events callback)

let prepend_frame context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.prepend_frame context.events callback)

let on_capabilities context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.on_capabilities context.events callback)

let once_capabilities context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.once_capabilities context.events callback)

let prepend_capabilities context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.prepend_capabilities context.events callback)

let on_palette context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.on_palette context.events callback)

let once_palette context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.once_palette context.events callback)

let prepend_palette context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.prepend_palette context.events callback)

let on_theme_mode context callback =
  match ensure_open context with Error error -> Error error | Ok () -> Ok (Renderer_events.on_theme_mode context.events callback)

let once_theme_mode context callback =
  match ensure_open context with Error error -> Error error | Ok () -> Ok (Renderer_events.once_theme_mode context.events callback)

let prepend_theme_mode context callback =
  match ensure_open context with Error error -> Error error | Ok () -> Ok (Renderer_events.prepend_theme_mode context.events callback)

let on_selection context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.on_selection context.events callback)

let once_selection context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.once_selection context.events callback)

let prepend_selection context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.prepend_selection context.events callback)

let on_focus context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.on_focus context.events callback)

let once_focus context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.once_focus context.events callback)

let prepend_focus context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.prepend_focus context.events callback)

let on_destroy context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.on_destroy context.events callback)

let once_destroy context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.once_destroy context.events callback)

let prepend_destroy context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.prepend_destroy context.events callback)

let register_lifecycle_pass context ~id callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () ->
      let entry = { id; callback } in
      context.lifecycle_passes <-
        entry
        :: List.filter
             (fun (current : lifecycle_pass) -> not (Int.equal current.id id))
             context.lifecycle_passes;
      Ok ()

let unregister_lifecycle_pass context ~id =
  match ensure_open context with
  | Error error -> Error error
  | Ok () ->
      context.lifecycle_passes <-
        List.filter
          (fun (current : lifecycle_pass) -> not (Int.equal current.id id))
          context.lifecycle_passes;
      Ok ()

let lifecycle_pass_count context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (List.length context.lifecycle_passes)

let on_handler_error context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.on_handler_error context.events callback)

let once_handler_error context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.once_handler_error context.events callback)

let prepend_handler_error context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Renderer_events.prepend_handler_error context.events callback)

let on_keypress context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.on_keypress context.key_handler callback)

let once_keypress context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.once_keypress context.key_handler callback)

let prepend_keypress context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.prepend_keypress context.key_handler callback)

let on_keyrelease context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.on_keyrelease context.key_handler callback)

let once_keyrelease context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.once_keyrelease context.key_handler callback)

let prepend_keyrelease context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.prepend_keyrelease context.key_handler callback)

let on_paste context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.on_paste context.key_handler callback)

let once_paste context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.once_paste context.key_handler callback)

let prepend_paste context callback =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Lib.Key_handler.prepend_paste context.key_handler callback)

module Private = struct
  let new_owner () = ref ()

  let grid_size ~width ~height =
    let width = Int32.to_int width in
    let height = Int32.to_int height in
    width * height

  let create_hit_grid ~width ~height =
    Array.make (grid_size ~width ~height) 0

  let handler_error_of_key_error (error : Lib.Key_handler.handler_error) =
    let scope =
      match error.scope with
      | Lib.Key_handler.Global -> Global
      | Lib.Key_handler.Renderable -> Renderable
    in
    let kind =
      match error.kind with
      | Lib.Key_handler.Keypress -> Keypress
      | Lib.Key_handler.Keyrelease -> Keyrelease
      | Lib.Key_handler.Paste -> Paste
    in
    { source = Keyboard; scope; kind; owner_num = error.owner_num;
      exception_value = error.exception_value }

  let create ~owner ~width ~height ~capabilities =
    let events = Renderer_events.Private.create () in
    let key_handler =
      Lib.Key_handler.create ~on_error:(fun error ->
          ignore
            (Renderer_events.Private.emit_handler_error events
               (handler_error_of_key_error error))) ()
    in
    {
      owner;
      width;
      height;
      frame_id = 0L;
      capabilities;
      palette = None;
      theme_mode = None;
      pixel_resolution = None;
      render_geometry =
        Lib.Render_geometry.calculate Lib.Render_geometry.Alternate_screen
          ~terminal_width:(Int32.to_int width)
          ~terminal_height:(Int32.to_int height) ~footer_height:0;
      screen_mode = Lib.Render_geometry.Alternate_screen;
      footer_height = 0;
      layout_generation = 0L;
      render_list_revision = 0L;
      render_requested = false;
      live_control = Idle;
      lifecycle_passes = [];
      focused = None;
      live_request_count = 0;
      hit_grid_count = 0;
      hit_grid_width = Int32.to_int width;
      hit_grid_height = Int32.to_int height;
      current_hit_grid = create_hit_grid ~width ~height;
      next_hit_grid = create_hit_grid ~width ~height;
      closed = false;
      events;
      key_handler;
    }

  let set_capabilities context capabilities =
    context.capabilities <- Some capabilities

  let set_palette context palette = context.palette <- Some palette

  let set_theme_mode context mode =
    context.theme_mode <- Some mode;
    ignore (Renderer_events.Private.emit_theme_mode context.events mode)

  let set_pixel_resolution context resolution =
    context.pixel_resolution <- resolution

  let set_render_geometry context screen_mode ~footer_height =
    let geometry =
      Lib.Render_geometry.calculate screen_mode
        ~terminal_width:(Int32.to_int context.width)
        ~terminal_height:(Int32.to_int context.height) ~footer_height
    in
    context.screen_mode <- screen_mode;
    context.footer_height <- max 0 footer_height;
    context.render_geometry <- geometry

  let resize context ~width ~height =
    context.width <- width;
    context.height <- height;
    context.render_geometry <-
      Lib.Render_geometry.calculate context.screen_mode
        ~terminal_width:(Int32.to_int width)
        ~terminal_height:(Int32.to_int height)
        ~footer_height:context.footer_height;
    context.hit_grid_width <- Int32.to_int width;
    context.hit_grid_height <- Int32.to_int height;
    context.current_hit_grid <- create_hit_grid ~width ~height;
    context.next_hit_grid <- create_hit_grid ~width ~height;
    context.hit_grid_count <- 0

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
        Option.iter (fun current -> current.blur ()) previous;
        ignore
          (Renderer_events.Private.emit_focus context.events
             { Renderer_events.current = Some id;
               previous = Option.map (fun current -> current.id) previous })

  let blur_renderable context ~id =
    match context.focused with
    | Some current when Int.equal current.id id ->
        context.focused <- None;
        ignore
          (Renderer_events.Private.emit_focus context.events
             { Renderer_events.current = None; previous = Some id })
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

  let clear_hit_grid context =
    Array.fill context.next_hit_grid 0 (Array.length context.next_hit_grid) 0;
    context.hit_grid_count <- 0

  let add_hit_grid context ~x ~y ~width ~height ~id =
    context.hit_grid_count <- context.hit_grid_count + 1;
    let left = max 0 x in
    let top = max 0 y in
    let right = min context.hit_grid_width (max 0 (x + width)) in
    let bottom = min context.hit_grid_height (max 0 (y + height)) in
    if Int.compare left right < 0 && Int.compare top bottom < 0 then
      for row = top to bottom - 1 do
        let offset = (row * context.hit_grid_width) + left in
        Array.fill context.next_hit_grid offset (right - left) id
      done

  let hit_grid_count context = context.hit_grid_count

  let commit_hit_grid context =
    let previous = context.current_hit_grid in
    context.current_hit_grid <- context.next_hit_grid;
    context.next_hit_grid <- previous;
    Array.fill context.next_hit_grid 0 (Array.length context.next_hit_grid) 0

  let hit_test context ~x ~y =
    if Int.compare x 0 < 0 || Int.compare y 0 < 0
       || Int.compare x context.hit_grid_width >= 0
       || Int.compare y context.hit_grid_height >= 0
    then None
    else
      let id =
        context.current_hit_grid.((y * context.hit_grid_width) + x)
      in
      if Int.equal id 0 then None else Some id

  let close context =
    if not context.closed then begin
      context.closed <- true;
      context.render_requested <- false;
      context.capabilities <- None;
      context.palette <- None;
      context.theme_mode <- None;
      context.pixel_resolution <- None;
      context.lifecycle_passes <- [];
      context.focused <- None;
      context.live_request_count <- 0;
      context.live_control <- Idle;
      context.hit_grid_count <- 0;
      context.hit_grid_width <- 0;
      context.hit_grid_height <- 0;
      context.current_hit_grid <- [||];
      context.next_hit_grid <- [||];
      Renderer_events.Private.clear context.events;
      Lib.Key_handler.clear context.key_handler
    end

  let is_open context = not context.closed
  let events context = context.events
  let key_handler context = context.key_handler
end

let request_live context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Private.request_live context; Ok ()

let drop_live context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Private.drop_live context; Ok ()

let live_request_count context =
  match ensure_open context with
  | Error error -> Error error
  | Ok () -> Ok (Private.live_request_count context)
