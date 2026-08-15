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

let draw_box buffer ~x ~y ~width ~height ~border_chars ~packed_options
    ~border_color ~background_color ~title_color ~title ~bottom_title =
  with_open buffer (fun () ->
      let drawing =
        ( x,
          y,
          width,
          height,
          border_chars,
          packed_options,
          Color.Private.to_native border_color,
          Color.Private.to_native background_color,
          Color.Private.to_native title_color,
          title,
          bottom_title )
      in
      let status = Native.buffer_draw_box buffer.handle drawing in
      result_of_status status ())

let draw_text_buffer_view buffer view ~x ~y =
  with_open buffer (fun () ->
      Text_buffer_view.Private.with_open view (fun view_handle ->
          let status =
            Native.buffer_draw_text_buffer_view buffer.handle view_handle x y
          in
          result_of_status status ()))

let set_cell_with_alpha_blending buffer ~x ~y ~character ~foreground ~background
    ~attributes =
  with_open buffer (fun () ->
      let cell =
        ( x,
          y,
          character,
          Color.Private.to_native foreground,
          Color.Private.to_native background,
          attributes )
      in
      result_of_status
        (Native.buffer_set_cell_with_alpha_blending buffer.handle cell) ())

let fill_rect buffer ~x ~y ~width ~height ~background =
  with_open buffer (fun () ->
      result_of_status
        (Native.buffer_fill_rect buffer.handle
           (x, y, width, height, Color.Private.to_native background))
        ())

let draw_frame_buffer buffer ~source ~x ~y ?(source_x = 0l) ?(source_y = 0l)
    ?(source_width = 0l) ?(source_height = 0l) () =
  with_open buffer (fun () ->
      Optimized_buffer.Private.with_open source (fun source_handle ->
          result_of_status
            (Native.buffer_draw_frame_buffer buffer.handle
               (x, y, source_handle, source_x, source_y, source_width,
                source_height))
            ()))

let draw_grid buffer ~border_chars ~border_foreground ~border_background
    ~column_offsets ~row_offsets ~draw_inner ~draw_outer =
  with_open buffer (fun () ->
      result_of_status
        (Native.buffer_draw_grid buffer.handle
           ( border_chars,
             Color.Private.to_native border_foreground,
             Color.Private.to_native border_background,
             column_offsets,
             row_offsets,
             draw_inner,
             draw_outer ))
        ())

let write_resolved_chars buffer ~output ~add_line_breaks =
  with_open buffer (fun () ->
      let status, count =
        Native.buffer_write_resolved_chars buffer.handle output add_line_breaks
      in
      result_of_status status count)

let draw_image buffer ~image ~x ~y ~width ~height ~pixel_width ~pixel_height
    ~source_x ~source_y ~source_width ~source_height ~protocol =
  with_open buffer (fun () ->
      result_of_status
        (Native.buffer_draw_image buffer.handle
           ( x,
             y,
             width,
             height,
             pixel_width,
             pixel_height,
             source_x,
             source_y,
             source_width,
             source_height,
             protocol,
             image ))
        ())

let color_matrix buffer ~matrix ~cell_mask ~strength ~target =
  with_open buffer (fun () ->
      result_of_status
        (Native.buffer_color_matrix buffer.handle matrix cell_mask strength
           target)
        ())

let color_matrix_uniform buffer ~matrix ~strength ~target =
  with_open buffer (fun () ->
      result_of_status
        (Native.buffer_color_matrix_uniform buffer.handle matrix strength target)
        ())

let push_scissor_rect buffer ~x ~y ~width ~height =
  with_open buffer (fun () ->
      result_of_status
        (Native.buffer_push_scissor_rect buffer.handle (x, y, width, height))
        ())

let pop_scissor_rect buffer =
  with_open buffer (fun () ->
      result_of_status (Native.buffer_pop_scissor_rect buffer.handle) ())

let clear_scissor_rects buffer =
  with_open buffer (fun () ->
      result_of_status (Native.buffer_clear_scissor_rects buffer.handle) ())

let push_opacity buffer opacity =
  with_open buffer (fun () ->
      result_of_status (Native.buffer_push_opacity buffer.handle opacity) ())

let pop_opacity buffer =
  with_open buffer (fun () ->
      result_of_status (Native.buffer_pop_opacity buffer.handle) ())

let current_opacity buffer =
  with_open buffer (fun () -> Ok (Native.buffer_get_current_opacity buffer.handle))

let clear_opacity buffer =
  with_open buffer (fun () ->
      result_of_status (Native.buffer_clear_opacity buffer.handle) ())

type snapshot = Native.buffer_snapshot

let snapshot buffer =
  with_open buffer (fun () ->
      let status, value = Native.buffer_snapshot buffer.handle in
      result_of_status status value)

let restore buffer value =
  with_open buffer (fun () ->
      result_of_status (Native.buffer_restore buffer.handle value) ())

module Private = struct
  let of_native handle owner = { handle; owner }
end
