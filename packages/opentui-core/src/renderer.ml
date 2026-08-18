type render_status = Rendered | Skipped | Failed

type post_process =
  Buffer.t -> delta_time:float -> (unit, Error.t) result

type post_process_id = int

type t = {
  raw : Opentui_raw.Renderer.t;
  context : Render_context.t;
  root : Renderable.t;
  children : Layout_children.t;
  current_buffer : Buffer.t;
  next_buffer : Buffer.t;
  console : Console.t;
  mutable post_processes : (post_process_id * post_process) list;
  mutable next_post_process_id : int;
  auto_focus : bool;
  mutable force_full_repaint : bool;
  palette_detector : Lib.Terminal_palette.t;
  theme_mode : Renderer_theme_mode.t;
  theme_query_requested : bool ref;
  mutable latest_pointer : (int * int) option;
  mutable last_pointer_modifiers : Lib.Mouse_decoder.modifiers;
  mutable last_over : Renderable.t option;
  mutable last_over_num : int option;
  mutable captured : Renderable.t option;
  mutable captured_destroy_subscription : Event_subscription.t option;
  mutable selection : Lib.Selection.t option;
  mutable selection_owner : Renderable.t option;
  mutable selection_containers : Renderable.t list;
  mutable selection_touched : Renderable.t list;
  mutable next_pre_render_id : int;
  mutable pre_render_drivers : pre_render_driver list;
  mutable before_destroy : teardown_attachment list;
  mutable live_leases : live_lease list;
  mutable destruction_started : bool;
}

and pre_render_driver = {
  renderer : t;
  id : int;
  callback : float -> unit;
  mutable active : bool;
}

and live_lease = {
  renderer : t;
  mutable active : bool;
}

and teardown_attachment = {
  renderer : t;
  callback : unit -> unit;
  mutable active : bool;
}

type resize_event = Render_context.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Render_context.frame_event = {
  frame_id : int64;
}

type render_error_event = Render_context.render_error_event = {
  error : Error.t;
  renderable_num : int option;
}

type capabilities_event = Render_context.capabilities_event
type palette_event = Render_context.palette_event
type theme_mode = Render_context.theme_mode
type theme_mode_event = Render_context.theme_mode_event
type selection_event = Render_context.selection_event
type focus_event = Render_context.focus_event
type theme_waiter = Renderer_theme_mode.waiter
type pixel_resolution = Render_context.pixel_resolution
type render_geometry = Render_context.render_geometry

type handler_source = Render_context.handler_source = Keyboard | Pointer
type handler_scope = Render_context.handler_scope = Global | Renderable
type handler_kind = Render_context.handler_kind = Keypress | Keyrelease | Paste | Mouse

type handler_error = Render_context.handler_error = {
  source : handler_source;
  scope : handler_scope;
  kind : handler_kind;
  owner_num : int option;
  exception_value : exn;
}

let map_raw_error error =
  match error with
  | Opentui_raw.Error.Closed -> Error.Closed
  | error -> Error.Native (Native.Error.Native error)

let terminal_capabilities_of_raw
    (raw : Opentui_raw.Capabilities.t) : Terminal_capabilities.t =
  let unicode =
    match raw.unicode with
    | Opentui_raw.Capabilities.Wcwidth -> Terminal_capabilities.Wcwidth
    | Opentui_raw.Capabilities.Unicode -> Terminal_capabilities.Unicode
  in
  let multiplexer =
    match raw.multiplexer with
    | Opentui_raw.Capabilities.No_multiplexer ->
        Terminal_capabilities.No_multiplexer
    | Opentui_raw.Capabilities.Tmux -> Terminal_capabilities.Tmux
    | Opentui_raw.Capabilities.Zellij -> Terminal_capabilities.Zellij
    | Opentui_raw.Capabilities.Screen -> Terminal_capabilities.Screen
    | Opentui_raw.Capabilities.Unknown_multiplexer ->
        Terminal_capabilities.Unknown_multiplexer
  in
  let image_protocol =
    match raw.image_protocol with
    | Opentui_raw.Capabilities.Auto -> Terminal_capabilities.Auto
    | Opentui_raw.Capabilities.Kitty -> Terminal_capabilities.Kitty
    | Opentui_raw.Capabilities.Sixel -> Terminal_capabilities.Sixel
    | Opentui_raw.Capabilities.Blocks -> Terminal_capabilities.Blocks
  in
  let osc52_support =
    match raw.osc52_support with
    | Opentui_raw.Capabilities.Unknown_osc52 ->
        Terminal_capabilities.Unknown_osc52
    | Opentui_raw.Capabilities.Supported -> Terminal_capabilities.Supported
    | Opentui_raw.Capabilities.Unsupported -> Terminal_capabilities.Unsupported
  in
  let terminal : Terminal_capabilities.terminal_info =
    {
      name = raw.terminal.name;
      version = raw.terminal.version;
      from_xtversion = raw.terminal.from_xtversion;
    }
  in
  {
    Terminal_capabilities.kitty_keyboard = raw.kitty_keyboard;
    kitty_graphics = raw.kitty_graphics;
    rgb = raw.rgb;
    ansi256 = raw.ansi256;
    unicode;
    sgr_pixels = raw.sgr_pixels;
    color_scheme_updates = raw.color_scheme_updates;
    explicit_width = raw.explicit_width;
    scaled_text = raw.scaled_text;
    sixel = raw.sixel;
    focus_tracking = raw.focus_tracking;
    sync = raw.sync;
    bracketed_paste = raw.bracketed_paste;
    hyperlinks = raw.hyperlinks;
    osc52 = raw.osc52;
    notifications = raw.notifications;
    explicit_cursor_positioning = raw.explicit_cursor_positioning;
    remote = raw.remote;
    multiplexer;
    image_protocol;
    terminal;
    osc52_support;
  }

type selection_intersection = {
  left : float;
  top : float;
  right : float;
  bottom : float;
}

let selection_intersection renderable (bounds : Lib.Selection.bounds) =
  let left =
    Float.max (Renderable.screen_x renderable) bounds.Lib.Selection.x
  in
  let top =
    Float.max (Renderable.screen_y renderable) bounds.Lib.Selection.y
  in
  let right =
    Float.min
      (Renderable.screen_x renderable +. Renderable.width renderable)
      (bounds.Lib.Selection.x +. bounds.Lib.Selection.width)
  in
  let bottom =
    Float.min
      (Renderable.screen_y renderable +. Renderable.height renderable)
      (bounds.Lib.Selection.y +. bounds.Lib.Selection.height)
  in
  if Float.compare left right < 0 && Float.compare top bottom < 0 then
    Some { left; top; right; bottom }
  else None

