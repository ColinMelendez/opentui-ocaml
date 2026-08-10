type renderer = {
  raw : Opentui_raw.Renderer.t;
  clear_background : Color.t;
  mutable closed : bool;
  mutable active_frame : bool;
}

type t = renderer

type render_status = Rendered | Skipped | Failed

type frame = {
  owner : renderer;
  buffer : Opentui_raw.Buffer.t;
  mutable active : bool;
}

module Frame = struct
  type t = frame

  let ensure_open frame =
    if frame.owner.closed then Error Error.Closed
    else if not frame.active then Error Error.Frame_not_open
    else Ok ()

  let map_native result =
    match result with
    | Ok value -> Ok value
    | Error error -> Error (Error.Native error)

  let clear frame ~background =
    match ensure_open frame with
    | Error error -> Error error
    | Ok () ->
        map_native
          (Opentui_raw.Buffer.clear frame.buffer
             ~background:(Color.Private.to_raw background))

  let set_cell frame ~x ~y ~character ~foreground ~background ~attributes =
    match ensure_open frame with
    | Error error -> Error error
    | Ok () ->
        map_native
          (Opentui_raw.Buffer.set_cell frame.buffer ~x ~y ~character
             ~foreground:(Color.Private.to_raw foreground)
             ~background:(Color.Private.to_raw background) ~attributes)

  let draw_text frame ~text ~x ~y ~foreground ~background ~attributes =
    match ensure_open frame with
    | Error error -> Error error
    | Ok () ->
        map_native
          (Opentui_raw.Buffer.draw_text frame.buffer ~text ~x ~y
             ~foreground:(Color.Private.to_raw foreground)
             ~background:(Color.Private.to_raw background) ~attributes)

  let write_resolved_chars frame ~output ~add_line_breaks =
    match ensure_open frame with
    | Error error -> Error error
    | Ok () ->
        map_native
          (Opentui_raw.Buffer.write_resolved_chars frame.buffer ~output
             ~add_line_breaks)
end

let create ~width ~height =
  match
    Color.rgba ~red:0 ~green:0 ~blue:0 ~alpha:0
  with
  | Error error -> Error error
  | Ok clear_background ->
      (match Opentui_raw.Renderer.create ~width ~height with
      | Ok raw ->
          Ok { raw; clear_background; closed = false; active_frame = false }
      | Error error -> Error (Error.Native error))

let resize renderer ~width ~height =
  if renderer.closed then Error Error.Closed
  else if renderer.active_frame then Error Error.Frame_already_open
  else
    match Opentui_raw.Renderer.resize renderer.raw ~width ~height with
    | Ok () -> Ok ()
    | Error error -> Error (Error.Native error)

let close renderer =
  if not renderer.closed then (
    renderer.closed <- true;
    renderer.active_frame <- false;
    Opentui_raw.Renderer.close renderer.raw)

let begin_frame renderer =
  if renderer.closed then Error Error.Closed
  else if renderer.active_frame then Error Error.Frame_already_open
  else
    match Opentui_raw.Renderer.next_buffer renderer.raw with
    | Error error -> Error (Error.Native error)
    | Ok buffer ->
        renderer.active_frame <- true;
        Ok { owner = renderer; buffer; active = true }

let present frame ~force =
  if frame.owner.closed then Error Error.Closed
  else if not frame.active then Error Error.Frame_not_open
  else
    let result = Opentui_raw.Renderer.render frame.owner.raw ~force in
    frame.active <- false;
    frame.owner.active_frame <- false;
    match result with
    | Error error -> Error (Error.Native error)
    | Ok Opentui_raw.Renderer.Rendered -> Ok Rendered
    | Ok Opentui_raw.Renderer.Skipped -> Ok Skipped
    | Ok Opentui_raw.Renderer.Failed -> Ok Failed

let discard frame =
  if frame.active then (
    ignore
      (Opentui_raw.Buffer.clear frame.buffer
         ~background:
           (Color.Private.to_raw frame.owner.clear_background));
    frame.active <- false;
    frame.owner.active_frame <- false)

let run_frame renderer ~force ~draw =
  match begin_frame renderer with
  | Error error -> Error error
  | Ok frame ->
      Fun.protect
        ~finally:(fun () -> discard frame)
        (fun () ->
          match draw frame with
          | Error error -> Error error
          | Ok () -> present frame ~force)
