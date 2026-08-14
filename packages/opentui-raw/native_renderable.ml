type measure_target = Text_buffer_view of Text_buffer_view.t

type t = {
  handle : Native_token.Native_renderable.t;
  owner : Native_owner.t;
  mutable yoga_node : Yoga.Node.t option;
  mutable measure_target : Text_buffer_view.t option;
}

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let create () =
  match Native.native_renderable_create () with
  | 0, handle ->
      Ok
        {
          handle;
          owner = Native_owner.Private.create ();
          yoga_node = None;
          measure_target = None;
        }
  | status, _ -> Error (error_of_status status)

let with_open renderable operation =
  if Native_owner.is_open renderable.owner then operation renderable.handle
  else Error Error.Closed

let release_node_claim node ~measure_attached =
  match
    if measure_attached then
      Yoga.Node.Private.set_native_measure_attached node false
    else Ok ()
  with
  | Error error -> Error error
  | Ok () -> Yoga.Node.Private.release_native_renderable node

let rollback_node_claim node ~measure_attached error =
  match release_node_claim node ~measure_attached with
  | Ok () -> Error error
  | Error cleanup_error -> Error cleanup_error

let native_set_measure_view renderable_handle view =
  Text_buffer_view.Private.with_open view (fun view_handle ->
      match
        Native.native_renderable_set_measure_target renderable_handle 1l
          view_handle
      with
      | 0 -> Ok ()
      | status -> Error (error_of_status status))

let native_clear_measure_target renderable_handle =
  match Native.native_renderable_clear_measure_target renderable_handle with
  | 0 -> Ok ()
  | status -> Error (error_of_status status)

let ensure_measure_node_is_leaf node =
  match Yoga.Node.child_count node with
  | Error error -> Error error
  | Ok count when Int32.equal count 0l -> Ok ()
  | Ok _ -> Error Error.Invalid_argument

let attach_yoga_node renderable node =
  with_open renderable (fun renderable_handle ->
      match renderable.yoga_node with
      | Some _ -> Error Error.Invalid_argument
      | None ->
          let leaf_result =
            match renderable.measure_target with
            | None -> Ok ()
            | Some _ -> ensure_measure_node_is_leaf node
          in
          (match leaf_result with
          | Error error -> Error error
          | Ok () ->
              match Yoga.Node.Private.claim_native_renderable node with
              | Error error -> Error error
              | Ok () ->
                  let measure_attached =
                    match renderable.measure_target with
                    | None -> false
                    | Some _ -> true
                  in
                  let mark_result =
                    if measure_attached then
                      Yoga.Node.Private.set_native_measure_attached node true
                    else Ok ()
                  in
                  match mark_result with
                  | Error error ->
                      rollback_node_claim node ~measure_attached:false error
                  | Ok () ->
                      let native_result =
                        Yoga.Node.Private.with_open_handle node
                          (fun node_handle ->
                            match
                              Native.native_renderable_attach_yoga_node
                                renderable_handle node_handle
                            with
                            | 0 -> Ok ()
                            | status -> Error (error_of_status status))
                      in
                      match native_result with
                      | Error error ->
                          rollback_node_claim node ~measure_attached error
                      | Ok () ->
                          renderable.yoga_node <- Some node;
                          Ok ()))

let set_measure_target renderable target =
  with_open renderable (fun renderable_handle ->
      match target with
      | Text_buffer_view view ->
          match Text_buffer_view.Private.claim_measure_user view with
          | Error error -> Error error
          | Ok () ->
              let release_new_view error =
                Text_buffer_view.Private.release_measure_user view;
                Error error
              in
              let leaf_result =
                match renderable.yoga_node with
                | None -> Ok ()
                | Some node -> ensure_measure_node_is_leaf node
              in
              match leaf_result with
              | Error error -> release_new_view error
              | Ok () ->
                  let old_target = renderable.measure_target in
                  match native_set_measure_view renderable_handle view with
                  | Error error -> release_new_view error
                  | Ok () ->
                      let mark_result =
                        match renderable.yoga_node with
                        | None -> Ok ()
                        | Some node ->
                            Yoga.Node.Private.set_native_measure_attached node
                              true
                      in
                      match mark_result with
                      | Ok () ->
                          (match old_target with
                          | None -> ()
                          | Some old_view ->
                              Text_buffer_view.Private.release_measure_user
                                old_view);
                          renderable.measure_target <- Some view;
                          Ok ()
                      | Error error ->
                          let restore_result =
                            match old_target with
                            | None ->
                                native_clear_measure_target renderable_handle
                            | Some old_view ->
                                native_set_measure_view renderable_handle
                                  old_view
                          in
                          Text_buffer_view.Private.release_measure_user view;
                          (match restore_result with
                          | Ok () -> Error error
                          | Error restore_error -> Error restore_error))

let clear_measure_target renderable =
  with_open renderable (fun renderable_handle ->
      match native_clear_measure_target renderable_handle with
      | Error error -> Error error
      | Ok () ->
          let mark_result =
            match renderable.yoga_node with
            | None -> Ok ()
            | Some node ->
                Yoga.Node.Private.set_native_measure_attached node false
          in
          (match renderable.measure_target with
          | None -> ()
          | Some view -> Text_buffer_view.Private.release_measure_user view);
          renderable.measure_target <- None;
          mark_result)

let close renderable =
  if not (Native_owner.is_open renderable.owner) then Ok ()
  else
    match clear_measure_target renderable with
    | Error error -> Error error
    | Ok () ->
        (match renderable.yoga_node with
        | None ->
            Native.native_renderable_destroy renderable.handle;
            Native_owner.Private.close renderable.owner;
            Ok ()
        | Some node ->
            (match Yoga.Node.Private.release_native_renderable node with
            | Error error -> Error error
            | Ok () ->
                renderable.yoga_node <- None;
                Native.native_renderable_destroy renderable.handle;
                Native_owner.Private.close renderable.owner;
                Ok ()))

module Private = struct
  let with_open = with_open
end