let integer_interval low high =
  int_of_float (Float.ceil low), int_of_float (Float.ceil high) - 1

let has_selection_point renderable ~left ~top ~right ~bottom =
  let first_x, last_x = integer_interval left right in
  let first_y, last_y = integer_interval top bottom in
  let found = ref false in
  if first_x <= last_x && first_y <= last_y then begin
    for y = first_y to last_y do
      for x = first_x to last_x do
        if
          not !found
          && Renderable.Private.should_start_selection renderable ~x ~y
        then found := true
      done
    done
  end;
  !found

let has_selectable_point renderable =
  let left = Renderable.screen_x renderable in
  let top = Renderable.screen_y renderable in
  let right = left +. Renderable.width renderable in
  let bottom = top +. Renderable.height renderable in
  has_selection_point renderable ~left ~top ~right ~bottom

let selection_snapshot renderable : Lib.Selection.selectable =
  {
    Lib.Selection.id = Renderable.num renderable;
    x = Renderable.screen_x renderable;
    y = Renderable.screen_y renderable;
    destroyed = Renderable.is_destroyed renderable;
    text = "";
  }

let selection_contains_renderable renderables renderable =
  List.exists (fun current -> current == renderable) renderables

let selection_parent renderer renderable =
  Option.value (Renderable.parent renderable) ~default:renderer.root

let rec renderable_within renderable container =
  if renderable == container then true
  else
    match Renderable.parent renderable with
    | None -> false
    | Some parent -> renderable_within parent container

let last_selection_container renderer =
  match List.rev renderer.selection_containers with
  | container :: _ when not (Renderable.is_destroyed container) -> container
  | _ -> renderer.root

let selection_container_index target containers =
  let rec find index = function
    | [] -> None
    | container :: rest ->
        if container == target then Some index else find (index + 1) rest
  in
  find 0 containers

let rec take_renderables count renderables =
  if Int.compare count 0 <= 0 then []
  else
    match renderables with
    | [] -> []
    | renderable :: rest -> renderable :: take_renderables (count - 1) rest

let update_selection_container renderer current_target =
  let current_container = last_selection_container renderer in
  let containers = renderer.selection_containers in
  match current_target with
  | Some target when renderable_within target current_container ->
      let candidate =
        match selection_container_index target containers with
        | Some _ -> Some target
        | None -> Renderable.parent target
      in
      (match candidate with
      | Some candidate ->
          (match selection_container_index candidate containers with
          | Some index when index < List.length containers - 1 ->
              renderer.selection_containers <- take_renderables (index + 1) containers
          | Some _ | None -> ())
      | None -> ())
  | Some _ | None ->
      let parent = selection_parent renderer current_container in
      if parent != current_container then
        renderer.selection_containers <- containers @ [ parent ]

let selection_container renderer =
  last_selection_container renderer

let collect_selection_renderables renderer value =
  let bounds = Lib.Selection.bounds value in
  let selected = ref [] in
  let touched = ref [] in
  let touched_nodes = ref [] in
  let rec visit container =
    List.iter
      (fun child ->
        if not (Renderable.is_destroyed child) && Renderable.visible child then
          match selection_intersection child bounds with
          | None -> ()
          | Some intersection ->
              let selected_here =
                has_selection_point child ~left:intersection.left
                  ~top:intersection.top ~right:intersection.right
                  ~bottom:intersection.bottom
              in
              let selectable = selected_here || has_selectable_point child in
              if selectable then begin
                Renderable.Private.selection_changed child (Some value);
                if not (Renderable.is_destroyed child) then begin
                  touched := selection_snapshot child :: !touched;
                  touched_nodes := child :: !touched_nodes;
                  if selected_here then selected := selection_snapshot child :: !selected
                end
              end;
              visit child)
      (Renderable.children container)
  in
  visit (selection_container renderer);
  List.rev !selected, List.rev !touched, List.rev !touched_nodes

let apply_selection renderer value =
  match value with
  | None ->
      List.iter
        (fun renderable ->
          if not (Renderable.is_destroyed renderable) then
            Renderable.Private.selection_changed renderable None)
        renderer.selection_touched;
      renderer.selection_touched <- []
  | Some value ->
      let selected, touched, touched_nodes =
        collect_selection_renderables renderer value
      in
      List.iter
        (fun renderable ->
          if
            not (selection_contains_renderable touched_nodes renderable)
            && not (Renderable.is_destroyed renderable)
          then Renderable.Private.selection_changed renderable None)
        renderer.selection_touched;
      Lib.Selection.update_selected_renderables value selected;
      Lib.Selection.update_touched_renderables value touched;
      renderer.selection_touched <- touched_nodes

let refresh_selection renderer =
  match renderer.selection with
  | None -> ()
  | Some value when not (Lib.Selection.is_active value) -> ()
  | Some value ->
      Option.iter
        (fun (x, y) ->
          Lib.Selection.set_focus value
            { Lib.Selection.x = float_of_int x; y = float_of_int y })
        renderer.latest_pointer;
      apply_selection renderer (Some value);
      ignore
        (Renderer_events.Private.emit_selection
           (Render_context.Private.events renderer.context) (Some value));
      Render_context.Private.request_render renderer.context

