type width_method = Wcwidth | Unicode

type t = Text_buffer_internal.t

let raw buffer = Text_buffer_internal.raw buffer

let map_error error =
  match error with
  | Opentui_raw.Error.Closed -> Error.Closed
  | error -> Error.Native (Native.Error.Native error)

let map_result result =
  match result with
  | Ok value -> Ok value
  | Error error -> Result.Error (map_error error)

let raw_width_method = function
  | Wcwidth -> Opentui_raw.Text_buffer.Wcwidth
  | Unicode -> Opentui_raw.Text_buffer.Unicode

let create width_method =
  match
    Opentui_raw.Text_buffer.create (raw_width_method width_method)
  with
  | Error error -> Result.Error (map_error error)
  | Ok buffer -> Ok (Text_buffer_internal.of_raw buffer)

let clear buffer = map_result (Opentui_raw.Text_buffer.clear (raw buffer))

let append buffer text =
  map_result
    (Opentui_raw.Text_buffer.append (raw buffer) (Bytes.of_string text))

let set_text buffer text =
  map_result
    (Opentui_raw.Text_buffer.set_text (raw buffer) (Bytes.of_string text))

let length buffer = map_result (Opentui_raw.Text_buffer.length (raw buffer))
let byte_size buffer = map_result (Opentui_raw.Text_buffer.byte_size (raw buffer))
let close buffer = map_result (Opentui_raw.Text_buffer.close (raw buffer))
