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

let draw_text_buffer buffer ~view ~x ~y =
  map_error
    (Opentui_raw.Buffer.draw_text_buffer_view (raw buffer)
       (Text_buffer_view_internal.raw view) ~x ~y)

let write_resolved_chars buffer ~output ~add_line_breaks =
  map_error
    (Opentui_raw.Buffer.write_resolved_chars (raw buffer) ~output
       ~add_line_breaks)
