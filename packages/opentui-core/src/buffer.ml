type t = Buffer_internal.t

let raw buffer = Buffer_internal.raw buffer

let map_error result =
  match result with
  | Ok value -> Ok value
  | Error Opentui_raw.Error.Closed -> Error Error.Closed
  | Error error -> Error (Error.Native (Native.Error.Native error))

let width buffer = map_error (Opentui_raw.Buffer.width (raw buffer))
let height buffer = map_error (Opentui_raw.Buffer.height (raw buffer))

let clear buffer ~background =
  map_error
    (Opentui_raw.Buffer.clear (raw buffer)
       ~background:(Color.Private.to_raw background))

let set_cell buffer ~x ~y ~character ~foreground ~background ~attributes =
  map_error
    (Opentui_raw.Buffer.set_cell (raw buffer) ~x ~y ~character
       ~foreground:(Color.Private.to_raw foreground)
       ~background:(Color.Private.to_raw background) ~attributes)

let draw_text buffer ~text ~x ~y ~foreground ~background ~attributes =
  map_error
    (Opentui_raw.Buffer.draw_text (raw buffer) ~text ~x ~y
       ~foreground:(Color.Private.to_raw foreground)
       ~background:(Color.Private.to_raw background) ~attributes)

let draw_box buffer ~x ~y ~width ~height ~border_chars ~packed_options
    ~border_color ~background_color ~title_color ~title ~bottom_title =
  map_error
    (Opentui_raw.Buffer.draw_box (raw buffer) ~x ~y ~width ~height
       ~border_chars ~packed_options
       ~border_color:(Color.Private.to_raw border_color)
       ~background_color:(Color.Private.to_raw background_color)
       ~title_color:(Color.Private.to_raw title_color) ~title ~bottom_title)

let draw_text_buffer buffer ~view ~x ~y =
  map_error
    (Opentui_raw.Buffer.draw_text_buffer_view (raw buffer)
       (Text_buffer_view_internal.raw view) ~x ~y)

let draw_frame_buffer buffer ~source ~x ~y ?(source_x = 0l) ?(source_y = 0l)
    ?(source_width = 0l) ?(source_height = 0l) () =
  map_error
    (Opentui_raw.Buffer.draw_frame_buffer (raw buffer)
       ~source:(Owned_buffer.raw source) ~x ~y ~source_x ~source_y ~source_width
       ~source_height ())

let draw_grid buffer ~border_chars ~border_foreground ~border_background
    ~column_offsets ~row_offsets ~draw_inner ~draw_outer =
  map_error
    (Opentui_raw.Buffer.draw_grid (raw buffer)
       ~border_chars ~border_foreground:(Color.Private.to_raw border_foreground)
       ~border_background:(Color.Private.to_raw border_background)
       ~column_offsets ~row_offsets ~draw_inner ~draw_outer)

let set_cell_with_alpha_blending buffer ~x ~y ~character ~foreground
    ~background ~attributes =
  map_error
    (Opentui_raw.Buffer.set_cell_with_alpha_blending (raw buffer)
       ~x ~y ~character ~foreground:(Color.Private.to_raw foreground)
       ~background:(Color.Private.to_raw background) ~attributes)

let fill_rect buffer ~x ~y ~width ~height ~background =
  map_error
    (Opentui_raw.Buffer.fill_rect (raw buffer)
       ~x ~y ~width ~height ~background:(Color.Private.to_raw background))

let draw_grayscale_buffer_impl buffer ~supersampled ~x ~y ~intensities ~width
    ~height ~foreground ~background =
  if width < 0l || height < 0l then Error Error.Invalid_argument
  else
    let args =
      ( x,
        y,
        intensities,
        width,
        height,
        Option.map Color.Private.to_raw foreground,
        Option.map Color.Private.to_raw background )
    in
    let draw =
      if supersampled then Opentui_raw.Buffer.draw_grayscale_buffer_supersampled
      else Opentui_raw.Buffer.draw_grayscale_buffer
    in
    match draw (raw buffer) args with
    | Ok value -> Ok value
    | Error Opentui_raw.Error.Invalid_argument -> Error Error.Invalid_argument
    | Error error -> map_error (Error error)

