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
  mutable selection : Lib.Selection.t option;
  mutable selection_owner : Renderable.t option;
}

type resize_event = Render_context.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Render_context.frame_event = {
  frame_id : int64;
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
                          Ok
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
                              selection = None;
                              selection_owner = None;
                            })))))

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

let selection renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.selection
  else Error Error.Closed

let apply_selection renderer value =
  Option.iter
    (fun owner -> Renderable.Private.selection_changed owner value)
    renderer.selection_owner

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
  try Renderable.Private.process_mouse_event target event with
  | exception_value ->
      let owner_num =
        Option.value
          (Option.map Renderable.num (Renderable.mouse_current_target event))
          ~default:(Renderable.num target)
      in
      report_pointer_error renderer ~owner_num exception_value

let hit_target renderer ~x ~y =
  match Render_context.Private.hit_test renderer.context ~x ~y with
  | None -> None
  | Some id -> Renderable.Private.find_by_num renderer.root id

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
      let point = { Lib.Selection.x = float_of_int x; y = float_of_int y } in
      let value = Lib.Selection.create ~anchor:point ~focus:point in
      Lib.Selection.set_is_start value true;
      renderer.selection <- Some value;
      renderer.selection_owner <- Some owner;
      apply_selection renderer renderer.selection;
      ignore
        (Renderer_events.Private.emit_selection
           (Render_context.Private.events renderer.context) renderer.selection);
      Render_context.Private.request_render renderer.context

