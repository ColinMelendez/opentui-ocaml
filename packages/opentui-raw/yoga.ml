type direction = Inherit | Ltr | Rtl

type value = Undefined | Point of float | Percent of float | Auto

type edge =
  | Left
  | Top
  | Right
  | Bottom
  | Start
  | End
  | Horizontal
  | Vertical
  | All

type gutter = Gutter_column | Gutter_row | Gutter_all

type align =
  | Align_auto
  | Align_flex_start
  | Align_center
  | Align_flex_end
  | Align_stretch
  | Align_baseline
  | Align_space_between
  | Align_space_around
  | Align_space_evenly

type box_sizing = Box_sizing_border_box | Box_sizing_content_box

type display = Display_flex | Display_none | Display_contents

type flex_direction =
  | Flex_column
  | Flex_column_reverse
  | Flex_row
  | Flex_row_reverse

type justify =
  | Justify_flex_start
  | Justify_center
  | Justify_flex_end
  | Justify_space_between
  | Justify_space_around
  | Justify_space_evenly

type overflow = Overflow_visible | Overflow_hidden | Overflow_scroll

type position_type = Position_static | Position_relative | Position_absolute

type wrap = Wrap_no_wrap | Wrap | Wrap_reverse

type layout = {
  left : float;
  top : float;
  right : float;
  bottom : float;
  width : float;
  height : float;
}

type t = {
  handle : Native_token.Yoga_node.t;
  mutable freed : bool;
}

