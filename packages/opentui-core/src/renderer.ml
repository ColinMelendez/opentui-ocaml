module Output = struct
  type remote_mode = Auto | Local | Remote

  type sink = {
    write_frame : bytes list -> (unit, Error.t) result;
  }

  let sink ~write_frame = { write_frame }

  type target = Memory | Stdout | Sink of sink
end

type render_status = Rendered | Skipped | Failed

type external_output_mode = Passthrough | Capture_stdout

type scrollback_render_context = {
  width : int;
  width_method : Text_buffer.width_method;
  tail_column : int;
  render_context : Render_context.t;
}

type scrollback_snapshot = {
  root : Renderable.t;
  width : int;
  height : int;
  row_columns : int;
  start_on_new_line : bool;
  trailing_newline : bool;
}

type scrollback_writer = scrollback_render_context -> scrollback_snapshot

type cursor_style = Render_context.cursor_style =
  | Block
  | Line
  | Underline
  | Default

type mouse_pointer_style = Render_context.mouse_pointer_style =
  | Mouse_default
  | Mouse_pointer
  | Mouse_text
  | Mouse_crosshair
  | Mouse_move
  | Mouse_not_allowed

type cursor_style_options = Render_context.cursor_style_options = {
  style : cursor_style option;
  blinking : bool option;
  color : Color.t option;
  cursor : mouse_pointer_style option;
}

type cursor_state = {
  x : int32;
  y : int32;
  visible : bool;
  style : cursor_style;
  blinking : bool;
  color : Color.t;
}

type post_process =
  Buffer.t -> delta_time:float -> (unit, Error.t) result

type post_process_id = int

type t = {
  raw : Opentui_raw.Renderer.t;
  output_sink : Output.sink option;
  output_feed : Native_span_feed.t option;
  mutable output_failed : bool;
  context : Render_context.t;
  root : Renderable.t;
  children : Layout_children.t;
  current_buffer : Buffer.t;
  next_buffer : Buffer.t;
  mutable background_color : Color.t;
  console : Console.t;
  mutable post_processes : (post_process_id * post_process) list;
  mutable next_post_process_id : int;
  auto_focus : bool;
  mutable force_full_repaint : bool;
  palette_detector : Lib.Terminal_palette.t;
  theme_mode : Renderer_theme_mode.t;
  theme_query_requested : bool ref;
  mutable latest_pointer : (int * int) option;
  mutable use_mouse : bool;
  mutable mouse_protocol : (bool -> (unit, Error.t) result) option;
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
  mutable close_error : Error.t option;
  mutable screen_mode : Lib.Render_geometry.screen_mode;
  mutable footer_height : int;
  mutable external_output_mode : external_output_mode;
  mutable split_render_offset : int32;
  mutable split_tail_column : int;
  mutable split_transition_pending : bool;
  mutable split_transition_source_top_line : int option;
  mutable split_transition_source_height : int option;
  (* Snapshots queued for upcoming split-footer frames. Intentionally
     unbounded at enqueue time: writers can publish bursts faster than frames
     consume them (streamed transcripts, pasted history), and rejecting or
     dropping a snapshot would silently lose transcript content the caller
     already rendered. Pacing is a consumer concern instead: normal rendering
     commits at most [max_scrollback_commits_per_render] snapshots per frame
     and requests another render for the remainder, while mode transitions and
     close drain the queue fully before switching or tearing down. *)
  mutable scrollback_commits : scrollback_commit list;
}

