type t = {
  handle : Native_token.Renderer.t;
  owner : Native_owner.t;
}

type render_status = Rendered | Skipped | Failed

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let create ~width ~height =
  let status, handle = Native.renderer_create width height in
  match status with
  | 0 -> Ok { handle; owner = Native_owner.Private.create () }
  | _ -> Error (error_of_status status)

let resize renderer ~width ~height =
  if not (Native_owner.is_open renderer.owner) then Error Error.Closed
  else
    match Native.renderer_resize renderer.handle width height with
    | 0 -> Ok ()
    | status -> Error (error_of_status status)

let close renderer =
  if Native_owner.is_open renderer.owner then begin
    Native.renderer_destroy renderer.handle;
    Native_owner.Private.close renderer.owner
  end

let buffer renderer ~next =
  if not (Native_owner.is_open renderer.owner) then Error Error.Closed
  else
    let status, handle = Native.renderer_buffer renderer.handle next in
    match status with
    | 0 -> Ok (Buffer.Private.of_native handle renderer.owner)
    | _ -> Error (error_of_status status)

let current_buffer renderer = buffer renderer ~next:false
let next_buffer renderer = buffer renderer ~next:true

let render renderer ~force =
  if not (Native_owner.is_open renderer.owner) then Error Error.Closed
  else
    match Native.renderer_render renderer.handle force with
    | 0 -> Ok Rendered
    | 1 -> Ok Skipped
    | 2 -> Ok Failed
    | status -> Error (error_of_status status)

module Private = struct
  let with_open renderer operation =
    if Native_owner.is_open renderer.owner then operation renderer.handle
    else Error Error.Closed
end