let create_with_clock_option ~clock ~width ~height =
  match Opentui_raw.Renderer.create ~width ~height with
  | Error error -> Error (map_raw_error error)
  | Ok raw ->
      (match Opentui_raw.Renderer.current_buffer raw with
      | Error error ->
          Opentui_raw.Renderer.close raw;
          Error (map_raw_error error)
      | Ok current_buffer ->
          (match Opentui_raw.Renderer.next_buffer raw with
          | Error error ->
              Opentui_raw.Renderer.close raw;
              Error (map_raw_error error)
          | Ok next_buffer ->
              (match Opentui_raw.Capabilities.snapshot raw with
              | Error error ->
                  Opentui_raw.Renderer.close raw;
                  Error (map_raw_error error)
              | Ok raw_capabilities ->
                  let capabilities =
                    terminal_capabilities_of_raw raw_capabilities
                  in
                  let context =
                    Render_context.Private.create
                      ~owner:(Render_context.Private.new_owner ()) ~width ~height
                      ~capabilities:(Some capabilities) ~clock
                      ~hit_grid:(Opentui_raw.Renderer.hit_grid raw)
                  in
                  (match Renderable.Private.create_root context with
                  | Error error ->
                      Render_context.Private.close context;
                      Opentui_raw.Renderer.close raw;
                      Error error
                  | Ok root ->
                      (match
                         Console.create ~width:(Int32.to_int width)
                           ~height:(Int32.to_int height) ()
                       with
                      | Error error ->
                          Renderable.destroy root;
                          Render_context.Private.close context;
                          Opentui_raw.Renderer.close raw;
                          Error error
                      | Ok console ->
                          let theme_query_requested = ref false in
                          let theme_mode =
                            match clock with
                            | Some clock ->
                                Renderer_theme_mode.create ~clock
                                  ~query:(fun () -> theme_query_requested := true) ()
                            | None ->
                                Renderer_theme_mode.create_without_clock
                                  ~query:(fun () -> theme_query_requested := true) ()
                          in
                          let renderer =
                            {
                              raw;
                              context;
                              root;
                              children = Layout_children.Private.of_renderable root;
                              current_buffer = Buffer_internal.of_raw current_buffer;
                              next_buffer = Buffer_internal.of_raw next_buffer;
                              console;
                              post_processes = [];
                              next_post_process_id = 1;
                              auto_focus = true;
                              force_full_repaint = false;
                              palette_detector = Lib.Terminal_palette.create ();
                              theme_mode;
                              theme_query_requested;
                              latest_pointer = None;
                              last_pointer_modifiers =
                                { Lib.Mouse_decoder.shift = false; alt = false; ctrl = false };
                              last_over = None;
                              last_over_num = None;
                              captured = None;
                              captured_destroy_subscription = None;
                              selection = None;
                              selection_owner = None;
                              selection_containers = [];
                              selection_touched = [];
                              next_pre_render_id = 1;
                              pre_render_drivers = [];
                              before_destroy = [];
                              live_leases = [];
                              destruction_started = false;
                            }
                          in
                          Render_context.Private.set_selection_update context
                            (fun () -> refresh_selection renderer);
                          Ok renderer)))))

let create_with_clock ~clock ~width ~height =
  create_with_clock_option ~clock:(Some clock) ~width ~height

let create ~width ~height = create_with_clock_option ~clock:None ~width ~height

let context renderer = renderer.context
let root renderer = renderer.root
let children renderer = renderer.children
let console renderer = renderer.console

let add_post_process renderer process =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else
    let id = renderer.next_post_process_id in
    renderer.next_post_process_id <- id + 1;
    renderer.post_processes <- renderer.post_processes @ [ id, process ];
    Ok id

let remove_post_process renderer id =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else begin
    renderer.post_processes <-
      List.filter
        (fun (current_id, _) -> not (Int.equal current_id id))
        renderer.post_processes;
    Ok ()
  end

let clear_post_processes renderer =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else begin
    renderer.post_processes <- [];
    Ok ()
  end

let apply_post_processes renderer ~delta_time =
  let result = ref (Ok ()) in
  List.iter
    (fun (_, process) ->
      match !result with
      | Error _ -> ()
      | Ok () -> result := process renderer.next_buffer ~delta_time)
    renderer.post_processes;
  !result

let reset_failed_frame renderer =
  Render_context.Private.abort_hit_grid renderer.context;
  ignore (Buffer.clear renderer.next_buffer ~background:Color.black);
  ignore (Buffer.clear_scissor_rects renderer.next_buffer);
  ignore (Buffer.clear_opacity renderer.next_buffer);
  renderer.force_full_repaint <- true

let report_render_error renderer error =
  ignore
    (Renderer_events.Private.emit_render_error
       (Render_context.Private.events renderer.context)
       { Renderer_events.error; renderable_num = None })

let failed_frame renderer error =
  reset_failed_frame renderer;
  Render_context.Private.request_render renderer.context;
  report_render_error renderer error;
  Error error

let width renderer = Render_context.width renderer.context
let height renderer = Render_context.height renderer.context
let terminal_width renderer = Render_context.terminal_width renderer.context
let terminal_height renderer = Render_context.terminal_height renderer.context
let frame_id renderer = Render_context.frame_id renderer.context
let capabilities renderer = Render_context.capabilities renderer.context
let width_method renderer = Render_context.width_method renderer.context
let palette renderer = Render_context.palette renderer.context
let theme_mode renderer = Render_context.theme_mode renderer.context
let pixel_resolution renderer = Render_context.pixel_resolution renderer.context
let render_geometry renderer = Render_context.render_geometry renderer.context
let has_pending_render renderer =
  Render_context.has_pending_render renderer.context

let current_buffer renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.current_buffer
  else Error Error.Closed

let next_buffer renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.next_buffer
  else Error Error.Closed

let request_render renderer = Render_context.request_render renderer.context
let request_live renderer = Render_context.request_live renderer.context
let drop_live renderer = Render_context.drop_live renderer.context
let live_request_count renderer = Render_context.live_request_count renderer.context

let attach_pre_render renderer callback =
  if renderer.destruction_started
     || not (Render_context.Private.is_open renderer.context)
  then Error Error.Closed
  else begin
    let id = renderer.next_pre_render_id in
    renderer.next_pre_render_id <- id + 1;
    let driver = { renderer; id; callback; active = true } in
    renderer.pre_render_drivers <- renderer.pre_render_drivers @ [ driver ];
    Ok driver
  end

let detach_pre_render driver =
  if driver.active then begin
    driver.active <- false;
    driver.renderer.pre_render_drivers <-
      List.filter
        (fun current -> current != driver)
        driver.renderer.pre_render_drivers
  end

let acquire_live_lease renderer =
  if renderer.destruction_started
     || not (Render_context.Private.is_open renderer.context)
  then Error Error.Closed
  else begin
    match Render_context.request_live renderer.context with
    | Error error -> Error error
    | Ok () ->
        let lease = { renderer; active = true } in
        renderer.live_leases <- lease :: renderer.live_leases;
        Ok lease
  end

let release_live_lease (lease : live_lease) =
  if lease.active then begin
    lease.active <- false;
    lease.renderer.live_leases <-
      List.filter
        (fun (current : live_lease) -> current != lease)
        lease.renderer.live_leases;
    ignore (Render_context.drop_live lease.renderer.context)
  end

