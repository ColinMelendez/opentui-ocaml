type t = {
  handle : Native_token.Event_sink.t;
  owner : Native_owner.t;
}

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let create () =
  let status, handle = Native.event_sink_create () in
  match status with
  | 0 -> Ok { handle; owner = Native_owner.Private.create () }
  | _ -> Error (error_of_status status)

let close sink =
  if Native_owner.is_open sink.owner then begin
    Native.event_sink_destroy sink.handle;
    Native_owner.Private.close sink.owner
  end

let poll sink =
  if not (Native_owner.is_open sink.owner) then Error Error.Closed
  else
    let status, event = Native.event_sink_poll sink.handle in
    match status with
    | 0 ->
        (match event with
        | None -> Ok None
        | Some (name, data) -> Ok (Some (Event.Private.of_native name data)))
    | _ -> Error (error_of_status status)
