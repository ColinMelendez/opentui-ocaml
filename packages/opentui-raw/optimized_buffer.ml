type t = {
  handle : Native_token.Optimized_buffer.t;
  owner : Native_owner.t;
}

type cell = int32 * int32 * int32 * Color.t * Color.t * int32
type text = string * int32 * int32 * Color.t * Color.t * int32

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let result_of_status status value =
  if status = 0 then Ok value else Error (error_of_status status)

let with_open buffer operation =
  if Native_owner.is_open buffer.owner then operation buffer.handle
  else Error Error.Closed

let create ~width ~height ~respect_alpha ~width_method ~id =
  let status, handle =
    Native.Optimized_buffer.create ~width ~height ~respect_alpha ~width_method
      ~id
  in
  match status with
  | 0 -> Ok { handle; owner = Native_owner.Private.create () }
  | status -> Error (error_of_status status)

let width buffer =
  with_open buffer (fun handle ->
      let status, width, _height = Native.Optimized_buffer.dimensions handle in
      result_of_status status width)

let height buffer =
  with_open buffer (fun handle ->
      let status, _width, height = Native.Optimized_buffer.dimensions handle in
      result_of_status status height)

let clear buffer background =
  with_open buffer (fun handle ->
      result_of_status
        (Native.Optimized_buffer.clear handle (Color.Private.to_native background))
        ())

let native_cell (x, y, character, foreground, background, attributes) =
  ( x,
    y,
    character,
    Color.Private.to_native foreground,
    Color.Private.to_native background,
    attributes )

let set_cell buffer cell =
  with_open buffer (fun handle ->
      result_of_status
        (Native.Optimized_buffer.set_cell handle (native_cell cell)) ())

let set_cell_with_alpha_blending buffer cell =
  with_open buffer (fun handle ->
      result_of_status
        (Native.Optimized_buffer.set_cell_with_alpha_blending handle
           (native_cell cell)) ())

let draw_text buffer text =
  with_open buffer (fun handle ->
      let text, x, y, foreground, background, attributes = text in
      result_of_status
        (Native.Optimized_buffer.draw_text handle
           (text, x, y, Color.Private.to_native foreground,
            Color.Private.to_native background, attributes))
        ())

let draw_text_buffer_view buffer view x y =
  with_open buffer (fun handle ->
      Text_buffer_view.Private.with_open view (fun view_handle ->
          result_of_status
            (Native.Optimized_buffer.draw_text_buffer_view handle view_handle x y)
            ()))

let fill_rect buffer rect =
  with_open buffer (fun handle ->
      let x, y, width, height, background = rect in
      result_of_status
        (Native.Optimized_buffer.fill_rect handle
           (x, y, width, height, Color.Private.to_native background))
        ())

let draw_frame_buffer buffer (x, y, source, source_x, source_y, source_width,
    source_height) =
  with_open buffer (fun handle ->
      with_open source (fun source_handle ->
          result_of_status
            (Native.Optimized_buffer.draw_frame_buffer handle
               (x, y, source_handle, source_x, source_y, source_width,
                source_height))
            ()))

let draw_grid buffer (border_chars, border_foreground, border_background,
    column_offsets, row_offsets, draw_inner, draw_outer) =
  with_open buffer (fun handle ->
      result_of_status
        (Native.Optimized_buffer.draw_grid handle
           ( border_chars,
             Color.Private.to_native border_foreground,
             Color.Private.to_native border_background,
             column_offsets,
             row_offsets,
             draw_inner,
             draw_outer ))
        ())

let draw_image buffer args =
  with_open buffer (fun handle ->
      result_of_status (Native.Optimized_buffer.draw_image handle args) ())

let resize buffer width height =
  with_open buffer (fun handle ->
      result_of_status (Native.Optimized_buffer.resize handle width height) ())

type snapshot = Native.buffer_snapshot

let snapshot buffer =
  with_open buffer (fun handle ->
      let status, value = Native.Optimized_buffer.snapshot handle in
      result_of_status status value)

let restore buffer value =
  with_open buffer (fun handle ->
      result_of_status (Native.Optimized_buffer.restore handle value) ())

let close buffer =
  if Native_owner.is_open buffer.owner then begin
    Native.Optimized_buffer.destroy buffer.handle;
    Native_owner.Private.close buffer.owner
  end

module Private = struct
  let with_open = with_open
end
