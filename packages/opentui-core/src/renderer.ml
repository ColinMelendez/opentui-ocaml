type render_status = Rendered | Skipped | Failed

type t = {
  raw : Opentui_raw.Renderer.t;
  context : Render_context.t;
  root : Renderable.t;
  children : Layout_children.t;
  current_buffer : Buffer.t;
  next_buffer : Buffer.t;
}

type resize_event = Render_context.resize_event = {
  width : int32;
  height : int32;
}

type frame_event = Render_context.frame_event = {
  frame_id : int64;
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

let resize renderer ~width ~height =
  if not (Render_context.Private.is_open renderer.context) then Error Error.Closed
  else
    match Opentui_raw.Renderer.resize renderer.raw ~width ~height with
    | Error error -> Error (map_raw_error error)
    | Ok () ->
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
    Renderable.destroy_recursively renderer.root;
    Render_context.Private.close renderer.context;
    Opentui_raw.Renderer.close renderer.raw
  end

let is_destroyed renderer = not (Render_context.Private.is_open renderer.context)
