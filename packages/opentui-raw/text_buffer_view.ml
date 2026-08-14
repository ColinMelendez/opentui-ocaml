type wrap_mode = No_wrap | Char | Word

type measure = {
  line_count : int32;
  width_cols_max : int32;
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
