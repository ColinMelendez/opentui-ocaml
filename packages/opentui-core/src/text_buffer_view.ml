type wrap_mode = No_wrap | Char | Word

type measure = {
  line_count : int32;
  width_cols_max : int32;
}

type t = Text_buffer_view_internal.t

let map_error error =
  match error with
  | Opentui_raw.Error.Closed -> Error.Closed
  | error -> Error.Native (Native.Error.Native error)

let map_result result =
  match result with
  | Ok value -> Ok value
  | Error error -> Result.Error (map_error error)

let raw_wrap_mode = function
  | No_wrap -> Opentui_raw.Text_buffer_view.No_wrap
  | Char -> Opentui_raw.Text_buffer_view.Char
  | Word -> Opentui_raw.Text_buffer_view.Word

let create (buffer : Text_buffer.t) =
  match
    Opentui_raw.Text_buffer_view.create
      (Text_buffer_internal.raw (buffer : Text_buffer_internal.t))
  with
  | Error error -> Result.Error (map_error error)
  | Ok view -> Ok (Text_buffer_view_internal.of_raw view)

let raw view = Text_buffer_view_internal.raw view

let set_wrap_width view width =
  map_result
    (Opentui_raw.Text_buffer_view.set_wrap_width (raw view) width)

let set_wrap_mode view mode =
  map_result
    (Opentui_raw.Text_buffer_view.set_wrap_mode (raw view)
       (raw_wrap_mode mode))

let set_first_line_offset view offset =
  map_result
    (Opentui_raw.Text_buffer_view.set_first_line_offset (raw view) offset)

let measure_for_dimensions view ~width ~height =
  match
    Opentui_raw.Text_buffer_view.measure_for_dimensions (raw view) ~width ~height
  with
  | Error error -> Result.Error (map_error error)
  | Ok measure ->
      Ok
        {
          line_count = measure.line_count;
          width_cols_max = measure.width_cols_max;
        }

let close view = map_result (Opentui_raw.Text_buffer_view.close (raw view))