let attach_before_destroy renderer callback =
  if renderer.destruction_started
     || not (Render_context.Private.is_open renderer.context)
  then Error Error.Closed
  else begin
    let attachment = { renderer; callback; active = true } in
    renderer.before_destroy <- renderer.before_destroy @ [ attachment ];
    Ok attachment
  end

let detach_before_destroy (attachment : teardown_attachment) =
  if attachment.active then begin
    attachment.active <- false;
    attachment.renderer.before_destroy <-
      List.filter
        (fun (current : teardown_attachment) -> current != attachment)
        attachment.renderer.before_destroy
  end

let close_before_destroy (attachment : teardown_attachment) =
  if attachment.active then begin
    detach_before_destroy attachment;
    attachment.callback ()
  end

let selection renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.selection
  else Error Error.Closed

let clear_selection renderer =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else begin
    let had_selection = Option.is_some renderer.selection in
    apply_selection renderer None;
    Option.iter
      (fun value -> Lib.Selection.set_active value false)
      renderer.selection;
    renderer.selection <- None;
    renderer.selection_owner <- None;
    renderer.selection_containers <- [];
    if had_selection then
      ignore
        (Renderer_events.Private.emit_selection
           (Render_context.Private.events renderer.context) None);
    Render_context.Private.request_render renderer.context;
    Ok ()
  end

let on_resize renderer callback =
  Render_context.on_resize renderer.context callback

let once_resize renderer callback =
  Render_context.once_resize renderer.context callback

let prepend_resize renderer callback =
  Render_context.prepend_resize renderer.context callback

let on_frame renderer callback = Render_context.on_frame renderer.context callback

let once_frame renderer callback =
  Render_context.once_frame renderer.context callback

let prepend_frame renderer callback =
  Render_context.prepend_frame renderer.context callback

let on_render_error renderer callback =
  Render_context.on_render_error renderer.context callback

let once_render_error renderer callback =
  Render_context.once_render_error renderer.context callback

let prepend_render_error renderer callback =
  Render_context.prepend_render_error renderer.context callback

let on_capabilities renderer callback =
  Render_context.on_capabilities renderer.context callback

let once_capabilities renderer callback =
  Render_context.once_capabilities renderer.context callback

let prepend_capabilities renderer callback =
  Render_context.prepend_capabilities renderer.context callback

let on_palette renderer callback = Render_context.on_palette renderer.context callback
let once_palette renderer callback = Render_context.once_palette renderer.context callback
let prepend_palette renderer callback = Render_context.prepend_palette renderer.context callback

let on_theme_mode renderer callback = Render_context.on_theme_mode renderer.context callback
let once_theme_mode renderer callback = Render_context.once_theme_mode renderer.context callback
let prepend_theme_mode renderer callback = Render_context.prepend_theme_mode renderer.context callback

let on_selection renderer callback = Render_context.on_selection renderer.context callback
let once_selection renderer callback = Render_context.once_selection renderer.context callback
let prepend_selection renderer callback = Render_context.prepend_selection renderer.context callback
let on_focus renderer callback = Render_context.on_focus renderer.context callback
let once_focus renderer callback = Render_context.once_focus renderer.context callback
let prepend_focus renderer callback = Render_context.prepend_focus renderer.context callback
let on_destroy renderer callback = Render_context.on_destroy renderer.context callback
let once_destroy renderer callback = Render_context.once_destroy renderer.context callback
let prepend_destroy renderer callback = Render_context.prepend_destroy renderer.context callback

let palette_query renderer ?(size = 16) ?(legacy_tmux = false) () =
  ignore renderer;
  let query = Lib.Terminal_palette.palette_query ~size () in
  if legacy_tmux then Lib.Terminal_palette.wrap_for_legacy_tmux query else query

let special_palette_query renderer ?(is_tmux = false) () =
  ignore renderer;
  Lib.Terminal_palette.special_query ~is_tmux ()

let osc_support_query renderer =
  ignore renderer;
  Lib.Terminal_palette.osc_support_query ()

let pixel_resolution_query renderer =
  ignore renderer;
  Lib.Terminal_capability_detection.pixel_resolution_query ()

let kitty_keyboard_flags ?(disambiguate = true) ?(alternate_keys = true)
    ?(events = false) ?(all_keys_as_escapes = false) ?(report_text = false) () =
  Lib.Kitty_keypress.build_flags ~disambiguate ~alternate_keys ~events
    ~all_keys_as_escapes ~report_text ()

let kitty_keyboard_push renderer ?(events = false) () =
  ignore renderer;
  Lib.Kitty_keypress.push_sequence
    ~flags:(kitty_keyboard_flags ~events ())

let kitty_keyboard_pop renderer =
  ignore renderer;
  Lib.Kitty_keypress.pop_sequence

let request_theme_query renderer =
  if Render_context.Private.is_open renderer.context then begin
    Renderer_theme_mode.request renderer.theme_mode;
    Ok ()
  end else Error Error.Closed

let wait_for_theme_mode renderer ~timeout_ms ~on_result =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else if Int.compare timeout_ms 0 < 0 then Error Error.Invalid_argument
  else if Int.compare timeout_ms 0 > 0 then
    (match Render_context.clock renderer.context with
    | Error error -> Error error
    | Ok None -> Error Error.Unsupported
    | Ok (Some _) ->
        Ok (Renderer_theme_mode.wait_for renderer.theme_mode ~timeout_ms ~on_result))
  else Ok (Renderer_theme_mode.wait_for renderer.theme_mode ~timeout_ms ~on_result)

let cancel_theme_waiter renderer waiter =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else begin
    Renderer_theme_mode.cancel_wait renderer.theme_mode waiter;
    Ok ()
  end

let theme_query renderer =
  if not (Render_context.Private.is_open renderer.context) then None
  else if !(renderer.theme_query_requested) then begin
    renderer.theme_query_requested := false;
    Some Renderer_theme_mode.query_sequence
  end else None

let palette_equal
    (left : Lib.Terminal_palette.normalized)
    (right : Lib.Terminal_palette.normalized) =
  let same_arrays left right =
    Int.equal (Array.length left) (Array.length right)
    && begin
      let equal = ref true in
      for index = 0 to Array.length left - 1 do
        if not (Lib.Rgba.equal left.(index) right.(index)) then equal := false
      done;
      !equal
    end
  in
  same_arrays left.palette right.palette
  && Lib.Rgba.equal left.default_foreground right.default_foreground
  && Lib.Rgba.equal left.default_background right.default_background

