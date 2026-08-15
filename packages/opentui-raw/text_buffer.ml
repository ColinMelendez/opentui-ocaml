type width_method = Wcwidth | Unicode
type styled_chunk = Native.styled_chunk

type t = {
  handle : Native_token.Text_buffer.t;
  owner : Native_owner.t;
  mutable retained :
    (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t list;
  mutable text_storage :
    (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
    option;
  mutable text_memory_id : int32 option;
  mutable open_views : int;
}

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let create width_method =
  let width_method_code = match width_method with Wcwidth -> 0l | Unicode -> 1l in
  match Native.text_buffer_create width_method_code with
  | 0, handle ->
      Ok
        {
          handle;
          owner = Native_owner.Private.create ();
          retained = [];
          text_storage = None;
          text_memory_id = None;
          open_views = 0;
        }
  | status, _ -> Error (error_of_status status)

let with_open buffer operation =
  if Native_owner.is_open buffer.owner then operation buffer.handle
  else Error Error.Closed

let clear buffer =
  with_open buffer (fun handle ->
      match Native.text_buffer_clear handle with
      | 0 ->
          Ok ()
      | status -> Error (error_of_status status))

let reset buffer =
  with_open buffer (fun handle ->
      match Native.text_buffer_reset handle with
      | 0 ->
          buffer.retained <- [];
          buffer.text_storage <- None;
          buffer.text_memory_id <- None;
          Ok ()
      | status -> Error (error_of_status status))

let set_styled_text buffer chunks =
  with_open buffer (fun handle ->
      match Native.text_buffer_set_styled_text handle chunks with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let clear_all_highlights buffer =
  with_open buffer (fun handle ->
      match Native.text_buffer_clear_all_highlights handle with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

type highlight = {
  start : int32;
  end_ : int32;
  style_id : int32;
  priority : int;
  hl_ref : int;
}

let native_highlight highlight =
  (highlight.start, highlight.end_, highlight.style_id, highlight.priority,
   highlight.hl_ref)

let int32_of_nonnegative value =
  let value64 = Int64.of_int value in
  if value < 0
     || Int64.compare value64 (Int64.of_int32 Int32.max_int) > 0
  then None
  else Some (Int32.of_int value)

let add_highlight_by_char_range buffer highlight =
  with_open buffer (fun handle ->
      match Native.text_buffer_add_highlight_by_char_range handle
              (native_highlight highlight) with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let add_highlight buffer ~line highlight =
  match int32_of_nonnegative line with
  | None -> Error Error.Invalid_argument
  | Some line ->
      with_open buffer (fun handle ->
          match Native.text_buffer_add_highlight handle line
                  (native_highlight highlight) with
          | 0 -> Ok ()
          | status -> Error (error_of_status status))

let remove_highlights_by_ref buffer reference =
  with_open buffer (fun handle ->
      match Native.text_buffer_remove_highlights_by_ref handle reference with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let clear_line_highlights buffer line =
  match int32_of_nonnegative line with
  | None -> Error Error.Invalid_argument
  | Some line ->
      with_open buffer (fun handle ->
          match Native.text_buffer_clear_line_highlights handle line with
          | 0 -> Ok ()
          | status -> Error (error_of_status status))

let set_default_fg buffer color =
  with_open buffer (fun handle ->
      match
        Native.text_buffer_set_default_fg handle
          (Option.map Color.Private.to_native color)
      with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let set_default_bg buffer color =
  with_open buffer (fun handle ->
      match
        Native.text_buffer_set_default_bg handle
          (Option.map Color.Private.to_native color)
      with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let set_default_attributes buffer attributes =
  with_open buffer (fun handle ->
      match Native.text_buffer_set_default_attributes handle attributes with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let reset_defaults buffer =
  with_open buffer (fun handle ->
      match Native.text_buffer_reset_defaults handle with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let set_syntax_style buffer style =
  with_open buffer (fun handle ->
      match
        Native.text_buffer_set_syntax_style handle
          (Option.map Syntax_style.Private.raw style)
      with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let stable_copy bytes =
  let length = Bytes.length bytes in
  let result =
    Bigarray.Array1.create Bigarray.char Bigarray.c_layout length
  in
  for index = 0 to length - 1 do
    Bigarray.Array1.set result index (Bytes.get bytes index)
  done;
  result

let normalized_byte_size bytes =
  let length = Bytes.length bytes in
  let removed = ref 0 in
  let index = ref 0 in
  while !index < length do
    if
      Bytes.get bytes !index = '\r'
      && !index + 1 < length
      && Bytes.get bytes (!index + 1) = '\n'
    then begin
      incr removed;
      index := !index + 2
    end
    else incr index
  done;
  Int32.of_int (length - !removed)

let append buffer bytes =
  with_open buffer (fun handle ->
      if Bytes.length bytes = 0 then Ok ()
      else
        let stable = stable_copy bytes in
        buffer.retained <- stable :: buffer.retained;
        match Native.text_buffer_append handle stable with
        | 0 -> Ok ()
        | status -> Error (error_of_status status))

let set_text buffer bytes =
  with_open buffer (fun handle ->
      let stable = stable_copy bytes in
      let memory_id_result =
        match buffer.text_memory_id with
        | Some memory_id ->
            (match Native.text_buffer_replace_mem_buffer handle memory_id stable
                     false with
            | 0 -> Ok memory_id
            | status when Int.equal status 3 ->
                (match
                   Native.text_buffer_register_mem_buffer handle stable false
                 with
                | 0, memory_id -> Ok memory_id
                | status, _ -> Error (error_of_status status))
            | status -> Error (error_of_status status))
        | None ->
            (match
               Native.text_buffer_register_mem_buffer handle stable false
             with
            | 0, memory_id -> Ok memory_id
            | status, _ -> Error (error_of_status status))
      in
      match memory_id_result with
      | Error error -> Error error
      | Ok memory_id ->
          (match buffer.text_memory_id with
          | Some old_memory_id when not (Int32.equal old_memory_id memory_id) ->
              (match buffer.text_storage with
              | None -> ()
              | Some old_storage ->
                  buffer.retained <- old_storage :: buffer.retained)
          | None | Some _ -> ());
          buffer.text_storage <- Some stable;
          buffer.text_memory_id <- Some memory_id;
          (match
             Native.text_buffer_set_text_from_mem handle memory_id
               (normalized_byte_size bytes)
           with
          | 0 -> Ok ()
          | status ->
              (* The native registry borrows [stable], including when the
                 pinned void setter reports failure through its postcondition. *)
              Error (error_of_status status)))

let length buffer =
  with_open buffer (fun handle ->
      let status, value = Native.text_buffer_length handle in
      match status with
      | 0 -> Ok value
      | status -> Error (error_of_status status))

let byte_size buffer =
  with_open buffer (fun handle ->
      let status, value = Native.text_buffer_byte_size handle in
      match status with
      | 0 -> Ok value
      | status -> Error (error_of_status status))

let line_count buffer =
  with_open buffer (fun handle ->
      let status, value = Native.text_buffer_line_count handle in
      match status with
      | 0 -> Ok value
      | status -> Error (error_of_status status))

let load_file buffer path =
  with_open buffer (fun handle ->
      match Native.text_buffer_load_file handle path with
      | 0 ->
          buffer.text_storage <- None;
          buffer.text_memory_id <- None;
          Ok ()
      | status -> Error (error_of_status status))

let tab_width buffer =
  with_open buffer (fun handle ->
      let status, value = Native.text_buffer_get_tab_width handle in
      match status with
      | 0 -> Ok value
      | status -> Error (error_of_status status))

let set_tab_width buffer width =
  if width < 0l || width > 255l then Error Error.Invalid_argument
  else
    with_open buffer (fun handle ->
        match Native.text_buffer_set_tab_width handle width with
        | 0 -> Ok ()
        | status -> Error (error_of_status status))

let close buffer =
  if not (Native_owner.is_open buffer.owner) then Ok ()
  else if buffer.open_views <> 0 then Error Error.Invalid_argument
  else begin
    Native.text_buffer_destroy buffer.handle;
    buffer.retained <- [];
    buffer.text_storage <- None;
    buffer.text_memory_id <- None;
    Native_owner.Private.close buffer.owner;
    Ok ()
  end

module Private = struct
  let with_open = with_open
  let owner buffer = buffer.owner
  let is_open buffer = Native_owner.is_open buffer.owner
  let register_view buffer = buffer.open_views <- buffer.open_views + 1

  let unregister_view buffer =
    if buffer.open_views > 0 then buffer.open_views <- buffer.open_views - 1
end
