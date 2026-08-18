type renderer = {
  handle : Native_token.Renderer.t;
  owner : Native_owner.t;
}

type t = renderer

type render_status = Rendered | Skipped | Failed

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let result_of_status status value =
  match Error.Private.of_native_status status with
  | None -> Ok value
  | Some error -> Error error

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

let with_open renderer operation =
  if Native_owner.is_open renderer.owner then operation renderer.handle
  else Error Error.Closed

module Hit_grid = struct
  type t = { renderer : renderer }

  let with_open hit_grid operation = with_open hit_grid.renderer operation

  let add_to_hit_grid hit_grid ~x ~y ~width ~height ~id =
    with_open hit_grid (fun handle ->
        if width < 0l || height < 0l || id < 0l then
          Error Error.Invalid_argument
        else
          result_of_status
            (Native.renderer_add_to_hit_grid handle x y width height id)
            ())

  let clear_current_hit_grid hit_grid =
    with_open hit_grid (fun handle ->
        result_of_status
          (Native.renderer_clear_current_hit_grid handle)
          ())

  let clear_next_hit_grid hit_grid =
    with_open hit_grid (fun handle ->
        result_of_status (Native.renderer_clear_next_hit_grid handle) ())

  let hit_grid_push_scissor_rect hit_grid ~x ~y ~width ~height =
    with_open hit_grid (fun handle ->
        if width < 0l || height < 0l then Error Error.Invalid_argument
        else
          result_of_status
            (Native.renderer_hit_grid_push_scissor_rect handle x y width
               height)
            ())

  let hit_grid_pop_scissor_rect hit_grid =
    with_open hit_grid (fun handle ->
        result_of_status
          (Native.renderer_hit_grid_pop_scissor_rect handle)
          ())

  let hit_grid_clear_scissor_rects hit_grid =
    with_open hit_grid (fun handle ->
        result_of_status
          (Native.renderer_hit_grid_clear_scissor_rects handle)
          ())

  let add_to_current_hit_grid_clipped hit_grid ~x ~y ~width ~height ~id =
    with_open hit_grid (fun handle ->
        if width < 0l || height < 0l || id < 0l then
          Error Error.Invalid_argument
        else
          result_of_status
            (Native.renderer_add_to_current_hit_grid_clipped handle x y width
               height id)
            ())

  let check_hit hit_grid ~x ~y =
    with_open hit_grid (fun handle ->
        if x < 0l || y < 0l then Error Error.Invalid_argument
        else
          let status, id = Native.renderer_check_hit handle x y in
          result_of_status status id)

  let get_hit_grid_dirty hit_grid =
    with_open hit_grid (fun handle ->
        let status, dirty = Native.renderer_get_hit_grid_dirty handle in
        result_of_status status dirty)

  module Private = struct
    let add_to_hit_grid_unchecked hit_grid ~x ~y ~width ~height ~id =
      Native.renderer_add_to_hit_grid_unchecked hit_grid.renderer.handle x y
        width height id

    let clear_current_hit_grid_unchecked hit_grid =
      Native.renderer_clear_current_hit_grid_unchecked hit_grid.renderer.handle

    let clear_next_hit_grid_unchecked hit_grid =
      Native.renderer_clear_next_hit_grid_unchecked hit_grid.renderer.handle

    let hit_grid_push_scissor_rect_unchecked hit_grid ~x ~y ~width ~height =
      Native.renderer_hit_grid_push_scissor_rect_unchecked
        hit_grid.renderer.handle x y width height

    let hit_grid_pop_scissor_rect_unchecked hit_grid =
      Native.renderer_hit_grid_pop_scissor_rect_unchecked hit_grid.renderer.handle

    let hit_grid_clear_scissor_rects_unchecked hit_grid =
      Native.renderer_hit_grid_clear_scissor_rects_unchecked
        hit_grid.renderer.handle

    let add_to_current_hit_grid_clipped_unchecked hit_grid ~x ~y ~width ~height
        ~id =
      Native.renderer_add_to_current_hit_grid_clipped_unchecked
        hit_grid.renderer.handle x y width height id

    let check_hit_unchecked hit_grid ~x ~y =
      Native.renderer_check_hit_unchecked hit_grid.renderer.handle x y

    let get_hit_grid_dirty_unchecked hit_grid =
      Native.renderer_get_hit_grid_dirty_unchecked hit_grid.renderer.handle
  end
end

let hit_grid renderer = { Hit_grid.renderer }

module Private = struct
  let with_open = with_open
end
