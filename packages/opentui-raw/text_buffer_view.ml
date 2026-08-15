type wrap_mode = No_wrap | Char | Word

type measure = {
  line_count : int32;
  width_cols_max : int32;
}

type line_info = {
  line_start_cols : int32 array;
  line_width_cols : int32 array;
  line_width_cols_max : int32;
  line_sources : int32 array;
  line_wraps : int32 array;
}

type selection = {
  start : int;
  end_ : int;
}

type t = {
  handle : Native_token.Text_buffer_view.t;
  owner : Native_owner.t;
  buffer : Text_buffer.t;
  mutable measure_users : int;
}

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let create buffer =
  match
    Text_buffer.Private.with_open buffer (fun buffer_handle ->
        match Native.text_buffer_view_create buffer_handle with
        | 0, handle -> Ok handle
        | status, _ -> Error (error_of_status status))
  with
  | Error error -> Error error
  | Ok handle ->
      Text_buffer.Private.register_view buffer;
      Ok
        {
          handle;
          owner = Native_owner.Private.create ();
          buffer;
          measure_users = 0;
        }

let with_open view operation =
  if not (Text_buffer.Private.is_open view.buffer) then Error Error.Closed
  else if not (Native_owner.is_open view.owner) then Error Error.Closed
  else operation view.handle

let set_wrap_width view width =
  let native_width = Option.value width ~default:0l in
  if native_width < 0l then Error Error.Invalid_argument
  else
    with_open view (fun handle ->
        match Native.text_buffer_view_set_wrap_width handle native_width with
        | 0 -> Ok ()
        | status -> Error (error_of_status status))

let wrap_mode_code = function No_wrap -> 0l | Char -> 1l | Word -> 2l

