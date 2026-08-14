type t = {
  renderable : Renderable.t;
  text_buffer : Text_buffer.t;
  text_buffer_view : Text_buffer_view.t;
  native_measure : Native_measure.t;
  mutable wrap_mode : Text_buffer_view.wrap_mode;
  mutable lifecycle_pass : (unit -> unit) option;
}

let close_resources text_buffer_renderable =
  ignore (Native_measure.close text_buffer_renderable.native_measure);
  ignore (Text_buffer_view.close text_buffer_renderable.text_buffer_view);
  ignore (Text_buffer.close text_buffer_renderable.text_buffer)

let cleanup_creation renderable text_buffer text_buffer_view native_measure =
  ignore (Native_measure.close native_measure);
  ignore (Text_buffer_view.close text_buffer_view);
  ignore (Text_buffer.close text_buffer);
  Renderable.destroy renderable

let mark_measure_dirty text_buffer_renderable =
  Renderable.Private.mark_yoga_dirty text_buffer_renderable.renderable

let install_behavior text_buffer_renderable =
  let on_resize _ ~width:_ ~height:_ =
    ignore (Renderable.Private.mark_yoga_dirty text_buffer_renderable.renderable)
  in
  let lifecycle_pass =
    Option.map
      (fun callback _ -> callback ())
      text_buffer_renderable.lifecycle_pass
  in
  let render_self renderable buffer _delta_time =
    Buffer.draw_text_buffer buffer
      ~view:text_buffer_renderable.text_buffer_view
      ~x:(Int32.of_float
            (Renderable.screen_x renderable))
      ~y:(Int32.of_float
            (Renderable.screen_y renderable))
  in
  let behavior =
    Renderable.Private.make_behavior ~on_resize ?lifecycle_pass
      ~render_self
      ~destroy_self:(fun _ -> close_resources text_buffer_renderable) ()
  in
  Renderable.Private.set_behavior text_buffer_renderable.renderable behavior

let ensure_alive text_buffer_renderable =
  if Renderable.is_destroyed text_buffer_renderable.renderable then
    Error Error.Destroyed
  else Ok ()

let set_wrap_width_for_dimensions text_buffer_renderable width =
  let width =
    match text_buffer_renderable.wrap_mode, width with
    | Text_buffer_view.No_wrap, _ | _, 0 -> None
    | _, width -> Some (Int32.of_int width)
  in
  Text_buffer_view.set_wrap_width text_buffer_renderable.text_buffer_view width

let create context ?id ?(width_method = Text_buffer.Wcwidth)
    ?(wrap_mode = Text_buffer_view.Word) () =
  match Renderable.Private.create context ?id () with
  | Error error -> Error error
  | Ok renderable ->
      (match Text_buffer.create width_method with
      | Error error ->
          Renderable.destroy renderable;
          Error error
      | Ok text_buffer ->
          (match Text_buffer_view.create text_buffer with
          | Error error ->
              ignore (Text_buffer.close text_buffer);
              Renderable.destroy renderable;
              Error error
          | Ok text_buffer_view ->
              (match
                 Text_buffer_view.set_wrap_mode text_buffer_view wrap_mode
               with
              | Error error ->
                  ignore (Text_buffer_view.close text_buffer_view);
                  ignore (Text_buffer.close text_buffer);
                  Renderable.destroy renderable;
                  Error error
              | Ok () ->
                  (match Native_measure.create () with
                  | Error error ->
                      ignore (Text_buffer_view.close text_buffer_view);
                      ignore (Text_buffer.close text_buffer);
                      Renderable.destroy renderable;
                      Error error
                  | Ok native_measure ->
                      (match
                         Renderable.Private.with_yoga_node renderable
                           (fun node ->
                             Native_measure.attach_yoga_node native_measure node)
                       with
                      | Error error ->
                          cleanup_creation renderable text_buffer
                            text_buffer_view native_measure;
                          Error error
                      | Ok () ->
                          (match
                             Native_measure.set_measure_target native_measure
                               text_buffer_view
                           with
                          | Error error ->
                              cleanup_creation renderable text_buffer
                                text_buffer_view native_measure;
                              Error error
                          | Ok () ->
                              let text_buffer_renderable =
                                {
                                  renderable;
                                  text_buffer;
                                  text_buffer_view;
                                  native_measure;
                                  wrap_mode;
                                  lifecycle_pass = None;
                                }
                              in
                              install_behavior text_buffer_renderable;
                              (match Render_context.width context with
                              | Error error ->
                                  Renderable.destroy renderable;
                                  Error error
                              | Ok width ->
                                  (match
                                     set_wrap_width_for_dimensions
                                       text_buffer_renderable (Int32.to_int width)
                                   with
                                  | Error error ->
                                      Renderable.destroy renderable;
                                      Error error
                                  | Ok () -> Ok text_buffer_renderable))))))))