let update_selection renderer ~x ~y ~dragging =
  match renderer.selection with
  | None -> ()
  | Some value ->
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
      let target =
        hit_target renderer ~x:decoded.Lib.Mouse_decoder.x
          ~y:decoded.Lib.Mouse_decoder.y
      in
      let target_num = Option.map Renderable.num target in
      let same_element =
        match renderer.last_over_num, target_num with
        | None, None -> true
        | Some left, Some right -> Int.equal left right
        | None, Some _ | Some _, None -> false
      in
      renderer.last_over_num <- target_num;
      if
        (match source_kind with
        | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Drag -> true
        | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up
        | Lib.Mouse_decoder.Scroll -> false)
        && not same_element
      then begin
        Option.iter
          (fun old_target ->
            if
              (match renderer.captured with
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
                ~source:renderer.captured ~target:(Some new_target)
                ~is_dragging:false
            in
            send_pointer_event renderer new_target event)
          target;
        renderer.last_over <- target
      end;
      (match renderer.captured with
      | Some captured ->
          (match source_kind with
          | Lib.Mouse_decoder.Up ->
              if Int.equal decoded.Lib.Mouse_decoder.button 0 then
                update_selection renderer
                  ~x:decoded.Lib.Mouse_decoder.x
                  ~y:decoded.Lib.Mouse_decoder.y ~dragging:false;
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
              Option.iter
                (fun current_target ->
                  let drop =
                    make_pointer_event ~kind:Renderable.Drop ~decoded
                      ~source:(Some captured) ~target:(Some current_target)
                      ~is_dragging:false
                  in
                  send_pointer_event renderer current_target drop)
                target;
              renderer.captured <- None;
              renderer.last_over <- Some captured;
              renderer.last_over_num <- Some (Renderable.num captured);
              Render_context.Private.request_render renderer.context;
              Ok true
          | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Move
          | Lib.Mouse_decoder.Drag ->
              let is_drag =
                match source_kind with Lib.Mouse_decoder.Drag -> true | _ -> false
              in
              if is_drag && Int.equal decoded.Lib.Mouse_decoder.button 0 then
                update_selection renderer
                  ~x:decoded.Lib.Mouse_decoder.x
                  ~y:decoded.Lib.Mouse_decoder.y ~dragging:true;
              let event =
                make_pointer_event ~kind ~decoded ~source:None
                  ~target:(Some captured) ~is_dragging:true
              in
              send_pointer_event renderer captured event;
              Ok true
          | Lib.Mouse_decoder.Scroll -> Ok false)
      | None ->
          if Int.equal decoded.Lib.Mouse_decoder.button 0 then
            (match source_kind with
            | Lib.Mouse_decoder.Drag ->
                update_selection renderer
                  ~x:decoded.Lib.Mouse_decoder.x
                  ~y:decoded.Lib.Mouse_decoder.y ~dragging:true
            | Lib.Mouse_decoder.Up ->
                update_selection renderer
                  ~x:decoded.Lib.Mouse_decoder.x
                  ~y:decoded.Lib.Mouse_decoder.y ~dragging:false
            | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Move
            | Lib.Mouse_decoder.Scroll -> ());
          (match target with
          | None ->
              renderer.captured <- None;
              renderer.last_over <- None;
              renderer.last_over_num <- None;
              Ok true
      | Some target ->
              if Int.equal decoded.Lib.Mouse_decoder.button 0
                 && not decoded.Lib.Mouse_decoder.modifiers.ctrl
              then begin
                (match source_kind with
                | Lib.Mouse_decoder.Down ->
                    begin_selection renderer target
                      ~x:decoded.Lib.Mouse_decoder.x
                      ~y:decoded.Lib.Mouse_decoder.y
                | Lib.Mouse_decoder.Drag ->
                    update_selection renderer
                      ~x:decoded.Lib.Mouse_decoder.x
                      ~y:decoded.Lib.Mouse_decoder.y ~dragging:true
                | Lib.Mouse_decoder.Up ->
                    update_selection renderer
                      ~x:decoded.Lib.Mouse_decoder.x
                      ~y:decoded.Lib.Mouse_decoder.y ~dragging:false
                | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Scroll -> ());
              end;
              let event =
                make_pointer_event ~kind ~decoded ~source:None ~target:(Some target)
                  ~is_dragging:
                    (match source_kind with
                    | Lib.Mouse_decoder.Drag -> true
                    | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up
                    | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Scroll -> false)
              in
              if
                (match source_kind with
                | Lib.Mouse_decoder.Drag -> true
                | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up
                | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Scroll -> false)
                && Int.equal decoded.Lib.Mouse_decoder.button 0
              then
                renderer.captured <- Some target;
              send_pointer_event renderer target event;
              (match source_kind with
              | Lib.Mouse_decoder.Down
                when Int.equal decoded.Lib.Mouse_decoder.button 0 ->
                  Result.bind (focus_after_pointer_down renderer target event)
                    (fun () -> Ok true)
              | Lib.Mouse_decoder.Down | Lib.Mouse_decoder.Up
              | Lib.Mouse_decoder.Move | Lib.Mouse_decoder.Drag
              | Lib.Mouse_decoder.Scroll -> Ok true)))

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
      renderer.captured <- None;
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
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else if not (Float.is_finite delta_time) || Float.compare delta_time 0.0 < 0 then
    Error Error.Invalid_argument
  else begin
    Render_context.Private.clear_render_request renderer.context;
    let frame_id = Render_context.Private.advance_frame renderer.context in
    (match
       Renderable.Private.render_root renderer.root renderer.next_buffer
         ~delta_time
     with
    | Error error ->
        Render_context.Private.request_render renderer.context;
        Error error
    | Ok () ->
        (match Console.render renderer.console renderer.next_buffer with
        | Error error ->
            Render_context.Private.request_render renderer.context;
            Error error
        | Ok () ->
            (match apply_post_processes renderer ~delta_time with
            | Error error ->
                Render_context.Private.request_render renderer.context;
                Error error
            | Ok () ->
                let native_force = force || renderer.force_full_repaint in
                let result = Opentui_raw.Renderer.render renderer.raw ~force:native_force in
                match result with
                | Error error ->
                    Render_context.Private.request_render renderer.context;
                    Error (map_raw_error error)
                | Ok Opentui_raw.Renderer.Rendered ->
                    renderer.force_full_repaint <- false;
                    Render_context.Private.commit_hit_grid renderer.context;
                    recheck_hover_state renderer;
                    ignore
                      (Renderer_events.Private.emit_frame
                         (Render_context.Private.events renderer.context)
                         { Render_context.frame_id });
                    Ok Rendered
                | Ok Opentui_raw.Renderer.Skipped -> Ok Skipped
                | Ok Opentui_raw.Renderer.Failed -> Ok Failed)))
  end

let destroy renderer =
  if Render_context.Private.is_open renderer.context then begin
    renderer.captured <- None;
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
