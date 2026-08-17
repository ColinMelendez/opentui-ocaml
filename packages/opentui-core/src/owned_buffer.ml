type t = {
  raw : Opentui_raw.Optimized_buffer.t;
  mutable width : int;
  mutable height : int;
  mutable closed : bool;
}

let map_error error =
  match error with
  | Opentui_raw.Error.Closed -> Error.Closed
  | error -> Error.Native (Native.Error.Native error)

let raw buffer = buffer.raw

let ensure_open buffer = if buffer.closed then Error Error.Closed else Ok ()

let map_raw_error error =
  match error with
  | Opentui_raw.Error.Invalid_argument -> Error.Invalid_argument
  | Opentui_raw.Error.Closed
  | Opentui_raw.Error.Stale_handle -> Error.Closed
  | error -> Error.Native (Native.Error.Native error)

let map_result result =
  match result with
  | Ok value -> Ok value
  | Error error -> Error (map_raw_error error)

let raw_width_method = function
  | Text_buffer.Wcwidth -> 0l
  | Text_buffer.Unicode -> 1l

let create ?id ?(respect_alpha = false)
    ?(width_method = Text_buffer.Unicode) ~width ~height () =
  if width <= 0 || height <= 0 then Error Error.Invalid_argument
  else
    let id = Option.value id ~default:"unnamed buffer" in
    match
      Opentui_raw.Optimized_buffer.create ~width:(Int32.of_int width)
        ~height:(Int32.of_int height) ~respect_alpha
        ~width_method:(raw_width_method width_method) ~id
    with
    | Error error -> Error (map_error error)
    | Ok raw -> Ok { raw; width; height; closed = false }

let width buffer = Result.bind (ensure_open buffer) (fun () -> Ok buffer.width)
let height buffer = Result.bind (ensure_open buffer) (fun () -> Ok buffer.height)

let clear buffer ~background =
  Result.bind (ensure_open buffer) (fun () ->
      map_result
        (Opentui_raw.Optimized_buffer.clear buffer.raw
           (Color.Private.to_raw background)))

let set_cell buffer ~x ~y ~character ~foreground ~background ~attributes =
  Result.bind (ensure_open buffer) (fun () ->
      if x < 0 || y < 0 then Error Error.Invalid_argument
      else
        map_result
          (Opentui_raw.Optimized_buffer.set_cell buffer.raw
             (Int32.of_int x, Int32.of_int y, character,
              Color.Private.to_raw foreground, Color.Private.to_raw background,
              attributes)))

let set_cell_with_alpha_blending buffer ~x ~y ~character ~foreground
    ~background ~attributes =
  Result.bind (ensure_open buffer) (fun () ->
      if x < 0 || y < 0 then Error Error.Invalid_argument
      else
        map_result
          (Opentui_raw.Optimized_buffer.set_cell_with_alpha_blending buffer.raw
             (Int32.of_int x, Int32.of_int y, character,
              Color.Private.to_raw foreground, Color.Private.to_raw background,
              attributes)))

let draw_text buffer ~text ~x ~y ~foreground ~background ~attributes =
  Result.bind (ensure_open buffer) (fun () ->
      if x < 0 || y < 0 then Error Error.Invalid_argument
      else
        map_result
          (Opentui_raw.Optimized_buffer.draw_text buffer.raw
             (text, Int32.of_int x, Int32.of_int y,
             Color.Private.to_raw foreground, Color.Private.to_raw background,
             attributes)))

let draw_text_buffer_view buffer ~view ~x ~y =
  Result.bind (ensure_open buffer) (fun () ->
      if x < 0 || y < 0 then Error Error.Invalid_argument
      else
        map_result
          (Opentui_raw.Optimized_buffer.draw_text_buffer_view buffer.raw
             (Text_buffer_view_internal.raw view) (Int32.of_int x)
             (Int32.of_int y)))

let draw_grid buffer ~border_chars ~border_foreground ~border_background
    ~column_offsets ~row_offsets ~draw_inner ~draw_outer =
  Result.bind (ensure_open buffer) (fun () ->
      map_result
        (Opentui_raw.Optimized_buffer.draw_grid buffer.raw
           ( border_chars,
             Color.Private.to_raw border_foreground,
             Color.Private.to_raw border_background,
             column_offsets,
             row_offsets,
             draw_inner,
             draw_outer )))