let feed_palette_response renderer response =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else begin
    Lib.Terminal_palette.feed renderer.palette_detector response;
    if not (Lib.Terminal_palette.complete renderer.palette_detector) then Ok false
    else
      let normalized =
        Lib.Terminal_palette.normalize
          (Some (Lib.Terminal_palette.colors renderer.palette_detector))
      in
      let previous = Render_context.palette renderer.context in
      Render_context.Private.set_palette renderer.context normalized;
      renderer.force_full_repaint <- true;
      Render_context.Private.request_render renderer.context;
      (match previous with
      | Ok (Some previous) when palette_equal previous normalized -> ()
      | Ok _ ->
          ignore
            (Renderer_events.Private.emit_palette
               (Render_context.Private.events renderer.context) normalized)
      | Error error ->
          ignore error;
          ignore
            (Renderer_events.Private.emit_palette
               (Render_context.Private.events renderer.context) normalized));
      Ok true
  end

let set_render_geometry renderer screen_mode ~footer_height =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else if footer_height < 0 then Error Error.Invalid_argument
  else begin
    Render_context.Private.set_render_geometry renderer.context screen_mode
      ~footer_height;
    match Render_context.render_geometry renderer.context with
    | Error error -> Error error
    | Ok geometry ->
        Result.bind
          (Renderable.Private.resize_root renderer.root
             ~width:(Int32.of_int geometry.render_width)
             ~height:(Int32.of_int geometry.render_height))
          (fun () ->
            renderer.force_full_repaint <- true;
            Render_context.Private.request_render renderer.context;
            Ok ())
  end

let on_handler_error renderer callback =
  Render_context.on_handler_error renderer.context callback

let once_handler_error renderer callback =
  Render_context.once_handler_error renderer.context callback

let prepend_handler_error renderer callback =
  Render_context.prepend_handler_error renderer.context callback

let on_keypress renderer callback =
  Render_context.on_keypress renderer.context callback

let once_keypress renderer callback =
  Render_context.once_keypress renderer.context callback

let prepend_keypress renderer callback =
  Render_context.prepend_keypress renderer.context callback

let on_keyrelease renderer callback =
  Render_context.on_keyrelease renderer.context callback

let once_keyrelease renderer callback =
  Render_context.once_keyrelease renderer.context callback

let prepend_keyrelease renderer callback =
  Render_context.prepend_keyrelease renderer.context callback

let on_paste renderer callback = Render_context.on_paste renderer.context callback

let once_paste renderer callback =
  Render_context.once_paste renderer.context callback

let prepend_paste renderer callback =
  Render_context.prepend_paste renderer.context callback

let same_renderable left right =
  match left, right with
  | None, None -> true
  | Some left, Some right -> left == right
  | None, Some _ | Some _, None -> false

let pointer_event_kind = function
  | Lib.Mouse_decoder.Down -> Renderable.Down
  | Lib.Mouse_decoder.Up -> Renderable.Up
  | Lib.Mouse_decoder.Move -> Renderable.Move
  | Lib.Mouse_decoder.Drag -> Renderable.Drag
  | Lib.Mouse_decoder.Scroll -> Renderable.Scroll

let make_pointer_event ~kind ~decoded ~source ~target ~is_dragging =
  Renderable.Private.make_mouse_event ~kind
    ~button:decoded.Lib.Mouse_decoder.button ~x:decoded.Lib.Mouse_decoder.x
    ~y:decoded.Lib.Mouse_decoder.y ~modifiers:decoded.Lib.Mouse_decoder.modifiers
    ~scroll:decoded.Lib.Mouse_decoder.scroll ~source ~target ~is_dragging

let report_pointer_error renderer ~owner_num exception_value =
  ignore
    (Renderer_events.Private.emit_handler_error
       (Render_context.Private.events renderer.context)
       {
         Render_context.source = Pointer;
         scope = Renderable;
         kind = Mouse;
         owner_num = Some owner_num;
         exception_value;
       })

let send_pointer_event renderer target event =
  if not (Renderable.is_destroyed target) then
    try Renderable.Private.process_mouse_event target event with
    | exception_value ->
        let owner_num =
          Option.value
            (Option.map Renderable.num (Renderable.mouse_current_target event))
            ~default:(Renderable.num target)
        in
        report_pointer_error renderer ~owner_num exception_value

let release_capture renderer =
  Option.iter Event_subscription.cancel renderer.captured_destroy_subscription;
  renderer.captured_destroy_subscription <- None;
  renderer.captured <- None;
  Render_context.Private.set_captured_num renderer.context None

let release_destroyed_capture renderer target =
  match renderer.captured with
  | Some captured when captured == target ->
      release_capture renderer;
      (match renderer.last_over with
      | Some last_over when last_over == target ->
          renderer.last_over <- None;
          renderer.last_over_num <- None
      | Some _ | None -> ())
  | Some _ | None -> ()

let capture renderer target =
  release_capture renderer;
  if not (Renderable.is_destroyed target) then
    match
      Renderable.once_destroyed target
        (fun () -> release_destroyed_capture renderer target)
    with
    | Error _ -> ()
    | Ok subscription ->
        renderer.captured <- Some target;
        renderer.captured_destroy_subscription <- Some subscription;
        Render_context.Private.set_captured_num renderer.context
          (Some (Renderable.num target))

let active_capture renderer =
  match renderer.captured with
  | Some captured when Renderable.is_destroyed captured ->
      release_destroyed_capture renderer captured;
      None
  | captured -> captured

let hit_target renderer ~x ~y =
  match Render_context.Private.hit_test renderer.context ~x ~y with
  | None -> None
  | Some id ->
      (match Renderable.Private.find_by_num renderer.root id with
      | Some target when not (Renderable.is_destroyed target) -> Some target
      | Some _ | None -> None)

let focused_target renderer =
  match Render_context.Private.focused_num renderer.context with
  | None -> None
        | Some id -> Renderable.Private.find_by_num renderer.root id

let rec selection_owner renderable ~x ~y =
  if Renderable.Private.should_start_selection renderable ~x ~y then Some renderable
  else
    match Renderable.parent renderable with
    | None -> None
    | Some parent -> selection_owner parent ~x ~y

