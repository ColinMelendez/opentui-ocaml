type t = Opentui_raw.Native_renderable.t

let map_error error =
  match error with
  | Opentui_raw.Error.Closed -> Error.Closed
  | error -> Error.Native (Native.Error.Native error)

let map_result result =
  match result with
  | Ok value -> Ok value
  | Error error -> Result.Error (map_error error)

let map_native_result result =
  match result with
  | Ok value -> Ok value
  | Error Native.Error.Closed -> Result.Error Error.Closed
  | Error (Native.Error.Native error) ->
      Result.Error (Error.Native (Native.Error.Native error))

let create () = map_result (Opentui_raw.Native_renderable.create ())

let attach_yoga_node renderable node =
  map_native_result
    (Yoga.Node.Private.attach_native_renderable node renderable)

let set_measure_target renderable view =
  map_result
    (Opentui_raw.Native_renderable.set_measure_target renderable
       (Opentui_raw.Native_renderable.Text_buffer_view
          (Text_buffer_view_internal.raw
             (view : Text_buffer_view_internal.t))))

let close renderable = map_result (Opentui_raw.Native_renderable.close renderable)