and scrollback_commit = {
  snapshot : Owned_buffer.t;
  row_columns : int;
  row_widths : int array;
  start_on_new_line : bool;
  trailing_newline : bool;
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
  let text =
    match Renderable.Private.selected_text renderable with
    | Ok value -> value
    | Error _ -> ""
  in
  {
    Lib.Selection.id = Renderable.num renderable;
    x = Renderable.screen_x renderable;
    y = Renderable.screen_y renderable;
    destroyed = Renderable.is_destroyed renderable;
    text;
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

let raw_remote_mode = function
  | Output.Auto -> Opentui_raw.Renderer.Auto
  | Output.Local -> Opentui_raw.Renderer.Local
  | Output.Remote -> Opentui_raw.Renderer.Remote

let close_output_feed = function
  | None -> ()
  | Some feed -> ignore (Native_span_feed.close feed)

let create_raw_renderer ~output ~remote_mode ~width ~height =
  let create_native raw_output feed =
    match
      Opentui_raw.Renderer.create ~output:raw_output
        ~remote_mode:(raw_remote_mode remote_mode) ~width ~height ()
    with
    | Error error -> Error (map_raw_error error)
    | Ok raw -> Ok (raw, feed)
  in
  match output with
  | Output.Memory -> create_native Opentui_raw.Renderer.Memory None
  | Output.Stdout -> create_native Opentui_raw.Renderer.Stdout None
  | Output.Sink sink ->
      (match Native_span_feed.create () with
       | Error error -> Error error
       | Ok feed ->
           (match Native_span_feed.Private.raw feed with
            | Error error ->
                close_output_feed (Some feed);
                Error error
            | Ok raw_feed ->
                (match
                   create_native (Opentui_raw.Renderer.Feed raw_feed) (Some feed)
                 with
                 | Error error ->
                     close_output_feed (Some feed);
                     Error error
                 | Ok (raw, returned_feed) ->
                     Ok (raw, returned_feed))))

let create_with_clock_option ?remote_mode ~output ~clock ~width ~height () =
  let remote_mode =
    match remote_mode with
    | Some value -> value
    | None ->
        (match output with Output.Sink _ -> Output.Remote | _ -> Output.Auto)
  in
  match create_raw_renderer ~output ~remote_mode ~width ~height with
  | Error error -> Error error
  | Ok (raw, output_feed) ->
      (match Opentui_raw.Renderer.current_buffer raw with
      | Error error ->
          Opentui_raw.Renderer.close raw;
          close_output_feed output_feed;
          Error (map_raw_error error)
      | Ok current_buffer ->
          (match Opentui_raw.Renderer.next_buffer raw with
          | Error error ->
              Opentui_raw.Renderer.close raw;
              close_output_feed output_feed;
              Error (map_raw_error error)
          | Ok next_buffer ->
              (match Opentui_raw.Capabilities.snapshot raw with
              | Error error ->
                  Opentui_raw.Renderer.close raw;
                  close_output_feed output_feed;
                  Error (map_raw_error error)
              | Ok raw_capabilities ->
                  let capabilities =
                    terminal_capabilities_of_raw raw_capabilities
                  in
                  let context =
                    Render_context.Private.create
                      ~owner:(Render_context.Private.new_owner ()) ~width ~height
                      ~terminal_width:width ~terminal_height:height
                      ~capabilities:(Some capabilities) ~clock
                      ~hit_grid:(Opentui_raw.Renderer.hit_grid raw)
                      ~presentation:raw ~offscreen:false
                  in
                  (match Renderable.Private.create_root context with
                  | Error error ->
                      Render_context.Private.close context;
                      Opentui_raw.Renderer.close raw;
                      close_output_feed output_feed;
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
                          close_output_feed output_feed;
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
                          let output_sink =
                            match output with
                            | Output.Sink sink -> Some sink
                            | Output.Memory | Output.Stdout -> None
                          in
                          let renderer =
                            {
                              raw;
                              output_sink;
                              output_feed;
                              output_failed = false;
                              context;
                              root;
                              children = Layout_children.Private.of_renderable root;
                              current_buffer = Buffer_internal.of_raw current_buffer;
                              next_buffer = Buffer_internal.of_raw next_buffer;
                              background_color = Color.transparent;
                              console;
                              post_processes = [];
                              next_post_process_id = 1;
                              auto_focus = true;
                              force_full_repaint = false;
                              palette_detector = Lib.Terminal_palette.create ();
                              theme_mode;
                              theme_query_requested;
                              latest_pointer = None;
                              use_mouse = true;
                              mouse_protocol = None;
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
                              close_error = None;
                              screen_mode = Lib.Render_geometry.Alternate_screen;
                              footer_height = 0;
                              external_output_mode = Passthrough;
                              split_render_offset = 0l;
                              split_tail_column = 0;
                              split_transition_pending = false;
                              split_transition_source_top_line = None;
                              split_transition_source_height = None;
                              scrollback_commits = [];
                            }
                          in
                          Render_context.Private.set_selection_update context
                            (fun () -> refresh_selection renderer);
                          Ok renderer)))))

let create_with_clock ~output ?remote_mode ~clock ~width ~height () =
  create_with_clock_option ?remote_mode ~output ~clock:(Some clock) ~width ~height ()

let create ~output ?remote_mode ~width ~height () =
  create_with_clock_option ?remote_mode ~output ~clock:None ~width ~height ()

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
  ignore (Buffer.clear renderer.next_buffer ~background:renderer.background_color);
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

let output_failure = Error.Output "renderer output sink is unavailable"

let release_output_spans spans =
  let first_error = ref None in
  List.iter
    (fun span ->
      match Native_span_feed.Span.release span with
      | Ok () -> ()
      | Error error ->
          if Option.is_none !first_error then first_error := Some error)
    spans;
  !first_error

let flush_output renderer =
  match renderer.output_sink, renderer.output_feed with
  | None, _ -> Ok ()
  | Some _, None ->
      renderer.output_failed <- true;
      Error output_failure
  | Some sink, Some feed ->
      (match Native_span_feed.drain feed with
       | Error error ->
           renderer.output_failed <- true;
           Error (Error.Output (Error.message error))
       | Ok spans ->
           let chunks =
             List.map Native_span_feed.Span.bytes spans
           in
           let release_error = ref None in
           let sink_result =
             Fun.protect
               ~finally:(fun () ->
                 release_error := release_output_spans spans)
               (fun () -> sink.write_frame chunks)
           in
           (match sink_result, !release_error with
            | Error error, _ ->
                renderer.output_failed <- true;
                Error (Error.Output (Error.message error))
            | Ok (), Some error ->
                renderer.output_failed <- true;
                Error (Error.Output (Error.message error))
            | Ok (), None -> Ok ()))

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
let external_output_mode renderer =
  if Render_context.Private.is_open renderer.context then
    Ok renderer.external_output_mode
  else Error Error.Closed

let is_split_screen = function
  | Lib.Render_geometry.Split_footer -> true
  | Lib.Render_geometry.Alternate_screen | Lib.Render_geometry.Main_screen -> false

let is_capture_output = function
  | Capture_stdout -> true
  | Passthrough -> false

let same_external_output_mode left right =
  match left, right with
  | Passthrough, Passthrough | Capture_stdout, Capture_stdout -> true
  | Passthrough, Capture_stdout | Capture_stdout, Passthrough -> false

let has_scrollback_commits renderer =
  match renderer.scrollback_commits with [] -> false | _ :: _ -> true

(* Upper bound on queued snapshots consumed by one normal split-footer frame,
   matching the reference renderer's per-frame pacing. Transition and close
   flushes ignore this bound and drain the queue fully. *)
let max_scrollback_commits_per_render = 8

(* Splits the queue FIFO into the batch to commit now and the retained suffix
   that stays queued for later frames. *)
let take_scrollback_batch limit commits =
  match limit with
  | None -> (commits, [])
  | Some capacity ->
      let accepted = ref [] in
      let remaining = ref commits in
      let count = ref capacity in
      while Int.compare !count 0 > 0 do
        match !remaining with
        | [] -> count := 0
        | first :: rest ->
            accepted := first :: !accepted;
            remaining := rest;
            decr count
      done;
      (List.rev !accepted, !remaining)

let split_pinned_render_offset renderer (geometry : Lib.Render_geometry.t) =
  match renderer.screen_mode with
  | Lib.Render_geometry.Split_footer -> Int32.of_int geometry.render_offset
  | Lib.Render_geometry.Alternate_screen | Lib.Render_geometry.Main_screen -> 0l

let split_cursor_seed_rows renderer =
  let terminal_height =
    match Render_context.terminal_height renderer.context with
    | Ok height -> max 1 (Int32.to_int height)
    | Error _ -> 1
  in
  match Opentui_raw.Renderer.cursor_state renderer.raw with
  | Ok { y; _ } ->
      Int32.of_int
        (max 1 (min terminal_height (max 1 (Int32.to_int y))))
  | Error _ -> 1l

let set_split_native_state renderer geometry ~preserve_scrollback =
  let pinned_render_offset = split_pinned_render_offset renderer geometry in
  let reset_state () =
    if is_split_screen renderer.screen_mode
       && is_capture_output renderer.external_output_mode
       && preserve_scrollback
    then
      match
        Opentui_raw.Renderer.sync_split_scrollback renderer.raw
          ~pinned_render_offset
      with
      | Error error -> Error (map_raw_error error)
      | Ok offset -> Ok offset
    else
      let seed_rows =
        if is_split_screen renderer.screen_mode
           && is_capture_output renderer.external_output_mode
        then split_cursor_seed_rows renderer
        else 0l
      in
      (match
         Opentui_raw.Renderer.reset_split_scrollback renderer.raw ~seed_rows
           ~pinned_render_offset
       with
       | Error error -> Error (map_raw_error error)
       | Ok offset -> Ok offset)
  in
  Result.bind (reset_state ()) (fun native_offset ->
      let render_offset =
        if is_split_screen renderer.screen_mode
           && not (is_capture_output renderer.external_output_mode)
        then pinned_render_offset
        else native_offset
      in
      match
        Opentui_raw.Renderer.set_render_offset renderer.raw
          ~offset:render_offset
      with
      | Error error -> Error (map_raw_error error)
      | Ok () ->
          renderer.split_render_offset <- render_offset;
          if not preserve_scrollback then renderer.split_tail_column <- 0;
          if not (is_split_screen renderer.screen_mode) then
            renderer.split_tail_column <- 0;
          Ok ())

let advance_split_tail_column ~tail_column ~columns ~width =
  if Int.compare columns 0 <= 0 || Int.compare width 0 <= 0 then
    max 0 tail_column
  else
    let tail = ref (max 0 (min tail_column width)) in
    let remaining = ref columns in
    while Int.compare !remaining 0 > 0 do
      if Int.compare !tail width >= 0 then tail := 0;
      let available = width - !tail in
      let step = min !remaining available in
      tail := !tail + step;
      remaining := !remaining - step;
      if Int.compare !remaining 0 > 0 && Int.compare !tail width >= 0 then
        tail := 0
    done;
    !tail

let snapshot_row_widths buffer ~width ~height ~row_columns =
  match Opentui_raw.Optimized_buffer.snapshot (Owned_buffer.raw buffer) with
  | Error error -> Error (map_raw_error error)
  | Ok (characters, _, _, _) ->
      let continuation_mask = Int32.of_int (-1073741824) in
      let widths = Array.make height 0 in
      let limit = max 0 (min row_columns width) in
      for row = 0 to height - 1 do
        let x = ref limit in
        let found_character = ref false in
        while Int.compare !x 0 > 0 && not !found_character do
          let character = characters.((row * width) + !x - 1) in
          if
            Int32.equal character 0l
            || Int32.equal (Int32.logand character continuation_mask)
                 continuation_mask
          then decr x
          else found_character := true
        done;
        widths.(row) <- !x
      done;
      Ok widths

let split_tail_after_commit ~tail_column ~width commit =
  let tail = ref tail_column in
  if commit.start_on_new_line && Int.compare !tail 0 > 0 then tail := 0;
  let row_count = Array.length commit.row_widths in
  for row = 0 to row_count - 1 do
    tail :=
      advance_split_tail_column ~tail_column:!tail
        ~columns:commit.row_widths.(row) ~width;
    if Int.compare row (row_count - 1) < 0 || commit.trailing_newline then
      tail := 0
  done;
  !tail

let projected_split_tail_column renderer (geometry : Lib.Render_geometry.t) =
  let width = max 1 geometry.render_width in
  let tail = ref renderer.split_tail_column in
  List.iter
    (fun commit ->
      tail := split_tail_after_commit ~tail_column:!tail ~width commit)
    renderer.scrollback_commits;
  !tail

let update_split_tail_column renderer (geometry : Lib.Render_geometry.t) commits =
  let width = max 1 geometry.render_width in
  List.iter
    (fun commit ->
      renderer.split_tail_column <-
        split_tail_after_commit ~tail_column:renderer.split_tail_column ~width
          commit)
    commits

let current_split_pinned_render_offset renderer =
  match Render_context.render_geometry renderer.context with
  | Ok geometry -> split_pinned_render_offset renderer geometry
  | Error _ -> 0l

let commit_scrollback_commits renderer ~force ~limit =
  let repaint_without_commits () =
    match
      Opentui_raw.Renderer.repaint_split_footer renderer.raw
        ~pinned_render_offset:(current_split_pinned_render_offset renderer)
        ~force
    with
    | Error error -> Error (map_raw_error error)
    | Ok (offset, status) ->
        renderer.split_render_offset <- offset;
        (match status with
        | Opentui_raw.Renderer.Rendered ->
            renderer.split_transition_pending <- false;
            renderer.split_transition_source_top_line <- None;
            renderer.split_transition_source_height <- None
        | Opentui_raw.Renderer.Skipped
        | Opentui_raw.Renderer.Failed -> ());
        Ok status
  in
  match renderer.scrollback_commits with
  | [] -> repaint_without_commits ()
  | queued ->
      (* Preflight geometry so bookkeeping cannot fail after native commit. *)
      (match Render_context.render_geometry renderer.context with
      | Error error -> Error error
      | Ok geometry ->
      let pinned_render_offset = split_pinned_render_offset renderer geometry in
      let commits, retained_commits = take_scrollback_batch limit queued in
      let last_index = List.length commits - 1 in
      let next_offset = ref renderer.split_render_offset in
      let outcome :
          (Opentui_raw.Renderer.render_status option, Error.t) result ref =
        ref (Ok None)
      in
      List.iteri
        (fun index commit ->
          match !outcome with
          | Error _ | Ok (Some _) -> ()
          | Ok None ->
              let begin_frame = Int.equal index 0 in
              let finalize_frame = Int.equal index last_index in
              (match
                 Opentui_raw.Renderer.commit_split_footer_snapshot renderer.raw
                   ~snapshot:(Owned_buffer.raw commit.snapshot)
                   ~row_columns:(Int32.of_int commit.row_columns)
                   ~start_on_new_line:commit.start_on_new_line
                   ~trailing_newline:commit.trailing_newline
                   ~pinned_render_offset
                   ~force:(force && finalize_frame) ~begin_frame ~finalize_frame
               with
               | Error error -> outcome := Error (map_raw_error error)
               | Ok (offset, Opentui_raw.Renderer.Rendered) ->
                   next_offset := offset
               | Ok (_, (Opentui_raw.Renderer.Skipped as status))
               | Ok (_, (Opentui_raw.Renderer.Failed as status)) ->
                   outcome := Ok (Some status)))
        commits;
      (match !outcome with
      | Error error ->
          (* Native batching restores the complete batch on failure. Keep every
             queued snapshot so the next frame retries the same FIFO payload. *)
          renderer.force_full_repaint <- true;
          Render_context.Private.request_render renderer.context;
          Error error
      | Ok (Some Opentui_raw.Renderer.Skipped) ->
          Render_context.Private.request_render renderer.context;
          Ok Opentui_raw.Renderer.Skipped
      | Ok (Some Opentui_raw.Renderer.Failed) ->
          renderer.force_full_repaint <- true;
          Render_context.Private.request_render renderer.context;
          Ok Opentui_raw.Renderer.Failed
      | Ok (Some Opentui_raw.Renderer.Rendered) ->
          Error Error.Unsupported
      | Ok None ->
          renderer.split_render_offset <- !next_offset;
          renderer.split_transition_pending <- false;
          renderer.split_transition_source_top_line <- None;
          renderer.split_transition_source_height <- None;
          update_split_tail_column renderer geometry commits;
          List.iter (fun commit -> Owned_buffer.close commit.snapshot) commits;
          renderer.scrollback_commits <- retained_commits;
          (match retained_commits with
          | [] -> ()
          | _ :: _ ->
              (* Paced consumption: leave a request pending so the
                 scheduler commits the retained suffix next frame. *)
              Render_context.Private.request_render renderer.context);
          Ok Opentui_raw.Renderer.Rendered))

let flush_scrollback_for_transition renderer =
  if not (has_scrollback_commits renderer) then Ok ()
  else
    match commit_scrollback_commits renderer ~force:true ~limit:None with
    | Error error -> Error error
    | Ok Opentui_raw.Renderer.Rendered -> Ok ()
    | Ok Opentui_raw.Renderer.Skipped
    | Ok Opentui_raw.Renderer.Failed -> Error Error.Unsupported

let schedule_split_footer_transition renderer ~previous_mode ~previous_capture
    ~previous_geometry ~previous_render_offset
    ~next_geometry:(next_geometry : Lib.Render_geometry.t) =
  let clear_pending () =
    match
      Opentui_raw.Renderer.clear_pending_split_footer_transition renderer.raw
    with
    | Ok () ->
        renderer.split_transition_pending <- false;
        renderer.split_transition_source_top_line <- None;
        renderer.split_transition_source_height <- None;
        Ok ()
    | Error error -> Error (map_raw_error error)
  in
  match previous_geometry with
  | None -> clear_pending ()
  | Some (source_geometry : Lib.Render_geometry.t) ->
      let same_split_capture_transition =
        is_split_screen previous_mode
        && is_split_screen renderer.screen_mode
        && is_capture_output renderer.external_output_mode
        && Int.compare source_geometry.render_height 0 > 0
        && Int.compare next_geometry.render_height 0 > 0
      in
      if not same_split_capture_transition then clear_pending ()
      else
        let source_top_line = max 1 (Int32.to_int previous_render_offset + 1) in
        let target_top_line =
          max 1 (Int32.to_int renderer.split_render_offset + 1)
        in
        let source_height = source_geometry.render_height in
        let target_height = next_geometry.render_height in
        let scroll_lines =
          if previous_capture then max 0 (source_top_line - target_top_line)
          else 0
        in
        let mode =
          if Int.compare scroll_lines 0 > 0 then
            Opentui_raw.Renderer.Viewport_scroll
          else
            Opentui_raw.Renderer.Clear_stale_rows
        in
        if
          Int.equal source_top_line target_top_line
          && Int.equal source_height target_height
          && Int.equal scroll_lines 0
        then clear_pending ()
        else
          match
            Opentui_raw.Renderer.set_pending_split_footer_transition renderer.raw
              mode ~source_top_line:(Int32.of_int source_top_line)
              ~source_height:(Int32.of_int source_height)
              ~target_top_line:(Int32.of_int target_top_line)
              ~target_height:(Int32.of_int target_height)
              ~scroll_lines:(Int32.of_int scroll_lines)
          with
          | Ok () ->
              renderer.split_transition_pending <- true;
              renderer.split_transition_source_top_line <- Some source_top_line;
              renderer.split_transition_source_height <- Some source_height;
              Ok ()
          | Error error -> Error (map_raw_error error)

let set_external_output_mode renderer mode =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else if is_capture_output mode && not (is_split_screen renderer.screen_mode) then
    Error Error.Invalid_argument
  else if same_external_output_mode mode renderer.external_output_mode then Ok ()
  else begin
    let previous_mode = renderer.external_output_mode in
    let previous_geometry =
      match Render_context.render_geometry renderer.context with
      | Ok geometry -> Some geometry
      | Error _ -> None
    in
    (match
       flush_scrollback_for_transition renderer
     with
    | Error error -> Error error
    | Ok () ->
        let previous_render_offset = renderer.split_render_offset in
        renderer.external_output_mode <- mode;
        (match Render_context.render_geometry renderer.context with
        | Error error ->
            renderer.external_output_mode <- previous_mode;
            Error error
        | Ok geometry ->
            (match
               set_split_native_state renderer geometry ~preserve_scrollback:false
             with
            | Error error ->
                renderer.external_output_mode <- previous_mode;
                Error error
            | Ok () ->
                (match
                   schedule_split_footer_transition renderer
                     ~previous_mode:renderer.screen_mode
                     ~previous_capture:(is_capture_output previous_mode)
                     ~previous_geometry ~previous_render_offset
                     ~next_geometry:geometry
                 with
                | Error error ->
                    renderer.external_output_mode <- previous_mode;
                    Error error
                | Ok () ->
                    renderer.force_full_repaint <- true;
                    Render_context.Private.request_render renderer.context;
                    Ok ()))))
  end

let has_pending_render renderer =
  Render_context.has_pending_render renderer.context

let current_buffer renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.current_buffer
  else Error Error.Closed

let next_buffer renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.next_buffer
  else Error Error.Closed

let background_color renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.background_color
  else Error Error.Closed

let set_background_color renderer ~color =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else
    match
      Opentui_raw.Renderer.set_background_color renderer.raw
        ~color:(Color.Private.to_raw color)
    with
    | Error error -> Error (map_raw_error error)
    | Ok () ->
        (match Buffer.clear renderer.next_buffer ~background:color with
        | Error error -> Error error
        | Ok () ->
            renderer.background_color <- color;
            Render_context.Private.request_render renderer.context;
            Ok ())

let set_cursor_position renderer ~x ~y ?(visible = true) () =
  Render_context.set_cursor_position renderer.context ~x ~y ~visible ()

let set_cursor_color renderer ~color =
  Render_context.set_cursor_color renderer.context ~color

let set_cursor_style renderer (options : cursor_style_options) =
  Render_context.set_cursor_style renderer.context options

let set_mouse_pointer renderer pointer =
  Render_context.set_mouse_pointer renderer.context pointer

let cursor_state renderer =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else
    match Opentui_raw.Renderer.cursor_state renderer.raw with
    | Error error -> Error (map_raw_error error)
    | Ok { x; y; visible; style; blinking; color } ->
        Ok { x; y; visible; style; blinking; color = Color.Private.of_raw color }

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

let clear_mouse_dispatch_state renderer =
  Option.iter Event_subscription.cancel renderer.captured_destroy_subscription;
  renderer.captured_destroy_subscription <- None;
  renderer.captured <- None;
  renderer.latest_pointer <- None;
  renderer.last_over <- None;
  renderer.last_over_num <- None;
  renderer.last_pointer_modifiers <-
    { Lib.Mouse_decoder.shift = false; alt = false; ctrl = false };
  Render_context.Private.set_captured_num renderer.context None;
  ignore (clear_selection renderer)

let use_mouse renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.use_mouse
  else Error Error.Closed

let set_mouse_protocol renderer callback =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else begin
    renderer.mouse_protocol <- Some callback;
    Ok ()
  end

let set_use_mouse renderer enabled =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else if Bool.equal renderer.use_mouse enabled then Ok ()
  else
    let transition () =
      renderer.use_mouse <- enabled;
      if enabled then Render_context.Private.request_render renderer.context
      else clear_mouse_dispatch_state renderer
    in
    match renderer.mouse_protocol with
    | Some callback -> Result.bind (callback enabled) (fun () -> transition (); Ok ())
    | None -> transition (); Ok ()

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
  else if Int.compare footer_height 0 < 0 then Error Error.Invalid_argument
  else
    let previous_mode = renderer.screen_mode in
    let previous_capture = is_capture_output renderer.external_output_mode in
    let previous_geometry =
      match Render_context.render_geometry renderer.context with
      | Ok geometry -> Some geometry
      | Error _ -> None
    in
    let flush_result =
      flush_scrollback_for_transition renderer
    in
    Result.bind flush_result (fun () ->
        let previous_render_offset = renderer.split_render_offset in
        match Render_context.terminal_width renderer.context,
          Render_context.terminal_height renderer.context with
        | Error error, _ | _, Error error -> Error error
        | Ok terminal_width, Ok terminal_height ->
            let geometry =
              Lib.Render_geometry.calculate screen_mode
                ~terminal_width:(Int32.to_int terminal_width)
                ~terminal_height:(Int32.to_int terminal_height) ~footer_height
            in
            let native_width = Int32.of_int (max 1 geometry.render_width) in
            let native_height = Int32.of_int (max 1 geometry.render_height) in
            let preserve_scrollback =
              is_split_screen renderer.screen_mode
              && is_capture_output renderer.external_output_mode
            in
            Result.bind
              (match
                 Opentui_raw.Renderer.resize renderer.raw ~width:native_width
                   ~height:native_height
               with
              | Error error -> Error (map_raw_error error)
              | Ok () -> Ok ())
              (fun () ->
                Render_context.Private.set_render_geometry renderer.context
                  screen_mode ~footer_height;
                renderer.screen_mode <- screen_mode;
                renderer.footer_height <- footer_height;
                if not (is_split_screen screen_mode) then
                  renderer.external_output_mode <- Passthrough;
                Result.bind
                  (Renderable.Private.resize_root renderer.root
                     ~width:(Int32.of_int geometry.render_width)
                     ~height:(Int32.of_int geometry.render_height))
                  (fun () ->
                    Result.bind
                      (Console.resize renderer.console
                         ~width:(max 1 geometry.render_width)
                         ~height:(max 1 geometry.render_height))
                      (fun () ->
                        Result.bind
                          (set_split_native_state renderer geometry
                             ~preserve_scrollback)
                          (fun () ->
                            Result.bind
                              (schedule_split_footer_transition renderer
                                 ~previous_mode ~previous_capture
                                 ~previous_geometry ~previous_render_offset
                                 ~next_geometry:geometry)
                              (fun () ->
                                renderer.force_full_repaint <- true;
                                Render_context.Private.request_render
                                  renderer.context;
                                Ok ()))))))

let raw_render_status = function
  | Rendered -> Opentui_raw.Renderer.Rendered
  | Skipped -> Opentui_raw.Renderer.Skipped
  | Failed -> Opentui_raw.Renderer.Failed

let core_render_status = function
  | Opentui_raw.Renderer.Rendered -> Rendered
  | Opentui_raw.Renderer.Skipped -> Skipped
  | Opentui_raw.Renderer.Failed -> Failed

let commit_scrollback_frames renderer ~force =
  Result.map core_render_status
    (commit_scrollback_commits renderer ~force
       ~limit:(Some max_scrollback_commits_per_render))

let text_width_method = function
  | Terminal_capabilities.Wcwidth -> Text_buffer.Wcwidth
  | Terminal_capabilities.Unicode -> Text_buffer.Unicode

let owned_buffer_as_buffer buffer =
  Buffer_internal.of_raw
    (Opentui_raw.Buffer.Private.of_optimized
       (Opentui_raw.Optimized_buffer.Private.handle (Owned_buffer.raw buffer))
       (Opentui_raw.Optimized_buffer.Private.owner (Owned_buffer.raw buffer)))

let write_to_scrollback renderer writer =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else
    match renderer.screen_mode, renderer.external_output_mode with
    | Lib.Render_geometry.Split_footer, Capture_stdout ->
        (match Render_context.render_geometry renderer.context with
        | Error error -> Error error
        | Ok geometry when Int.compare geometry.render_height 0 <= 0 ->
            Error Error.Invalid_argument
        | Ok geometry ->
            (match
               Render_context.capabilities renderer.context,
               Render_context.clock renderer.context,
               Render_context.width_method renderer.context,
               Render_context.terminal_width renderer.context,
               Render_context.terminal_height renderer.context
             with
            | Error error, _, _, _, _
            | _, Error error, _, _, _
            | _, _, Error error, _, _
            | _, _, _, Error error, _
            | _, _, _, _, Error error ->
                Error error
            | Ok capabilities, Ok clock, Ok unicode, Ok terminal_width,
              Ok terminal_height ->
                let snapshot_context =
                  Render_context.Private.create
                    ~owner:(Render_context.Private.new_owner ())
                    ~width:(Int32.of_int (max 1 geometry.render_width))
                    ~height:(Int32.of_int (max 1 geometry.render_height))
                    ~terminal_width ~terminal_height
                    ~capabilities ~clock
                    ~hit_grid:(Opentui_raw.Renderer.hit_grid renderer.raw)
                    ~presentation:renderer.raw ~offscreen:true
                in
                Fun.protect
                  ~finally:(fun () -> Render_context.Private.close snapshot_context)
                  (fun () ->
                    let width_method = text_width_method unicode in
                    let context =
                      {
                        width = max 1 geometry.render_width;
                        width_method;
                        tail_column = projected_split_tail_column renderer geometry;
                        render_context = snapshot_context;
                      }
                    in
                    let snapshot : scrollback_snapshot = writer context in
                    let root = snapshot.root in
                    let snapshot_root_ref : Renderable.t option ref = ref None in
                    let cleanup_snapshot_root () =
                      Option.iter
                        (fun snapshot_root ->
                          Renderable.destroy_recursively snapshot_root)
                        !snapshot_root_ref;
                      if not (Renderable.is_destroyed root) then
                        Renderable.destroy_recursively root
                    in
                    Fun.protect ~finally:cleanup_snapshot_root (fun () ->
                        if Renderable.is_destroyed root
                           || Option.is_some (Renderable.parent root)
                           || not (Render_context.same_owner
                                     (Renderable.context root) snapshot_context)
                        then Error Error.Invalid_argument
                        else
                          let snapshot_width =
                            max 1 (min snapshot.width (max 1 geometry.render_width))
                          in
                          let snapshot_height = max 1 snapshot.height in
                          let row_columns =
                            max 0 (min snapshot.row_columns snapshot_width)
                          in
                          match
                            Render_context.Private.resize_offscreen snapshot_context
                              ~width:(Int32.of_int snapshot_width)
                              ~height:(Int32.of_int snapshot_height)
                          with
                          | () ->
                              (match
                                 Renderable.Private.create_root snapshot_context
                               with
                              | Error error -> Error error
                              | Ok snapshot_root ->
                                  snapshot_root_ref := Some snapshot_root;
                                  let result =
                                match
                                  Renderable.Private.attach ~parent:snapshot_root
                                    ~child:root ~index:0
                                with
                                | Error error -> Error error
                                | Ok _ ->
                                    (match
                                       Renderable.Private.resize_root snapshot_root
                                         ~width:(Int32.of_int snapshot_width)
                                         ~height:(Int32.of_int snapshot_height)
                                     with
                                    | Error error -> Error error
                                    | Ok () ->
                                        (match
                                           Owned_buffer.create ~width:snapshot_width
                                             ~height:snapshot_height ~width_method ()
                                         with
                                        | Error error -> Error error
                                        | Ok buffer ->
                                            let render_result =
                                              let target = owned_buffer_as_buffer buffer in
                                              Result.bind
                                                (Owned_buffer.clear buffer
                                                   ~background:Color.transparent)
                                                (fun () ->
                                                  Result.bind
                                                    (Renderable.Private.render_root
                                                       snapshot_root target
                                                       ~delta_time:0.0)
                                                    (fun () ->
                                                      (match
                                                         snapshot_row_widths buffer
                                                           ~width:snapshot_width
                                                           ~height:snapshot_height
                                                           ~row_columns
                                                       with
                                                      | Error error ->
                                                          Owned_buffer.close buffer;
                                                          Error error
                                                      | Ok row_widths ->
                                                          renderer.scrollback_commits <-
                                                          renderer.scrollback_commits
                                                            @ [ {
                                                                  snapshot = buffer;
                                                                  row_columns;
                                                                  row_widths;
                                                                  start_on_new_line =
                                                                    snapshot.start_on_new_line;
                                                                  trailing_newline =
                                                                    snapshot.trailing_newline;
                                                                } ];
                                                          Render_context.Private.request_render
                                                            renderer.context;
                                                          Ok ())))
                                            in
                                            (match render_result with
                                            | Ok () -> Ok ()
                                            | Error error ->
                                                Owned_buffer.close buffer;
                                                Error error)))
                                  in
                                  result))
                  )))
    | Lib.Render_geometry.Alternate_screen, _
    | Lib.Render_geometry.Main_screen, _
    | Lib.Render_geometry.Split_footer, Passthrough -> Error Error.Invalid_argument

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

let dispatch_pointer_in_surface renderer (decoded : Lib.Mouse_decoder.event) =
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
            if Renderable.Private.mouse_capture_requested event then
              capture renderer target;
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

let dispatch_pointer renderer (decoded : Lib.Mouse_decoder.event) =
  if not renderer.use_mouse then Ok false
  else
    let render_offset =
      if is_split_screen renderer.screen_mode then
        Int32.to_int renderer.split_render_offset
      else 0
    in
    if is_split_screen renderer.screen_mode
       && Int.compare decoded.Lib.Mouse_decoder.y render_offset < 0
    then Ok false
    else
      let decoded =
        if is_split_screen renderer.screen_mode then
          { decoded with Lib.Mouse_decoder.y = decoded.Lib.Mouse_decoder.y - render_offset }
        else decoded
      in
      dispatch_pointer_in_surface renderer decoded

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

let write_terminal_output renderer bytes =
  match Opentui_raw.Renderer.write_out renderer.raw bytes with
  | Ok () -> Ok ()
  | Error error -> Error (map_raw_error error)

let resize renderer ~width ~height =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else if Int32.compare width 0l <= 0 || Int32.compare height 0l <= 0 then
    Error Error.Invalid_argument
  else
    let previous_geometry =
      match Render_context.render_geometry renderer.context with
      | Ok geometry -> Some geometry
      | Error _ -> None
    in
    match Render_context.terminal_width renderer.context,
      Render_context.terminal_height renderer.context with
    | Error error, _ | _, Error error -> Error error
    | Ok previous_terminal_width, Ok previous_terminal_height ->
        let previous_footer_height =
          match previous_geometry with
          | Some geometry -> geometry.effective_footer_height
          | None -> 0
        in
        let pending_transition_start =
          if renderer.split_transition_pending then
            renderer.split_transition_source_top_line
          else None
        in
        let visible_previous_split_height =
          match renderer.split_transition_source_height with
          | Some height -> height
          | None -> previous_footer_height
        in
        let clear_start =
          if not (is_split_screen renderer.screen_mode)
             || Int.compare visible_previous_split_height 0 <= 0
          then None
          else
            let width_shrink_start =
              if Int32.compare width previous_terminal_width < 0 then
                Some
                  (max 1
                     (Int32.to_int previous_terminal_height
                     - (visible_previous_split_height * 2)))
              else None
            in
            match pending_transition_start, width_shrink_start with
            | None, None -> None
            | Some start, None -> Some (max 1 start)
            | None, Some start -> Some start
            | Some transition_start, Some width_start ->
                Some (max 1 (min transition_start width_start))
        in
        let geometry =
          Lib.Render_geometry.calculate renderer.screen_mode
            ~terminal_width:(Int32.to_int width)
            ~terminal_height:(Int32.to_int height)
            ~footer_height:renderer.footer_height
        in
        Result.bind (flush_scrollback_for_transition renderer) (fun () ->
            Result.bind
              (if is_split_screen renderer.screen_mode then
                 Buffer.clear renderer.current_buffer
                   ~background:renderer.background_color
               else Ok ())
              (fun () ->
                Result.bind
                  (match clear_start with
                  | None -> Ok ()
                  | Some row ->
                      (match Lib.Ansi.move_cursor_and_clear ~row ~column:1 with
                      | Error _ -> Error Error.Invalid_argument
                      | Ok sequence ->
                          write_terminal_output renderer
                            (Bytes.of_string sequence)))
                  (fun () ->
                    match
                      Opentui_raw.Renderer.clear_pending_split_footer_transition
                        renderer.raw
                    with
                    | Error error -> Error (map_raw_error error)
                    | Ok () ->
                        renderer.split_transition_pending <- false;
                        renderer.split_transition_source_top_line <- None;
                        renderer.split_transition_source_height <- None;
                        match
                          Opentui_raw.Renderer.resize renderer.raw
                            ~width:(Int32.of_int (max 1 geometry.render_width))
                            ~height:(Int32.of_int (max 1 geometry.render_height))
                        with
                        | Error error -> Error (map_raw_error error)
                        | Ok () ->
                            release_capture renderer;
                            ignore (clear_selection renderer);
                            Render_context.Private.resize renderer.context ~width ~height;
                            (match
                               Renderable.Private.resize_root renderer.root
                                 ~width:(Int32.of_int geometry.render_width)
                                 ~height:(Int32.of_int geometry.render_height)
                             with
                            | Error error -> Error error
                            | Ok () ->
                                Result.bind
                                  (Console.resize renderer.console
                                     ~width:(max 1 geometry.render_width)
                                     ~height:(max 1 geometry.render_height))
                                  (fun () ->
                                    Result.bind
                                      (set_split_native_state renderer geometry
                                         ~preserve_scrollback:true)
                                      (fun () ->
                                        ignore
                                          (Renderer_events.Private.emit_resize
                                             (Render_context.Private.events renderer.context)
                                             { Render_context.width; height });
                                        Render_context.Private.request_render
                                          renderer.context;
                                        Ok ()))))))

let render ?(delta_time = 0.0) renderer ~force =
  if renderer.destruction_started
     || not (Render_context.Private.is_open renderer.context)
  then Error Error.Closed
  else if renderer.output_failed then Error output_failure
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
                        if is_split_screen renderer.screen_mode
                           && is_capture_output renderer.external_output_mode
                        then
                          Result.map raw_render_status
                            (commit_scrollback_frames renderer
                               ~force:native_force)
                        else
                          let render_offset =
                            if is_split_screen renderer.screen_mode then
                              renderer.split_render_offset
                            else 0l
                          in
                          (match
                             Opentui_raw.Renderer.set_render_offset renderer.raw
                               ~offset:render_offset
                           with
                           | Error error -> Error (map_raw_error error)
                           | Ok () ->
                               (match
                                  Opentui_raw.Renderer.render renderer.raw
                                    ~force:native_force
                                with
                                | Error error -> Error (map_raw_error error)
                                | Ok status -> Ok status))
                      in
                      match native_result with
                      | Error error -> failed_frame renderer error
                      | Ok native_status ->
                          (match flush_output renderer with
                           | Error error -> failed_frame renderer error
                           | Ok () ->
                               match native_status with
                               | Opentui_raw.Renderer.Rendered ->
                                   renderer.force_full_repaint <- false;
                                   if Render_context.Private.hit_grid_dirty renderer.context then
                                     recheck_hover_state renderer;
                                   ignore
                                     (Renderer_events.Private.emit_frame
                                        (Render_context.Private.events renderer.context)
                                        { Render_context.frame_id });
                                   Ok Rendered
                               | Opentui_raw.Renderer.Skipped ->
                                   Render_context.Private.abort_hit_grid renderer.context;
                                   Render_context.Private.request_render renderer.context;
                                   Ok Skipped
                               | Opentui_raw.Renderer.Failed ->
                                   Render_context.Private.abort_hit_grid renderer.context;
                                   renderer.force_full_repaint <- true;
                                   Render_context.Private.request_render renderer.context;
                                   Ok Failed)))
        in
        frame_finished := true;
        result)
  end