let begin_selection renderer target ~x ~y =
  match selection_owner target ~x ~y with
  | None ->
      ignore (clear_selection renderer)
  | Some owner ->
      ignore (clear_selection renderer);
      let point = { Lib.Selection.x = float_of_int x; y = float_of_int y } in
      let value = Lib.Selection.create ~anchor:point ~focus:point in
      Lib.Selection.set_is_start value true;
      renderer.selection <- Some value;
      renderer.selection_owner <- Some owner;
      renderer.selection_containers <- [ selection_parent renderer owner ];
      apply_selection renderer renderer.selection;
      ignore
        (Renderer_events.Private.emit_selection
           (Render_context.Private.events renderer.context) renderer.selection);
      Render_context.Private.request_render renderer.context

let update_selection renderer ~current_target ~x ~y ~dragging =
  match renderer.selection with
  | None -> ()
  | Some value ->
      update_selection_container renderer current_target;
      Lib.Selection.set_focus value { Lib.Selection.x = float_of_int x; y = float_of_int y };
      Lib.Selection.set_is_start value false;
      Lib.Selection.set_dragging value dragging;
      apply_selection renderer renderer.selection;
      ignore
        (Renderer_events.Private.emit_selection
           (Render_context.Private.events renderer.context) renderer.selection);
      Render_context.Private.request_render renderer.context

let rec first_focusable renderable =
  if Renderable.focusable renderable then Some renderable
  else
    match Renderable.parent renderable with
    | None -> None
    | Some parent -> first_focusable parent

let focus_after_pointer_down renderer target event =
  if renderer.auto_focus
     && not (Renderable.mouse_default_prevented event) then
    match first_focusable target with
    | None -> Ok ()
    | Some focusable ->
        (match Renderable.focus focusable with
        | Error Error.Destroyed -> Ok ()
        | result -> result)
  else Ok ()

let recheck_hover_state renderer =
  match renderer.latest_pointer, renderer.captured with
  | Some (x, y), None ->
      let target = hit_target renderer ~x ~y in
      if not (same_renderable renderer.last_over target) then begin
        Option.iter
          (fun old_target ->
            if not (Renderable.is_destroyed old_target) then
              let event =
                let decoded =
                  {
                    Lib.Mouse_decoder.kind = Lib.Mouse_decoder.Move;
                    button = 0;
                    x;
                    y;
                    modifiers = renderer.last_pointer_modifiers;
                    scroll = None;
                          }

                in
                make_pointer_event ~kind:Renderable.Out ~decoded ~source:None
                  ~target:(Some old_target) ~is_dragging:false
              in
              send_pointer_event renderer old_target event)
          renderer.last_over;
        Option.iter
          (fun new_target ->
            let decoded =
              {
                Lib.Mouse_decoder.kind = Lib.Mouse_decoder.Move;
                button = 0;
                x;
                y;
                modifiers = renderer.last_pointer_modifiers;
                scroll = None;
              }
            in
            let event =
              make_pointer_event ~kind:Renderable.Over ~decoded ~source:None
                ~target:(Some new_target) ~is_dragging:false
            in
            send_pointer_event renderer new_target event)
          target;
        renderer.last_over <- target;
        renderer.last_over_num <- Option.map Renderable.num target
      end
  | None, _ | Some _, Some _ -> ()

let selection_is_dragging renderer =
  match renderer.selection with
  | Some selection -> Lib.Selection.is_dragging selection
  | None -> false

let pointer_event_is_dragging = function
  | Lib.Mouse_decoder.Drag -> true
  | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up | Lib.Mouse_decoder.Move
  | Lib.Mouse_decoder.Scroll -> false

let pointer_event_is_motion = function
  | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Drag -> true
  | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up | Lib.Mouse_decoder.Scroll -> false

