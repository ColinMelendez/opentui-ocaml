type renderer = {
  handle : Native_token.Renderer.t;
  owner : Native_owner.t;
}

type t = renderer

type render_status = Rendered | Skipped | Failed

type cursor_style = Block | Line | Underline | Default

type mouse_pointer_style =
  | Mouse_default
  | Mouse_pointer
  | Mouse_text
  | Mouse_crosshair
  | Mouse_move
  | Mouse_not_allowed

type cursor_style_options = {
  style : cursor_style option;
  blinking : bool option;
  color : Color.t option;
  cursor : mouse_pointer_style option;
}

type cursor_state = {
  x : int32;
  y : int32;
  visible : bool;
  style : cursor_style;
  blinking : bool;
  color : Color.t;
}

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

let cursor_style_code = function
  | Block -> 0
  | Line -> 1
  | Underline -> 2
  | Default -> 3

let cursor_style_of_code = function
  | 0 -> Ok Block
  | 1 -> Ok Line
  | 2 -> Ok Underline
  | 3 -> Ok Default
  | _ -> Error Error.Native_failure

let mouse_pointer_style_code = function
  | Mouse_default -> 0
  | Mouse_pointer -> 1
  | Mouse_text -> 2
  | Mouse_crosshair -> 3
  | Mouse_move -> 4
  | Mouse_not_allowed -> 5

let set_background_color renderer ~color =
  with_open renderer (fun handle ->
      result_of_status
        (Native.renderer_set_background_color handle (Color.Private.to_native color))
        ())

let set_cursor_position renderer ~x ~y ?(visible = true) () =
  with_open renderer (fun handle ->
      result_of_status
        (Native.renderer_set_cursor_position handle x y visible)
        ())

let set_cursor_color renderer ~color =
  with_open renderer (fun handle ->
      result_of_status
        (Native.renderer_set_cursor_color handle (Color.Private.to_native color))
        ())

let set_cursor_style renderer (options : cursor_style_options) =
  with_open renderer (fun handle ->
      let style = Option.map cursor_style_code options.style in
      let color = Option.map Color.Private.to_native options.color in
      let cursor = Option.map mouse_pointer_style_code options.cursor in
      result_of_status
        (Native.renderer_set_cursor_style_options handle style options.blinking
           color cursor)
        ())

let cursor_state renderer =
  with_open renderer (fun handle ->
      let status, (x, y, visible, style_code, blinking, color) =
        Native.renderer_cursor_state handle
      in
      match Error.Private.of_native_status status with
      | Some error -> Error error
      | None ->
          (match cursor_style_of_code style_code with
          | Error error -> Error error
          | Ok style ->
              let red, green, blue, alpha = color in
              (match Color.rgba ~red ~green ~blue ~alpha with
              | Ok color -> Ok { x; y; visible; style; blinking; color }
              | Error
                  (Error.Invalid_argument
                  | Error.Closed
                  | Error.Stale_handle
                  | Error.Native_failure
                  | Error.Output_too_small
                  | Error.Queue_overflow
                  | Error.No_space
                  | Error.Max_bytes
                  | Error.Busy) -> Error Error.Native_failure)))

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