let fill_rect buffer ~x ~y ~width ~height ~background =
  Result.bind (ensure_open buffer) (fun () ->
      if x < 0 || y < 0 || width < 0 || height < 0 then
        Error Error.Invalid_argument
      else
        map_result
          (Opentui_raw.Optimized_buffer.fill_rect buffer.raw
             (Int32.of_int x, Int32.of_int y, Int32.of_int width,
              Int32.of_int height, Color.Private.to_raw background)))

let draw_frame_buffer buffer ~source ~x ~y ?(source_x = 0) ?(source_y = 0)
    ?(source_width = 0) ?(source_height = 0) () =
  Result.bind (ensure_open buffer) (fun () ->
      Result.bind (ensure_open source) (fun () ->
          if source_x < 0 || source_y < 0 || source_width < 0
             || source_height < 0 then Error Error.Invalid_argument
          else
            map_result
              (Opentui_raw.Optimized_buffer.draw_frame_buffer buffer.raw
                  (Int32.of_int x, Int32.of_int y, source.raw,
                  Int32.of_int source_x, Int32.of_int source_y,
                  Int32.of_int source_width, Int32.of_int source_height))))

let image_protocol_to_int = function
  | Image.Auto -> 0l
  | Kitty -> 1l
  | Sixel -> 2l
  | Blocks -> 3l

let map_image_error error = Error.Native_image error

let map_image_draw_error = function
  | Opentui_raw.Error.Closed | Opentui_raw.Error.Stale_handle ->
      Opentui_raw.Image.Invalid_handle
  | Opentui_raw.Error.Invalid_argument -> Opentui_raw.Image.Invalid_argument
  | Opentui_raw.Error.Native_failure
  | Opentui_raw.Error.Output_too_small
  | Opentui_raw.Error.Queue_overflow
  | Opentui_raw.Error.No_space
  | Opentui_raw.Error.Max_bytes
  | Opentui_raw.Error.Busy -> Opentui_raw.Image.Unsupported_feature

let draw_image buffer ~image ~x ~y ~width ~height ~pixel_width ~pixel_height
    ?(source_x = 0) ?(source_y = 0) ?(source_width = 0)
    ?(source_height = 0) ?(protocol = Image.Auto) () =
  Result.bind (ensure_open buffer) (fun () ->
      if width < 0 || height < 0 || pixel_width < 0 || pixel_height < 0
         || source_x < 0 || source_y < 0 || source_width < 0
         || source_height < 0 then Error Error.Invalid_argument
      else
        match
          Image.Private.with_open image (fun image_handle ->
              match
                Opentui_raw.Optimized_buffer.draw_image buffer.raw
                  ( Int32.of_int x,
                    Int32.of_int y,
                    Int32.of_int width,
                    Int32.of_int height,
                    Int32.of_int pixel_width,
                    Int32.of_int pixel_height,
                    Int32.of_int source_x,
                    Int32.of_int source_y,
                    Int32.of_int source_width,
                    Int32.of_int source_height,
                    image_protocol_to_int protocol,
                    image_handle )
              with
              | Ok value -> Ok value
              | Error error -> Error (map_image_draw_error error))
        with
        | Ok value -> Ok value
        | Error error -> Error (map_image_error error))

let resize buffer ~width ~height =
  Result.bind (ensure_open buffer) (fun () ->
      if width <= 0 || height <= 0 then Error Error.Invalid_argument
      else
        match
          map_result
            (Opentui_raw.Optimized_buffer.resize buffer.raw
               (Int32.of_int width) (Int32.of_int height))
        with
        | Ok () ->
            buffer.width <- width;
            buffer.height <- height;
            Ok ()
        | Error error -> Error error)

type snapshot = int32 array * int32 array * int32 array * int32 array

let snapshot buffer =
  Result.bind (ensure_open buffer) (fun () ->
      map_result (Opentui_raw.Optimized_buffer.snapshot buffer.raw))

let restore buffer value =
  Result.bind (ensure_open buffer) (fun () ->
      map_result (Opentui_raw.Optimized_buffer.restore buffer.raw value))

let close buffer =
  if not buffer.closed then begin
    buffer.closed <- true;
    Opentui_raw.Optimized_buffer.close buffer.raw
  end
