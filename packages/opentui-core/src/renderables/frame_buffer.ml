type t = {
  renderable : Renderable.t;
  frame_buffer : Owned_buffer.t;
  mutable destroyed : bool;
}

let ensure_alive frame_buffer =
  if frame_buffer.destroyed then Error Error.Destroyed else Ok ()

let render_self frame_buffer renderable buffer _delta_time =
  let x = Int32.of_float (Float.floor (Renderable.screen_x renderable)) in
  let y = Int32.of_float (Float.floor (Renderable.screen_y renderable)) in
  Buffer.draw_frame_buffer buffer ~source:frame_buffer.frame_buffer ~x ~y ()

let resize_resource frame_buffer ~width ~height =
  if Int.compare width 0 <= 0 || Int.compare height 0 <= 0 then ()
  else ignore (Owned_buffer.resize frame_buffer.frame_buffer ~width ~height)

let create context ?id ~width ~height ?(respect_alpha = false)
    ?(width_method = Text_buffer.Unicode) ?(focusable = false) () =
  if Int.compare width 0 <= 0 || Int.compare height 0 <= 0 then Error Error.Invalid_argument
  else
    match
      Owned_buffer.create ?id ~width ~height ~respect_alpha ~width_method ()
    with
    | Error error -> Error error
    | Ok frame_buffer ->
        (match Renderable.Private.create context ?id () with
        | Error error ->
            Owned_buffer.close frame_buffer;
            Error error
        | Ok renderable ->
            let value = { renderable; frame_buffer; destroyed = false } in
            let behavior =
              Renderable.Private.make_behavior
                ~render_self:(render_self value)
                ~on_resize:(fun _renderable ~width ~height ->
                  resize_resource value ~width ~height;
                  ignore (Renderable.request_render value.renderable))
                ~destroy_self:(fun _renderable ->
                  if not value.destroyed then begin
                    value.destroyed <- true;
                    Owned_buffer.close value.frame_buffer
                  end)
                ()
            in
            Renderable.Private.set_behavior renderable behavior;
            let result =
              Result.bind (Renderable.set_width renderable (Yoga.Point (float_of_int width)))
                (fun () ->
                  Result.bind
                    (Renderable.set_height renderable
                       (Yoga.Point (float_of_int height)))
                    (fun () ->
                      if focusable then Renderable.set_focusable renderable true
                      else Ok ()))
            in
            (match result with
            | Ok () -> Ok value
            | Error error ->
                Renderable.destroy renderable;
                Error error))

let as_renderable frame_buffer = frame_buffer.renderable
let frame_buffer frame_buffer = frame_buffer.frame_buffer

let resize frame_buffer ~width ~height =
  Result.bind (ensure_alive frame_buffer) (fun () ->
      if Int.compare width 0 <= 0 || Int.compare height 0 <= 0 then Error Error.Invalid_argument
      else
        Result.bind
          (Owned_buffer.resize frame_buffer.frame_buffer ~width ~height)
          (fun () ->
            Result.bind (Renderable.set_width frame_buffer.renderable
                           (Yoga.Point (float_of_int width)))
              (fun () ->
                Renderable.set_height frame_buffer.renderable
                  (Yoga.Point (float_of_int height)))))

let width frame_buffer =
  match Owned_buffer.width frame_buffer.frame_buffer with
  | Ok width -> width
  | Error _ -> 0

let height frame_buffer =
  match Owned_buffer.height frame_buffer.frame_buffer with
  | Ok height -> height
  | Error _ -> 0

let destroy frame_buffer = Renderable.destroy frame_buffer.renderable
