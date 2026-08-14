type t = {
  handle : Native_token.Buffer.t;
  owner : Native_owner.t;
}

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let result_of_status status value =
  match status with
  | 0 -> Ok value
  | _ -> Error (error_of_status status)

let with_open buffer operation =
  if Native_owner.is_open buffer.owner then operation () else Error Error.Closed

let width buffer =
  with_open buffer (fun () ->
      let status, width, _height = Native.buffer_dimensions buffer.handle in
      result_of_status status width)

let height buffer =
  with_open buffer (fun () ->
      let status, _width, height = Native.buffer_dimensions buffer.handle in
      result_of_status status height)

let clear buffer ~background =
  with_open buffer (fun () ->
      let status =
        Native.buffer_clear buffer.handle (Color.Private.to_native background)
      in
      result_of_status status ())

let set_cell buffer ~x ~y ~character ~foreground ~background ~attributes =
  with_open buffer (fun () ->
      let cell =
        ( x,
          y,
          character,
          Color.Private.to_native foreground,
          Color.Private.to_native background,
          attributes )
      in
      let status = Native.buffer_set_cell buffer.handle cell in
      result_of_status status ())

let draw_text buffer ~text ~x ~y ~foreground ~background ~attributes =
  with_open buffer (fun () ->
      let drawing =
        ( text,
          x,
          y,
          Color.Private.to_native foreground,
          Color.Private.to_native background,
          attributes )
      in
      let status = Native.buffer_draw_text buffer.handle drawing in
      result_of_status status ())

let draw_text_buffer_view buffer view ~x ~y =
  with_open buffer (fun () ->
      Text_buffer_view.Private.with_open view (fun view_handle ->
          let status =
            Native.buffer_draw_text_buffer_view buffer.handle view_handle x y
          in
          result_of_status status ()))

let write_resolved_chars buffer ~output ~add_line_breaks =
  with_open buffer (fun () ->
      let status, count =
        Native.buffer_write_resolved_chars buffer.handle output add_line_breaks
      in
      result_of_status status count)

module Private = struct
  let of_native handle owner = { handle; owner }
end