let close renderer =
  if renderer.destruction_started then
    match renderer.close_error with
    | None -> Ok ()
    | Some error -> Error error
  else if not (Render_context.Private.is_open renderer.context) then Ok ()
  else begin
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
    let scrollback_result =
      if is_split_screen renderer.screen_mode
         && is_capture_output renderer.external_output_mode
      then begin
        let commit_result =
          if has_scrollback_commits renderer then
            commit_scrollback_commits renderer ~force:true ~limit:None
          else Ok Opentui_raw.Renderer.Rendered
        in
        let reset_result =
          match
            Opentui_raw.Renderer.reset_split_scrollback renderer.raw
              ~seed_rows:0l ~pinned_render_offset:0l
          with
          | Ok _ -> Ok ()
          | Error error -> Error (map_raw_error error)
        in
        renderer.split_render_offset <- 0l;
        renderer.split_tail_column <- 0;
        let committed_result =
          match commit_result with
          | Error error -> Error error
          | Ok Opentui_raw.Renderer.Rendered -> Ok ()
          | Ok Opentui_raw.Renderer.Skipped
          | Ok Opentui_raw.Renderer.Failed -> Error Error.Unsupported
        in
        (match committed_result, reset_result with
        | Error error, _ | Ok (), Error error -> Error error
        | Ok (), Ok () -> Ok ())
      end else Ok ()
    in
    release_capture renderer;
    ignore (clear_selection renderer);
    renderer.last_over <- None;
    renderer.last_over_num <- None;
    renderer.latest_pointer <- None;
    renderer.post_processes <- [];
    Renderer_theme_mode.dispose renderer.theme_mode;
    Console.destroy renderer.console;
    Renderable.destroy_recursively renderer.root;
    List.iter (fun commit -> Owned_buffer.close commit.snapshot)
      renderer.scrollback_commits;
    renderer.scrollback_commits <- [];
    ignore
      (Renderer_events.Private.emit_destroy
         (Render_context.Private.events renderer.context) ());
    Render_context.Private.close renderer.context;
    Opentui_raw.Renderer.close renderer.raw;
    let output_result = flush_output renderer in
    let feed_result =
      match renderer.output_feed with
      | None -> Ok ()
      | Some feed -> Native_span_feed.close feed
    in
    let result =
      match scrollback_result, output_result, feed_result with
      | Error error, _, _ -> Error error
      | Ok (), Error error, _ -> Error error
      | Ok (), Ok (), Error error -> Error error
      | Ok (), Ok (), Ok () -> Ok ()
    in
    (match result with
     | Ok () -> ()
     | Error error -> renderer.close_error <- Some error);
    result
  end

let destroy renderer = ignore (close renderer)

let is_destroyed renderer = not (Render_context.Private.is_open renderer.context)
