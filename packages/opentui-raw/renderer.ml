type renderer = {
  handle : Native_token.Renderer.t;
  owner : Native_owner.t;
  feed : Span_feed.t option;
}

type t = renderer

type output = Memory | Stdout | Feed of Span_feed.t

type remote_mode = Auto | Local | Remote

type render_status = Rendered | Skipped | Failed

type split_footer_transition = Viewport_scroll | Clear_stale_rows

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

let remote_mode_code = function
  | Auto -> 0
  | Local -> 1
  | Remote -> 2

let create ?(output = Memory) ?(remote_mode = Auto) ~width ~height () =
  let create_native destination native_feed owner_feed =
    let status, handle =
      Native.renderer_create
        width height destination (remote_mode_code remote_mode) native_feed
    in
    match status with
    | 0 -> Ok { handle; owner = Native_owner.Private.create (); feed = owner_feed }
    | _ -> Error (error_of_status status)
  in
  match output with
  | Memory -> create_native 1 None None
  | Stdout -> create_native 0 None None
  | Feed feed ->
      (match Span_feed.Private.raw feed with
       | Error error -> Error error
       | Ok token ->
           create_native 1 (Some token) (Some feed))

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

let drain_output renderer =
  match renderer.feed with
  | None -> Ok []
  | Some feed -> Span_feed.drain feed

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

let write_out renderer bytes =
  with_open renderer (fun handle ->
      result_of_status (Native.renderer_write_out handle bytes) ())

let query_terminal_capabilities renderer =
  with_open renderer (fun handle ->
      result_of_status (Native.renderer_query_terminal_capabilities handle) ())

let trigger_notification renderer ~message ~title =
  with_open renderer (fun handle ->
      let status, triggered =
        Native.renderer_trigger_notification handle message title
      in
      result_of_status status triggered)

let render_status_of_code = function
  | 0 -> Ok Rendered
  | 1 -> Ok Skipped
  | 2 -> Ok Failed
  | status -> Error (error_of_status status)

let split_render_result (status, offset) =
  match render_status_of_code status with
  | Error error -> Error error
  | Ok render_status -> Ok (offset, render_status)

let set_render_offset renderer ~offset =
  if Int32.compare offset 0l < 0 then Error Error.Invalid_argument
  else
    with_open renderer (fun handle ->
        result_of_status (Native.renderer_set_render_offset handle offset) ())

let reset_split_scrollback renderer ~seed_rows ~pinned_render_offset =
  if Int32.compare seed_rows 0l < 0
     || Int32.compare pinned_render_offset 0l < 0
  then Error Error.Invalid_argument
  else
    with_open renderer (fun handle ->
        let status, offset =
          Native.renderer_reset_split_scrollback handle seed_rows
            pinned_render_offset
        in
        result_of_status status offset)

let sync_split_scrollback renderer ~pinned_render_offset =
  if Int32.compare pinned_render_offset 0l < 0 then Error Error.Invalid_argument
  else
    with_open renderer (fun handle ->
        let status, offset =
          Native.renderer_sync_split_scrollback handle pinned_render_offset
        in
        result_of_status status offset)

let get_split_output_offset renderer ~surface_offset =
  if Int32.compare surface_offset 0l < 0 then Error Error.Invalid_argument
  else
    with_open renderer (fun handle ->
        let status, offset =
          Native.renderer_get_split_output_offset handle surface_offset
        in
        result_of_status status offset)

let set_pending_split_footer_transition renderer mode ~source_top_line
    ~source_height ~target_top_line ~target_height ~scroll_lines =
  let mode_code =
    match mode with Viewport_scroll -> 1l | Clear_stale_rows -> 2l
  in
  if Int32.compare source_top_line 0l < 0
     || Int32.compare source_height 0l < 0
     || Int32.compare target_top_line 0l < 0
     || Int32.compare target_height 0l < 0
     || Int32.compare scroll_lines 0l < 0
  then Error Error.Invalid_argument
  else
    with_open renderer (fun handle ->
        result_of_status
          (Native.renderer_set_pending_split_footer_transition handle
             (mode_code, source_top_line, source_height, target_top_line,
              target_height, scroll_lines))
          ())

let clear_pending_split_footer_transition renderer =
  with_open renderer (fun handle ->
      result_of_status
        (Native.renderer_clear_pending_split_footer_transition handle) ())

let repaint_split_footer renderer ~pinned_render_offset ~force =
  if Int32.compare pinned_render_offset 0l < 0 then Error Error.Invalid_argument
  else
    with_open renderer (fun handle ->
        split_render_result
          (Native.renderer_repaint_split_footer handle pinned_render_offset
             force))

let commit_split_footer_snapshot renderer ~snapshot ~row_columns
    ~start_on_new_line ~trailing_newline ~pinned_render_offset ~force
    ~begin_frame ~finalize_frame =
  if Int32.compare row_columns 0l < 0
     || Int32.compare pinned_render_offset 0l < 0
  then Error Error.Invalid_argument
  else
    with_open renderer (fun handle ->
        Optimized_buffer.Private.with_open snapshot (fun snapshot_handle ->
            split_render_result
              (Native.renderer_commit_split_footer_snapshot handle snapshot_handle
                 row_columns start_on_new_line trailing_newline
                 pinned_render_offset force begin_frame finalize_frame)))

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