let set_wrap_mode view mode =
  with_open view (fun handle ->
      match
        Native.text_buffer_view_set_wrap_mode handle (wrap_mode_code mode)
      with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let set_first_line_offset view offset =
  if offset < 0l then Error Error.Invalid_argument
  else
    with_open view (fun handle ->
        match Native.text_buffer_view_set_first_line_offset handle offset with
        | 0 -> Ok ()
        | status -> Error (error_of_status status))

let normalize_range start finish =
  if start <= finish then start, finish else finish, start

let int32_of_int value =
  let value = Int64.of_int value in
  if Int64.compare value (Int64.of_int32 Int32.min_int) < 0
     || Int64.compare value (Int64.of_int32 Int32.max_int) > 0
  then None
  else Some (Int32.of_int (Int64.to_int value))

let int32_of_nonnegative value =
  match int32_of_int value with
  | Some value when Int32.compare value 0l >= 0 -> Some value
  | Some _ | None -> None

let set_selection view ~start ~end_ ?bg_color ?fg_color () =
  match int32_of_nonnegative start, int32_of_nonnegative end_ with
  | Some start, Some end_ ->
      let start, end_ = normalize_range start end_ in
      with_open view (fun handle ->
          match
            Native.text_buffer_view_set_selection handle start end_ bg_color
              fg_color
          with
          | 0 -> Ok ()
          | status -> Error (error_of_status status))
  | None, _ | _, None -> Error Error.Invalid_argument

let update_selection view ~end_ ?bg_color ?fg_color () =
  match int32_of_nonnegative end_ with
  | None -> Error Error.Invalid_argument
  | Some end_ ->
      with_open view (fun handle ->
          match
            Native.text_buffer_view_update_selection handle end_ bg_color
              fg_color
          with
          | 0 -> Ok ()
          | status -> Error (error_of_status status))

let reset_selection view =
  with_open view (fun handle ->
      match Native.text_buffer_view_reset_selection handle with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let selection view =
  with_open view (fun handle ->
      let packed = Native.text_buffer_view_get_selection_info handle in
      if Int64.equal packed (-1L) then Ok None
      else
        let start = Int64.to_int (Int64.shift_right_logical packed 32) in
        let end_ = Int64.to_int (Int64.logand packed 0xffff_ffffL) in
        Ok (Some { start; end_ }))

let set_local_selection view ~anchor_x ~anchor_y ~focus_x ~focus_y ?bg_color
    ?fg_color () =
  match
    int32_of_int anchor_x, int32_of_int anchor_y, int32_of_int focus_x,
    int32_of_int focus_y
  with
  | Some anchor_x, Some anchor_y, Some focus_x, Some focus_y ->
      with_open view (fun handle ->
          match
            Native.text_buffer_view_set_local_selection handle
              (anchor_x, anchor_y, focus_x, focus_y, bg_color, fg_color)
          with
          | 0, changed -> Ok changed
          | status, _ -> Error (error_of_status status))
  | _ -> Error Error.Invalid_argument

let update_local_selection view ~anchor_x ~anchor_y ~focus_x ~focus_y ?bg_color
    ?fg_color () =
  match
    int32_of_int anchor_x, int32_of_int anchor_y, int32_of_int focus_x,
    int32_of_int focus_y
  with
  | Some anchor_x, Some anchor_y, Some focus_x, Some focus_y ->
      with_open view (fun handle ->
          match
            Native.text_buffer_view_update_local_selection handle
              (anchor_x, anchor_y, focus_x, focus_y, bg_color, fg_color)
          with
          | 0, changed -> Ok changed
          | status, _ -> Error (error_of_status status))
  | _ -> Error Error.Invalid_argument

let reset_local_selection view =
  with_open view (fun handle ->
      match Native.text_buffer_view_reset_local_selection handle with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let selected_text view ~capacity =
  match int32_of_nonnegative capacity with
  | None -> Error Error.Invalid_argument
  | Some native_capacity ->
      with_open view (fun handle ->
          let output = Bytes.create capacity in
          match
            Native.text_buffer_view_get_selected_text handle output
              native_capacity
          with
          | 0, length ->
              Ok (Bytes.to_string (Bytes.sub output 0 (Int32.to_int length)))
          | status, _ -> Error (error_of_status status))

let set_viewport_size view ~width ~height =
  if width < 0l || height < 0l then Error Error.Invalid_argument
  else
    with_open view (fun handle ->
        match Native.text_buffer_view_set_viewport_size handle width height with
        | 0 -> Ok ()
        | status -> Error (error_of_status status))

let set_viewport view ~x ~y ~width ~height =
  if x < 0l || y < 0l || width < 0l || height < 0l then
    Error Error.Invalid_argument
  else
    with_open view (fun handle ->
        match
          Native.text_buffer_view_set_viewport handle x y width height
        with
        | 0 -> Ok ()
        | status -> Error (error_of_status status))

let virtual_line_count view =
  with_open view (fun handle ->
      match Native.text_buffer_view_get_virtual_line_count handle with
      | 0, count -> Ok (Int32.to_int count)
      | status, _ -> Error (error_of_status status))

let set_tab_indicator view indicator =
  if indicator < 0l then Error Error.Invalid_argument
  else
    with_open view (fun handle ->
        match Native.text_buffer_view_set_tab_indicator handle indicator with
        | 0 -> Ok ()
        | status -> Error (error_of_status status))

let set_tab_indicator_color view color =
  with_open view (fun handle ->
      match Native.text_buffer_view_set_tab_indicator_color handle color with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let set_truncate view truncate =
  with_open view (fun handle ->
      match Native.text_buffer_view_set_truncate handle truncate with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let measure_for_dimensions view ~width ~height =
  if width < 0l || height < 0l then Error Error.Invalid_argument
  else
    with_open view (fun handle ->
        let status, line_count, width_cols_max =
          Native.text_buffer_view_measure_for_dimensions handle width height
        in
        match status with
        | 0 -> Ok { line_count; width_cols_max }
        | status -> Error (error_of_status status))

let line_info_result result =
  let status, line_start_cols, line_width_cols, line_sources, line_wraps,
      line_width_cols_max = result
  in
  match status with
  | 0 ->
      Ok
        {
          line_start_cols;
          line_width_cols;
          line_width_cols_max;
          line_sources;
          line_wraps;
        }
  | status -> Error (error_of_status status)

let line_info view =
  with_open view (fun handle ->
      line_info_result (Native.text_buffer_view_get_line_info handle))

let logical_line_info view =
  with_open view (fun handle ->
      line_info_result (Native.text_buffer_view_get_logical_line_info handle))

let close view =
  if not (Native_owner.is_open view.owner) then Ok ()
  else if view.measure_users <> 0 then Error Error.Invalid_argument
  else begin
    if Text_buffer.Private.is_open view.buffer then
      Native.text_buffer_view_destroy view.handle;
    Text_buffer.Private.unregister_view view.buffer;
    Native_owner.Private.close view.owner;
    Ok ()
  end

module Private = struct
  let with_open = with_open

  let claim_measure_user view =
    if not (Native_owner.is_open view.owner) then Error Error.Closed
    else begin
      view.measure_users <- view.measure_users + 1;
      Ok ()
    end

  let release_measure_user view =
    if view.measure_users > 0 then view.measure_users <- view.measure_users - 1
end