let dispatch_pointer renderer (decoded : Lib.Mouse_decoder.event) =
  renderer.latest_pointer <-
    Some (decoded.Lib.Mouse_decoder.x, decoded.Lib.Mouse_decoder.y);
  renderer.last_pointer_modifiers <- decoded.Lib.Mouse_decoder.modifiers;
  match decoded.Lib.Mouse_decoder.kind with
  | Lib.Mouse_decoder.Scroll ->
      let target =
        match
          hit_target renderer ~x:decoded.Lib.Mouse_decoder.x
            ~y:decoded.Lib.Mouse_decoder.y
        with
        | Some target -> Some target
        | None -> focused_target renderer
      in
      Option.iter
        (fun target ->
          let event =
            make_pointer_event ~kind:Renderable.Scroll ~decoded ~source:None
              ~target:(Some target) ~is_dragging:false
          in
          send_pointer_event renderer target event)
        target;
      Ok true
  | ((Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up | Lib.Mouse_decoder.Move
     | Lib.Mouse_decoder.Drag) as source_kind) ->
      let kind = pointer_event_kind source_kind in
      let x = decoded.Lib.Mouse_decoder.x in
      let y = decoded.Lib.Mouse_decoder.y in
      let is_left_button = Int.equal decoded.Lib.Mouse_decoder.button 0 in
      let target =
        hit_target renderer ~x ~y
      in
      let target_num = Option.map Renderable.num target in
      let same_element =
        match renderer.last_over_num, target_num with
        | None, None -> true
        | Some left, Some right -> Int.equal left right
        | None, Some _ | Some _, None -> false
      in
      renderer.last_over_num <- target_num;
      let captured = active_capture renderer in
      let selection_route_target =
        match target with
        | Some _ -> target
        | None -> renderer.selection_owner
      in
      let dispatch_target () =
        match target with
        | None ->
            release_capture renderer;
            renderer.last_over <- None;
            renderer.last_over_num <- None;
            Ok None
        | Some target ->
            if pointer_event_is_dragging source_kind && is_left_button then
              capture renderer target
            else release_capture renderer;
            let event =
              make_pointer_event ~kind ~decoded ~source:None ~target:(Some target)
                ~is_dragging:(pointer_event_is_dragging source_kind)
            in
            send_pointer_event renderer target event;
            let focus_result =
              match source_kind with
              | Lib.Mouse_decoder.Down when is_left_button ->
                  focus_after_pointer_down renderer target event
              | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up
              | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Drag
              | Lib.Mouse_decoder.Scroll -> Ok ()
            in
            Result.map (fun () -> Some event) focus_result
      in
      let clear_selection_after_down event =
        match source_kind with
        | Lib.Mouse_decoder.Down when is_left_button ->
            let default_prevented =
              match event with
              | None -> false
              | Some event -> Renderable.mouse_default_prevented event
            in
            if not default_prevented then ignore (clear_selection renderer)
        | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up
        | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Drag
        | Lib.Mouse_decoder.Scroll -> ()
      in
      let dispatch_regular () =
        if pointer_event_is_motion source_kind && not same_element then begin
          Option.iter
            (fun old_target ->
              if
                (match captured with
                | Some captured -> captured != old_target
                | None -> true)
                && not (Renderable.is_destroyed old_target)
              then
                let event =
                  make_pointer_event ~kind:Renderable.Out ~decoded ~source:None
                    ~target:(Some old_target) ~is_dragging:false
                in
                send_pointer_event renderer old_target event)
            renderer.last_over;
          Option.iter
            (fun new_target ->
              let event =
                make_pointer_event ~kind:Renderable.Over ~decoded
                  ~source:captured ~target:(Some new_target)
                  ~is_dragging:false
              in
              send_pointer_event renderer new_target event)
            target;
          renderer.last_over <- target
        end;
        match captured with
        | Some captured ->
            (match source_kind with
            | Lib.Mouse_decoder.Up ->
                let drag_end =
                  make_pointer_event ~kind:Renderable.Drag_end ~decoded
                    ~source:None ~target:(Some captured) ~is_dragging:false
                in
                send_pointer_event renderer captured drag_end;
                let up =
                  make_pointer_event ~kind:Renderable.Up ~decoded
                    ~source:None ~target:(Some captured) ~is_dragging:false
                in
                send_pointer_event renderer captured up;
                if not (Renderable.is_destroyed captured) then
                  Option.iter
                    (fun current_target ->
                      let drop =
                        make_pointer_event ~kind:Renderable.Drop ~decoded
                          ~source:(Some captured) ~target:(Some current_target)
                          ~is_dragging:false
                      in
                      send_pointer_event renderer current_target drop)
                    target;
                release_capture renderer;
                if Renderable.is_destroyed captured then begin
                  (match renderer.last_over with
                  | Some last_over when last_over == captured ->
                      renderer.last_over <- None;
                      renderer.last_over_num <- None
                  | Some _ | None -> ())
                end else begin
                  renderer.last_over <- Some captured;
                  renderer.last_over_num <- Some (Renderable.num captured)
                end;
                Render_context.Private.request_render renderer.context;
                Result.bind (dispatch_target ()) (fun event ->
                    clear_selection_after_down event;
                    Ok true)
            | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Move
            | Lib.Mouse_decoder.Drag ->
                let event =
                  make_pointer_event ~kind ~decoded ~source:None
                    ~target:(Some captured)
                    ~is_dragging:(pointer_event_is_dragging source_kind)
                in
                send_pointer_event renderer captured event;
                Ok true
            | Lib.Mouse_decoder.Scroll -> Ok false)
        | None ->
            Result.bind (dispatch_target ()) (fun event ->
                clear_selection_after_down event;
                Ok true)
      in
      if
        match source_kind with
        | Lib.Mouse_decoder.Down ->
            is_left_button
            && not (selection_is_dragging renderer)
            && not decoded.Lib.Mouse_decoder.modifiers.ctrl
        | Lib.Mouse_decoder.Up | Lib.Mouse_decoder.Move
        | Lib.Mouse_decoder.Drag | Lib.Mouse_decoder.Scroll -> false
      then
        match target with
        | Some target ->
            (match selection_owner target ~x ~y with
            | Some _ ->
                begin_selection renderer target ~x ~y;
                let event =
                  make_pointer_event ~kind:Renderable.Down ~decoded ~source:None
                    ~target:(Some target) ~is_dragging:false
                in
                send_pointer_event renderer target event;
                Result.bind (focus_after_pointer_down renderer target event)
                  (fun () -> Ok true)
            | None -> dispatch_regular ())
        | None -> dispatch_regular ()
      else
        match source_kind with
        | Lib.Mouse_decoder.Drag when selection_is_dragging renderer ->
            update_selection renderer ~current_target:target ~x ~y ~dragging:true;
            Option.iter
              (fun target ->
                let event =
                  make_pointer_event ~kind:Renderable.Drag ~decoded ~source:None
                    ~target:(Some target) ~is_dragging:true
                in
                send_pointer_event renderer target event)
              selection_route_target;
            Ok true
        | Lib.Mouse_decoder.Up when selection_is_dragging renderer ->
            Option.iter
              (fun target ->
                let event =
                  make_pointer_event ~kind:Renderable.Up ~decoded ~source:None
                    ~target:(Some target) ~is_dragging:true
                in
                send_pointer_event renderer target event)
              selection_route_target;
            update_selection renderer ~current_target:target ~x ~y ~dragging:false;
            Ok true
        | Lib.Mouse_decoder.Down when
            is_left_button && decoded.Lib.Mouse_decoder.modifiers.ctrl ->
            (match renderer.selection with
            | Some selection ->
                Lib.Selection.set_dragging selection true;
                update_selection renderer ~current_target:target ~x ~y ~dragging:true;
                Ok true
            | None -> dispatch_regular ())
        | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up
        | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Drag
        | Lib.Mouse_decoder.Scroll -> dispatch_regular ()

let process_capability_response renderer bytes =
  let sequence = Bytes.to_string bytes in
  let theme_response = Renderer_theme_mode.handle_sequence renderer.theme_mode sequence in
  if theme_response.handled then begin
    Option.iter
      (fun mode ->
        Render_context.Private.set_theme_mode renderer.context mode;
        renderer.force_full_repaint <- true;
        Render_context.Private.request_render renderer.context)
      theme_response.changed_mode;
    Ok true
  end else if Lib.Terminal_capability_detection.is_pixel_resolution_response sequence then begin
    let resolution = Lib.Terminal_capability_detection.parse_pixel_resolution sequence in
    let to_context_resolution
        (value : Lib.Terminal_capability_detection.pixel_resolution) :
        Render_context.pixel_resolution =
      { Render_context.width = value.width; height = value.height }
    in
    let converted = Option.map to_context_resolution resolution in
    Render_context.Private.set_pixel_resolution renderer.context converted;
    Render_context.Private.request_render renderer.context;
    Ok true
  end else if
    not
      (Lib.Terminal_capability_detection.is_capability_response sequence)
  then Ok false
  else
    match Opentui_raw.Capabilities.process_response renderer.raw ~response:sequence with
    | Error error -> Error (map_raw_error error)
    | Ok () ->
        (match Opentui_raw.Capabilities.snapshot renderer.raw with
        | Error error -> Error (map_raw_error error)
        | Ok raw_capabilities ->
            let capabilities =
              terminal_capabilities_of_raw raw_capabilities
            in
            Render_context.Private.set_capabilities renderer.context capabilities;
            renderer.force_full_repaint <- true;
            Render_context.Private.request_render renderer.context;
            ignore
              (Renderer_events.Private.emit_capabilities
                 (Render_context.Private.events renderer.context) capabilities);
            Ok true)