let as_renderable text_buffer_renderable = text_buffer_renderable.renderable
let text_buffer text_buffer_renderable = text_buffer_renderable.text_buffer

let text_buffer_view text_buffer_renderable =
  text_buffer_renderable.text_buffer_view

let set_text text_buffer_renderable text =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.set_text text_buffer_renderable.text_buffer text)
        (fun () -> mark_measure_dirty text_buffer_renderable))

let append text_buffer_renderable text =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.append text_buffer_renderable.text_buffer text)
        (fun () -> mark_measure_dirty text_buffer_renderable))

let clear text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.clear text_buffer_renderable.text_buffer)
        (fun () -> mark_measure_dirty text_buffer_renderable))

let wrap_mode text_buffer_renderable = text_buffer_renderable.wrap_mode

let equal_wrap_mode left right =
  match left, right with
  | Text_buffer_view.No_wrap, Text_buffer_view.No_wrap
  | Text_buffer_view.Char, Text_buffer_view.Char
  | Text_buffer_view.Word, Text_buffer_view.Word -> true
  | Text_buffer_view.No_wrap, (Text_buffer_view.Char | Text_buffer_view.Word)
  | Text_buffer_view.Char, (Text_buffer_view.No_wrap | Text_buffer_view.Word)
  | Text_buffer_view.Word, (Text_buffer_view.No_wrap | Text_buffer_view.Char) ->
      false

let set_wrap_mode text_buffer_renderable wrap_mode =
  match ensure_alive text_buffer_renderable with
  | Error error -> Error error
  | Ok () when equal_wrap_mode text_buffer_renderable.wrap_mode wrap_mode ->
      Ok ()
  | Ok () ->
    let previous = text_buffer_renderable.wrap_mode in
    match
      Text_buffer_view.set_wrap_mode text_buffer_renderable.text_buffer_view
        wrap_mode
    with
    | Error error -> Error error
    | Ok () ->
        text_buffer_renderable.wrap_mode <- wrap_mode;
        (match
           Render_context.width
             (Renderable.context text_buffer_renderable.renderable)
         with
        | Error error ->
            text_buffer_renderable.wrap_mode <- previous;
            ignore
              (Text_buffer_view.set_wrap_mode
                 text_buffer_renderable.text_buffer_view previous);
            Error error
        | Ok width ->
            (match
               set_wrap_width_for_dimensions text_buffer_renderable
                 (Int32.to_int width)
             with
            | Error error ->
                text_buffer_renderable.wrap_mode <- previous;
                ignore
                  (Text_buffer_view.set_wrap_mode
                     text_buffer_renderable.text_buffer_view previous);
                Error error
            | Ok () -> mark_measure_dirty text_buffer_renderable))

let measure_for_dimensions text_buffer_renderable ~width ~height =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer_view.measure_for_dimensions
        text_buffer_renderable.text_buffer_view ~width ~height)

let destroy text_buffer_renderable =
  Renderable.destroy text_buffer_renderable.renderable

module Private = struct
  let set_lifecycle_pass text_buffer_renderable lifecycle_pass =
    text_buffer_renderable.lifecycle_pass <- lifecycle_pass;
    install_behavior text_buffer_renderable
end
