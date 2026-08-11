type direction = Inherit | Ltr | Rtl

type layout = {
  left : float;
  top : float;
  right : float;
  bottom : float;
  width : float;
  height : float;
}

type t = {
  handle : Native_token.Yoga_tree.t;
  owner : Native_owner.t;
}

module Node = struct
  type t = {
    handle : Native_token.Yoga_node.t;
    owner : Native_owner.t;
  }

  type edge = Left | Top | Right | Bottom

  let with_open node operation =
    if Native_owner.is_open node.owner then operation ()
    else Error Error.Closed

  let result_of_status status value =
    match status with
    | 0 -> Ok value
    | _ ->
        (match Error.Private.of_native_status status with
        | Some error -> Error error
        | None -> Error Error.Native_failure)

  let set_width node width =
    with_open node (fun () ->
        let status = Native.yoga_node_set_width node.handle width in
        result_of_status status ())

  let set_height node height =
    with_open node (fun () ->
        let status = Native.yoga_node_set_height node.handle height in
        result_of_status status ())

  let edge_code edge =
    match edge with
    | Left -> 0l
    | Top -> 1l
    | Right -> 2l
    | Bottom -> 3l

  let set_padding node ~edge ~value =
    with_open node (fun () ->
        let status =
          Native.yoga_node_set_padding node.handle (edge_code edge) value
        in
        result_of_status status ())

  let layout node =
    with_open node (fun () ->
        let status, native_layout = Native.yoga_node_layout node.handle in
        match status, native_layout with
        | 0, Some (left, top, right, bottom, width, height) ->
            Ok { left; top; right; bottom; width; height }
        | 0, None -> Error Error.Native_failure
        | _, _ ->
            (match Error.Private.of_native_status status with
            | Some error -> Error error
            | None -> Error Error.Native_failure))
end

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let result_of_status status value =
  match status with
  | 0 -> Ok value
  | _ -> Error (error_of_status status)

let create () =
  let status, handle = Native.yoga_create () in
  match status with
  | 0 -> Ok { handle; owner = Native_owner.Private.create () }
  | _ -> Error (error_of_status status)

let close tree =
  if Native_owner.is_open tree.owner then begin
    Native.yoga_destroy tree.handle;
    Native_owner.Private.close tree.owner
  end

let root tree =
  if not (Native_owner.is_open tree.owner) then Error Error.Closed
  else
    let status, handle = Native.yoga_root tree.handle in
    match status with
    | 0 -> Ok { Node.handle; owner = tree.owner }
    | _ -> Error (error_of_status status)

let add_child tree ~parent =
  if not (Native_owner.is_open tree.owner)
     || not (Native_owner.is_open parent.Node.owner)
  then Error Error.Closed
  else
    let status, handle =
      Native.yoga_add_child tree.handle parent.Node.handle
    in
    match status with
    | 0 -> Ok { Node.handle; owner = tree.owner }
    | _ -> Error (error_of_status status)

let remove_child tree ~parent ~child =
  if not (Native_owner.is_open tree.owner)
     || not (Native_owner.is_open parent.Node.owner)
     || not (Native_owner.is_open child.Node.owner)
  then Error Error.Closed
  else
    result_of_status
      (Native.yoga_remove_child tree.handle parent.Node.handle child.Node.handle)
      ()

let move_child tree ~parent ~child ~index =
  if not (Native_owner.is_open tree.owner)
     || not (Native_owner.is_open parent.Node.owner)
     || not (Native_owner.is_open child.Node.owner)
  then Error Error.Closed
  else
    result_of_status
      (Native.yoga_move_child tree.handle parent.Node.handle child.Node.handle
         index)
      ()

let direction_code direction =
  match direction with
  | Inherit -> 0
  | Ltr -> 1
  | Rtl -> 2

let calculate tree ~width ~height ~direction =
  if not (Native_owner.is_open tree.owner) then Error Error.Closed
  else
    let status =
      Native.yoga_calculate tree.handle width height (direction_code direction)
    in
    result_of_status status ()