let draw_grayscale_buffer buffer ~x ~y ~intensities ~width ~height
    ?foreground ?background () =
  draw_grayscale_buffer_impl buffer ~supersampled:false ~x ~y ~intensities ~width
    ~height ~foreground ~background

let draw_grayscale_buffer_supersampled buffer ~x ~y ~intensities ~width ~height
    ?foreground ?background () =
  draw_grayscale_buffer_impl buffer ~supersampled:true ~x ~y ~intensities ~width
    ~height ~foreground ~background

let write_resolved_chars buffer ~output ~add_line_breaks =
  map_error
    (Opentui_raw.Buffer.write_resolved_chars (raw buffer) ~output
       ~add_line_breaks)

let image_protocol_to_int = function
  | Image.Auto -> 0l
  | Kitty -> 1l
  | Sixel -> 2l
  | Blocks -> 3l

let map_image_error error = Error.Native_image error

let map_raw_draw_error = function
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
    ?(source_x = 0l) ?(source_y = 0l) ?(source_width = 0l)
    ?(source_height = 0l) ?(protocol = Image.Auto) () =
  match
    Image.Private.with_open image (fun image_handle ->
        match
          Opentui_raw.Buffer.draw_image (raw buffer) ~image:image_handle ~x ~y
            ~width ~height ~pixel_width ~pixel_height ~source_x ~source_y
            ~source_width ~source_height
            ~protocol:(image_protocol_to_int protocol)
        with
        | Ok value -> Ok value
        | Error error -> Error (map_raw_draw_error error))
  with
  | Ok value -> Ok value
  | Error error -> Error (map_image_error error)

type color_target = Foreground | Background | Both

let color_target_to_int = function
  | Foreground -> 1
  | Background -> 2
  | Both -> 3

let color_matrix buffer ~matrix ~cell_mask ~strength ~target =
  map_error
    (Opentui_raw.Buffer.color_matrix (raw buffer) ~matrix ~cell_mask ~strength
       ~target:(color_target_to_int target))

let color_matrix_uniform buffer ~matrix ~strength ~target =
  map_error
    (Opentui_raw.Buffer.color_matrix_uniform (raw buffer) ~matrix ~strength
       ~target:(color_target_to_int target))

let push_scissor_rect buffer ~x ~y ~width ~height =
  if width < 0l || height < 0l then Error Error.Invalid_argument
  else
    map_error
      (Opentui_raw.Buffer.push_scissor_rect (raw buffer) ~x ~y ~width ~height)

let pop_scissor_rect buffer =
  map_error (Opentui_raw.Buffer.pop_scissor_rect (raw buffer))

let clear_scissor_rects buffer =
  map_error (Opentui_raw.Buffer.clear_scissor_rects (raw buffer))

let push_opacity buffer opacity =
  if not (Float.is_finite opacity) then Error Error.Invalid_argument
  else
    map_error
      (Opentui_raw.Buffer.push_opacity (raw buffer)
         (Float.max 0.0 (Float.min 1.0 opacity)))

let pop_opacity buffer =
  map_error (Opentui_raw.Buffer.pop_opacity (raw buffer))

let current_opacity buffer =
  map_error (Opentui_raw.Buffer.current_opacity (raw buffer))

let clear_opacity buffer =
  map_error (Opentui_raw.Buffer.clear_opacity (raw buffer))

type snapshot = Opentui_raw.Buffer.snapshot

let snapshot buffer = map_error (Opentui_raw.Buffer.snapshot (raw buffer))
let restore buffer value = map_error (Opentui_raw.Buffer.restore (raw buffer) value)

type cell_snapshot = {
  width : int32;
  height : int32;
  cells : snapshot;
}

let cell_snapshot buffer =
  match width buffer, height buffer, snapshot buffer with
  | Ok width, Ok height, Ok cells -> Ok { width; height; cells }
  | Error error, _, _
  | _, Error error, _
  | _, _, Error error -> Error error