let handle_input renderer input =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else
    match input with
    | Lib.Stdin_parser.Key { raw; key; modifiers; metadata } ->
        let handler = Render_context.Private.key_handler renderer.context in
        (match metadata.Lib.Key_decoder.event_type with
        | Lib.Key_decoder.Release ->
            Ok
              (Lib.Key_handler.process_keyrelease handler ~metadata ~raw ~key
                 ~modifiers ())
        | Lib.Key_decoder.Press | Lib.Key_decoder.Repeat ->
            Ok
              (Lib.Key_handler.process_key handler ~metadata ~raw ~key
                 ~modifiers ()))
    | Lib.Stdin_parser.Paste bytes ->
        Ok
          (Lib.Key_handler.process_paste
             (Render_context.Private.key_handler renderer.context) bytes)
    | Lib.Stdin_parser.Mouse { event; _ } -> dispatch_pointer renderer event
    | Lib.Stdin_parser.Response { bytes; _ } ->
        process_capability_response renderer bytes

let hit_test renderer ~x ~y =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else Ok (hit_target renderer ~x ~y)

let resize renderer ~width ~height =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else
    match Opentui_raw.Renderer.resize renderer.raw ~width ~height with
    | Error error -> Error (map_raw_error error)
    | Ok () ->
      release_capture renderer;
      ignore (clear_selection renderer);
        Render_context.Private.resize renderer.context ~width ~height;
        let geometry =
          match Render_context.render_geometry renderer.context with
          | Ok geometry -> geometry
          | Error _ ->
              Lib.Render_geometry.calculate Lib.Render_geometry.Alternate_screen
                ~terminal_width:(Int32.to_int width)
                ~terminal_height:(Int32.to_int height) ~footer_height:0
        in
        (match
           Renderable.Private.resize_root renderer.root
             ~width:(Int32.of_int geometry.render_width)
             ~height:(Int32.of_int geometry.render_height)
         with
        | Error error -> Error error
        | Ok () ->
            Result.bind
              (Console.resize renderer.console ~width:(Int32.to_int width)
                 ~height:(Int32.to_int height))
              (fun () ->
                ignore
                  (Renderer_events.Private.emit_resize
                     (Render_context.Private.events renderer.context)
                     { Render_context.width; height });
                Render_context.Private.request_render renderer.context;
                Ok ()))

let render ?(delta_time = 0.0) renderer ~force =
  if renderer.destruction_started
     || not (Render_context.Private.is_open renderer.context)
  then Error Error.Closed
  else if not (Float.is_finite delta_time) || Float.compare delta_time 0.0 < 0 then
    Error Error.Invalid_argument
  else begin
    let frame_finished = ref false in
    Fun.protect
      ~finally:(fun () ->
        if not !frame_finished then begin
          reset_failed_frame renderer;
          Render_context.Private.request_render renderer.context
        end)
      (fun () ->
        Render_context.Private.clear_render_request renderer.context;
        let frame_id = Render_context.Private.advance_frame renderer.context in
        List.iter
          (fun driver -> if driver.active then driver.callback delta_time)
          renderer.pre_render_drivers;
        let result =
          match
            Renderable.Private.render_root renderer.root renderer.next_buffer
              ~delta_time
          with
          | Error error -> failed_frame renderer error
          | Ok () ->
              (match apply_post_processes renderer ~delta_time with
              | Error error -> failed_frame renderer error
              | Ok () ->
                  (match Console.render renderer.console renderer.next_buffer with
                  | Error error -> failed_frame renderer error
                  | Ok () ->
                      let native_force = force || renderer.force_full_repaint in
                      let native_result =
                        Opentui_raw.Renderer.render renderer.raw ~force:native_force
                      in
                      match native_result with
                      | Error error -> failed_frame renderer (map_raw_error error)
                      | Ok Opentui_raw.Renderer.Rendered ->
                          renderer.force_full_repaint <- false;
                          if Render_context.Private.hit_grid_dirty renderer.context then
                            recheck_hover_state renderer;
                          ignore
                            (Renderer_events.Private.emit_frame
                               (Render_context.Private.events renderer.context)
                               { Render_context.frame_id });
                          Ok Rendered
                      | Ok Opentui_raw.Renderer.Skipped ->
                          Render_context.Private.abort_hit_grid renderer.context;
                          Render_context.Private.request_render renderer.context;
                          Ok Skipped
                      | Ok Opentui_raw.Renderer.Failed ->
                          Render_context.Private.abort_hit_grid renderer.context;
                          renderer.force_full_repaint <- true;
                          Render_context.Private.request_render renderer.context;
                          Ok Failed))
        in
        frame_finished := true;
        result)
  end

let destroy renderer =
  if not renderer.destruction_started
     && Render_context.Private.is_open renderer.context
  then begin
    renderer.destruction_started <- true;
    let attachments = renderer.before_destroy in
    renderer.before_destroy <- [];
    List.iter
      (fun (attachment : teardown_attachment) ->
        if attachment.active then begin
          attachment.active <- false;
          attachment.callback ()
        end)
      attachments;
    List.iter
      (fun (lease : live_lease) -> lease.active <- false)
      renderer.live_leases;
    renderer.live_leases <- [];
    renderer.pre_render_drivers <- [];
    release_capture renderer;
    ignore (clear_selection renderer);
    renderer.last_over <- None;
    renderer.last_over_num <- None;
    renderer.latest_pointer <- None;
    renderer.post_processes <- [];
    Renderer_theme_mode.dispose renderer.theme_mode;
    Console.destroy renderer.console;
    Renderable.destroy_recursively renderer.root;
    ignore
      (Renderer_events.Private.emit_destroy
         (Render_context.Private.events renderer.context) ());
    Render_context.Private.close renderer.context;
    Opentui_raw.Renderer.close renderer.raw
  end

let is_destroyed renderer = not (Render_context.Private.is_open renderer.context)
