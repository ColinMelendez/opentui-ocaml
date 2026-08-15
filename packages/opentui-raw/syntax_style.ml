type t = {
  handle : Native_token.Syntax_style.t;
  owner : Native_owner.t;
}

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let create () =
  match Native.syntax_style_create () with
  | 0, handle -> Ok { handle; owner = Native_owner.Private.create () }
  | status, _ -> Error (error_of_status status)

let with_open style operation =
  if Native_owner.is_open style.owner then operation style.handle
  else Error Error.Closed

let register_style style ~name ~fg ~bg ~attributes =
  with_open style (fun handle ->
      match Native.syntax_style_register handle name fg bg attributes with
      | 0, style_id -> Ok style_id
      | status, _ -> Error (error_of_status status))

let resolve_style style name =
  with_open style (fun handle ->
      match Native.syntax_style_resolve handle name with
      | 0, style_id -> Ok (if Int32.equal style_id 0l then None else Some style_id)
      | status, _ -> Error (error_of_status status))

let style_count style =
  with_open style (fun handle ->
      match Native.syntax_style_count handle with
      | 0, count -> Ok count
      | status, _ -> Error (error_of_status status))

let close style =
  if not (Native_owner.is_open style.owner) then Ok ()
  else begin
    Native.syntax_style_destroy style.handle;
    Native_owner.Private.close style.owner;
    Ok ()
  end

module Private = struct
  let raw style = style.handle
  let with_open = with_open
  let is_open style = Native_owner.is_open style.owner
end