module Node = struct
  type nonrec t = t
  type nonrec value = value
  type nonrec edge = edge
  type nonrec gutter = gutter
  type nonrec align = align
  type nonrec box_sizing = box_sizing
  type nonrec display = display
  type nonrec flex_direction = flex_direction
  type nonrec justify = justify
  type nonrec overflow = overflow
  type nonrec position_type = position_type
  type nonrec wrap = wrap

  let error_of_status status =
    match Error.Private.of_native_status status with
    | Some error -> error
    | None -> Error.Native_failure

  let result_of_status status value =
    if status = 0 then Ok value else Error (error_of_status status)

  let with_live node operation =
    if node.freed then Error Error.Stale_handle else operation ()

  let direction_code = function Inherit -> 0l | Ltr -> 1l | Rtl -> 2l

  let edge_code = function
    | Left -> 0l
    | Top -> 1l
    | Right -> 2l
    | Bottom -> 3l
    | Start -> 4l
    | End -> 5l
    | Horizontal -> 6l
    | Vertical -> 7l
    | All -> 8l

  let gutter_code = function
    | Gutter_column -> 0l
    | Gutter_row -> 1l
    | Gutter_all -> 2l

  let align_code = function
    | Align_auto -> 0l
    | Align_flex_start -> 1l
    | Align_center -> 2l
    | Align_flex_end -> 3l
    | Align_stretch -> 4l
    | Align_baseline -> 5l
    | Align_space_between -> 6l
    | Align_space_around -> 7l
    | Align_space_evenly -> 8l

  let box_sizing_code = function
    | Box_sizing_border_box -> 0l
    | Box_sizing_content_box -> 1l

  let display_code = function
    | Display_flex -> 0l
    | Display_none -> 1l
    | Display_contents -> 2l

  let flex_direction_code = function
    | Flex_column -> 0l
    | Flex_column_reverse -> 1l
    | Flex_row -> 2l
    | Flex_row_reverse -> 3l

  let justify_code = function
    | Justify_flex_start -> 0l
    | Justify_center -> 1l
    | Justify_flex_end -> 2l
    | Justify_space_between -> 3l
    | Justify_space_around -> 4l
    | Justify_space_evenly -> 5l

  let overflow_code = function
    | Overflow_visible -> 0l
    | Overflow_hidden -> 1l
    | Overflow_scroll -> 2l

  let position_type_code = function
    | Position_static -> 0l
    | Position_relative -> 1l
    | Position_absolute -> 2l

  let wrap_code = function
    | Wrap_no_wrap -> 0l
    | Wrap -> 1l
    | Wrap_reverse -> 2l

  let value_code = function
    | Undefined -> 0l
    | Point _ -> 1l
    | Percent _ -> 2l
    | Auto -> 3l

  let value_number = function
    | Undefined | Auto -> Float.nan
    | Point value | Percent value -> value

  let create () =
    let status, handle = Native.yoga_node_create () in
    if status = 0 then Ok { handle; freed = false }
    else Error (error_of_status status)

  let free node =
    if node.freed then Ok ()
    else
      match result_of_status (Native.yoga_node_free node.handle) () with
      | Ok () ->
          node.freed <- true;
          Ok ()
      | Error error -> Error error

  let free_recursive node =
    if node.freed then Ok ()
    else
      match result_of_status (Native.yoga_node_free_recursive node.handle) () with
      | Ok () ->
          node.freed <- true;
          Ok ()
      | Error error -> Error error

  let insert_child ~parent ~child ~index =
    with_live parent (fun () ->
        with_live child (fun () ->
            result_of_status
              (Native.yoga_node_insert_child parent.handle child.handle index)
              ()))

  let remove_child ~parent ~child =
    with_live parent (fun () ->
        with_live child (fun () ->
            result_of_status
              (Native.yoga_node_remove_child parent.handle child.handle)
              ()))

  let move_child ~parent ~child ~index =
    with_live parent (fun () ->
        with_live child (fun () ->
            result_of_status
              (Native.yoga_node_move_child parent.handle child.handle index)
              ()))

  let child_count node =
    with_live node (fun () ->
        let status, count = Native.yoga_node_child_count node.handle in
        result_of_status status count)

  let calculate_layout node ~width ~height ~direction =
    with_live node (fun () ->
        result_of_status
          (Native.yoga_node_calculate node.handle width height
          (direction_code direction))
          ())

  let is_dirty node =
    with_live node (fun () ->
        let status, value = Native.yoga_node_is_dirty node.handle in
        result_of_status status value)

  let mark_dirty node =
    with_live node (fun () ->
        result_of_status (Native.yoga_node_mark_dirty node.handle) ())

  let has_new_layout node =
    with_live node (fun () ->
        let status, value = Native.yoga_node_has_new_layout node.handle in
        result_of_status status value)

  let mark_layout_seen node =
    with_live node (fun () ->
        result_of_status (Native.yoga_node_mark_layout_seen node.handle) ())

  let set_value node ~kind ~edge_or_gutter value =
    with_live node (fun () ->
        result_of_status
          (Native.yoga_node_style_set_value node.handle kind edge_or_gutter
             (value_code value) (value_number value))
          ())

  let set_value_without_auto node ~kind ~edge_or_gutter value =
    match value with
    | Auto -> Error Error.Invalid_argument
    | Undefined | Point _ | Percent _ ->
        set_value node ~kind ~edge_or_gutter value

  let set_width node value = set_value node ~kind:0l ~edge_or_gutter:0l value
  let set_height node value = set_value node ~kind:1l ~edge_or_gutter:0l value

  let set_min_width node value =
    set_value_without_auto node ~kind:2l ~edge_or_gutter:0l value

  let set_min_height node value =
    set_value_without_auto node ~kind:3l ~edge_or_gutter:0l value

  let set_max_width node value =
    set_value_without_auto node ~kind:4l ~edge_or_gutter:0l value

  let set_max_height node value =
    set_value_without_auto node ~kind:5l ~edge_or_gutter:0l value

  let set_flex_basis node value =
    set_value node ~kind:6l ~edge_or_gutter:0l value

  let set_margin node ~edge value =
    set_value node ~kind:7l ~edge_or_gutter:(edge_code edge) value

  let set_padding node ~edge value =
    set_value_without_auto node ~kind:8l ~edge_or_gutter:(edge_code edge) value

  let set_position node ~edge value =
    set_value node ~kind:9l ~edge_or_gutter:(edge_code edge) value

  let set_gap node ~gutter value =
    set_value_without_auto node ~kind:10l ~edge_or_gutter:(gutter_code gutter)
      value

  let set_enum node ~kind value =
    with_live node (fun () ->
        result_of_status
          (Native.yoga_node_style_set_enum node.handle kind value)
          ())

  let set_direction node direction = set_enum node ~kind:0l (direction_code direction)

  let set_flex_direction node value =
    set_enum node ~kind:1l (flex_direction_code value)

  let set_justify_content node value =
    set_enum node ~kind:2l (justify_code value)

  let set_align_content node value = set_enum node ~kind:3l (align_code value)
  let set_align_items node value = set_enum node ~kind:4l (align_code value)
  let set_align_self node value = set_enum node ~kind:5l (align_code value)

  let set_position_type node value =
    set_enum node ~kind:6l (position_type_code value)

  let set_wrap node value = set_enum node ~kind:7l (wrap_code value)
  let set_overflow node value = set_enum node ~kind:8l (overflow_code value)
  let set_display node value = set_enum node ~kind:9l (display_code value)

  let set_box_sizing node value =
    set_enum node ~kind:10l (box_sizing_code value)

  let set_float node ~kind value =
    with_live node (fun () ->
        result_of_status
          (Native.yoga_node_style_set_float node.handle kind
             (Option.value value ~default:Float.nan))
          ())

  let set_flex node value = set_float node ~kind:0l value
  let set_flex_grow node value = set_float node ~kind:1l value
  let set_flex_shrink node value = set_float node ~kind:2l value
  let set_aspect_ratio node value = set_float node ~kind:3l value

  let set_border node ~edge ~value =
    with_live node (fun () ->
        result_of_status
          (Native.yoga_node_style_set_border node.handle (edge_code edge)
             (Option.value value ~default:Float.nan))
          ())

  let set_width_point node width =
    set_width node (Point width)

  let set_height_point node height =
    set_height node (Point height)

  let set_padding_point node ~edge ~value =
    set_padding node ~edge (Point value)

  let layout node =
    with_live node (fun () ->
        let status, native_layout = Native.yoga_node_layout node.handle in
        match status, native_layout with
        | 0, Some (left, top, right, bottom, width, height) ->
            Ok { left; top; right; bottom; width; height }
        | 0, None -> Error Error.Native_failure
        | _, _ -> Error (error_of_status status))

  module Private = struct
    let with_open_handle node operation =
      with_live node (fun () -> operation node.handle)

    let claim_native_renderable node =
      with_live node (fun () ->
          result_of_status
            (Native.yoga_node_claim_native_renderable node.handle)
            ())

    let release_native_renderable node =
      with_live node (fun () ->
          result_of_status
            (Native.yoga_node_release_native_renderable node.handle)
            ())

    let set_native_measure_attached node attached =
      with_live node (fun () ->
          result_of_status
            (Native.yoga_node_set_native_measure_attached node.handle attached)
            ())
  end
end
