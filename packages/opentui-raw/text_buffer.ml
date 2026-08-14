type width_method = Wcwidth | Unicode

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
            | status when status = 3 ->
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
