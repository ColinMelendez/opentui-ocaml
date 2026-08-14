type render_status = Rendered | Skipped | Failed

type t = {
  raw : Opentui_raw.Renderer.t;
  context : Render_context.t;
  root : Renderable.t;
  children : Layout_children.t;
  current_buffer : Buffer.t;
  next_buffer : Buffer.t;
  auto_focus : bool;
  mutable latest_pointer : (int * int) option;
  mutable last_pointer_modifiers : Lib.Mouse_decoder.modifiers;
  mutable last_over : Renderable.t option;
  mutable last_over_num : int option;
  mutable captured : Renderable.t option;
}

type resize_event = Render_context.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Render_context.frame_event = {
  frame_id : int64;
}

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

let create ~width ~height =
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
              let context =
                Render_context.Private.create
                  ~owner:(Render_context.Private.new_owner ()) ~width ~height
              in
              (match Renderable.Private.create_root context with
              | Error error ->
                  Render_context.Private.close context;
                  Opentui_raw.Renderer.close raw;
                  Error error
              | Ok root ->
                  Ok
                    {
                      raw;
                      context;
                      root;
                      children = Layout_children.Private.of_renderable root;
                      current_buffer = Buffer_internal.of_raw current_buffer;
                      next_buffer = Buffer_internal.of_raw next_buffer;
                      auto_focus = true;
                      latest_pointer = None;
                      last_pointer_modifiers =
                        { Lib.Mouse_decoder.shift = false; alt = false; ctrl = false };
                      last_over = None;
                      last_over_num = None;
                      captured = None;
                    })))

let context renderer = renderer.context
let root renderer = renderer.root
let children renderer = renderer.children

let width renderer = Render_context.width renderer.context
let height renderer = Render_context.height renderer.context
let frame_id renderer = Render_context.frame_id renderer.context
let has_pending_render renderer =
  Render_context.has_pending_render renderer.context

let current_buffer renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.current_buffer
  else Error Error.Closed

let next_buffer renderer =
  if Render_context.Private.is_open renderer.context then Ok renderer.next_buffer
  else Error Error.Closed

let request_render renderer = Render_context.request_render renderer.context

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
              let event =
                make_pointer_event ~kind ~decoded ~source:None
                  ~target:(Some captured) ~is_dragging:true
              in
              send_pointer_event renderer captured event;
              Ok true
          | Lib.Mouse_decoder.Scroll -> Ok false)
      | None ->
          (match target with
          | None ->
              renderer.captured <- None;
              renderer.last_over <- None;
              renderer.last_over_num <- None;
              Ok true
          | Some target ->
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

let handle_input renderer input =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else
    match input with
    | Lib.Stdin_parser.Key { raw; key; modifiers } ->
        Ok
          (Lib.Key_handler.process_key
             (Render_context.Private.key_handler renderer.context)
             ~raw ~key ~modifiers)
    | Lib.Stdin_parser.Paste bytes ->
        Ok
          (Lib.Key_handler.process_paste
             (Render_context.Private.key_handler renderer.context) bytes)
    | Lib.Stdin_parser.Mouse { event; _ } -> dispatch_pointer renderer event
    | Lib.Stdin_parser.Response _ -> Ok false

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
        Render_context.Private.resize renderer.context ~width ~height;
        (match
           Renderable.Private.resize_root renderer.root ~width ~height
         with
        | Error error -> Error error
        | Ok () ->
        ignore
          (Renderer_events.Private.emit_resize
             (Render_context.Private.events renderer.context)
             { Render_context.width; height });
        Render_context.Private.request_render renderer.context;
        Ok ())

let render renderer ~force =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else begin
    Render_context.Private.clear_render_request renderer.context;
    let frame_id = Render_context.Private.advance_frame renderer.context in
    (match
       Renderable.Private.render_root renderer.root renderer.next_buffer
         ~delta_time:0.0
     with
    | Error error ->
        Render_context.Private.request_render renderer.context;
        Error error
    | Ok () ->
        let result = Opentui_raw.Renderer.render renderer.raw ~force in
        match result with
        | Error error ->
            Render_context.Private.request_render renderer.context;
            Error (map_raw_error error)
        | Ok Opentui_raw.Renderer.Rendered ->
            Render_context.Private.commit_hit_grid renderer.context;
            recheck_hover_state renderer;
            ignore
              (Renderer_events.Private.emit_frame
                 (Render_context.Private.events renderer.context)
                 { Render_context.frame_id });
            Ok Rendered
        | Ok Opentui_raw.Renderer.Skipped -> Ok Skipped
        | Ok Opentui_raw.Renderer.Failed -> Ok Failed)
  end

let destroy renderer =
  if Render_context.Private.is_open renderer.context then begin
    renderer.captured <- None;
    renderer.last_over <- None;
    renderer.last_over_num <- None;
    renderer.latest_pointer <- None;
    Renderable.destroy_recursively renderer.root;
    Render_context.Private.close renderer.context;
    Opentui_raw.Renderer.close renderer.raw
  end

let is_destroyed renderer = not (Render_context.Private.is_open renderer.context)
