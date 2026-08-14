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

let map_error error = Native.Error.Native error

let map_result result =
  match result with
  | Ok value -> Ok value
  | Error error -> Error (map_error error)

module Node = struct
  type t = Opentui_raw.Yoga.Node.t

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

  let create () = map_result (Opentui_raw.Yoga.Node.create ())
  let free node = map_result (Opentui_raw.Yoga.Node.free node)
  let free_recursive node = map_result (Opentui_raw.Yoga.Node.free_recursive node)

  let insert_child ~parent ~child ~index =
    map_result
      (Opentui_raw.Yoga.Node.insert_child ~parent ~child ~index)

  let remove_child ~parent ~child =
    map_result (Opentui_raw.Yoga.Node.remove_child ~parent ~child)

  let move_child ~parent ~child ~index =
    map_result (Opentui_raw.Yoga.Node.move_child ~parent ~child ~index)

  let child_count node = map_result (Opentui_raw.Yoga.Node.child_count node)

  let raw_direction = function
    | Inherit -> Opentui_raw.Yoga.Inherit
    | Ltr -> Opentui_raw.Yoga.Ltr
    | Rtl -> Opentui_raw.Yoga.Rtl

  let calculate_layout node ~width ~height ~direction =
    map_result
      (Opentui_raw.Yoga.Node.calculate_layout node ~width ~height
         ~direction:(raw_direction direction))

  let is_dirty node = map_result (Opentui_raw.Yoga.Node.is_dirty node)
  let mark_dirty node = map_result (Opentui_raw.Yoga.Node.mark_dirty node)
  let has_new_layout node = map_result (Opentui_raw.Yoga.Node.has_new_layout node)
  let mark_layout_seen node =
    map_result (Opentui_raw.Yoga.Node.mark_layout_seen node)

  let raw_value = function
    | Undefined -> Opentui_raw.Yoga.Undefined
    | Point value -> Opentui_raw.Yoga.Point value
    | Percent value -> Opentui_raw.Yoga.Percent value
    | Auto -> Opentui_raw.Yoga.Auto

  let raw_edge = function
    | Left -> Opentui_raw.Yoga.Left
    | Top -> Opentui_raw.Yoga.Top
    | Right -> Opentui_raw.Yoga.Right
    | Bottom -> Opentui_raw.Yoga.Bottom
    | Start -> Opentui_raw.Yoga.Start
    | End -> Opentui_raw.Yoga.End
    | Horizontal -> Opentui_raw.Yoga.Horizontal
    | Vertical -> Opentui_raw.Yoga.Vertical
    | All -> Opentui_raw.Yoga.All

  let raw_gutter = function
    | Gutter_column -> Opentui_raw.Yoga.Gutter_column
    | Gutter_row -> Opentui_raw.Yoga.Gutter_row
    | Gutter_all -> Opentui_raw.Yoga.Gutter_all

  let raw_align = function
    | Align_auto -> Opentui_raw.Yoga.Align_auto
    | Align_flex_start -> Opentui_raw.Yoga.Align_flex_start
    | Align_center -> Opentui_raw.Yoga.Align_center
    | Align_flex_end -> Opentui_raw.Yoga.Align_flex_end
    | Align_stretch -> Opentui_raw.Yoga.Align_stretch
    | Align_baseline -> Opentui_raw.Yoga.Align_baseline
    | Align_space_between -> Opentui_raw.Yoga.Align_space_between
    | Align_space_around -> Opentui_raw.Yoga.Align_space_around
    | Align_space_evenly -> Opentui_raw.Yoga.Align_space_evenly

  let raw_box_sizing = function
    | Box_sizing_border_box -> Opentui_raw.Yoga.Box_sizing_border_box
    | Box_sizing_content_box -> Opentui_raw.Yoga.Box_sizing_content_box

  let raw_display = function
    | Display_flex -> Opentui_raw.Yoga.Display_flex
    | Display_none -> Opentui_raw.Yoga.Display_none
    | Display_contents -> Opentui_raw.Yoga.Display_contents

  let raw_flex_direction = function
    | Flex_column -> Opentui_raw.Yoga.Flex_column
    | Flex_column_reverse -> Opentui_raw.Yoga.Flex_column_reverse
    | Flex_row -> Opentui_raw.Yoga.Flex_row
    | Flex_row_reverse -> Opentui_raw.Yoga.Flex_row_reverse

  let raw_justify = function
    | Justify_flex_start -> Opentui_raw.Yoga.Justify_flex_start
    | Justify_center -> Opentui_raw.Yoga.Justify_center
    | Justify_flex_end -> Opentui_raw.Yoga.Justify_flex_end
    | Justify_space_between -> Opentui_raw.Yoga.Justify_space_between
    | Justify_space_around -> Opentui_raw.Yoga.Justify_space_around
    | Justify_space_evenly -> Opentui_raw.Yoga.Justify_space_evenly

  let raw_overflow = function
    | Overflow_visible -> Opentui_raw.Yoga.Overflow_visible
    | Overflow_hidden -> Opentui_raw.Yoga.Overflow_hidden
    | Overflow_scroll -> Opentui_raw.Yoga.Overflow_scroll

  let raw_position_type = function
    | Position_static -> Opentui_raw.Yoga.Position_static
    | Position_relative -> Opentui_raw.Yoga.Position_relative
    | Position_absolute -> Opentui_raw.Yoga.Position_absolute

  let raw_wrap = function
    | Wrap_no_wrap -> Opentui_raw.Yoga.Wrap_no_wrap
    | Wrap -> Opentui_raw.Yoga.Wrap
    | Wrap_reverse -> Opentui_raw.Yoga.Wrap_reverse

  let set_width node value =
    map_result (Opentui_raw.Yoga.Node.set_width node (raw_value value))

  let set_height node value =
    map_result (Opentui_raw.Yoga.Node.set_height node (raw_value value))

  let set_min_width node value =
    map_result (Opentui_raw.Yoga.Node.set_min_width node (raw_value value))

  let set_min_height node value =
    map_result (Opentui_raw.Yoga.Node.set_min_height node (raw_value value))

  let set_max_width node value =
    map_result (Opentui_raw.Yoga.Node.set_max_width node (raw_value value))

  let set_max_height node value =
    map_result (Opentui_raw.Yoga.Node.set_max_height node (raw_value value))

  let set_flex_basis node value =
    map_result (Opentui_raw.Yoga.Node.set_flex_basis node (raw_value value))

  let set_margin node ~edge value =
    map_result
      (Opentui_raw.Yoga.Node.set_margin node ~edge:(raw_edge edge)
         (raw_value value))

  let set_padding node ~edge value =
    map_result
      (Opentui_raw.Yoga.Node.set_padding node ~edge:(raw_edge edge)
         (raw_value value))

  let set_position node ~edge value =
    map_result
      (Opentui_raw.Yoga.Node.set_position node ~edge:(raw_edge edge)
         (raw_value value))

  let set_gap node ~gutter value =
    map_result
      (Opentui_raw.Yoga.Node.set_gap node ~gutter:(raw_gutter gutter)
         (raw_value value))

  let set_direction node direction =
    map_result
      (Opentui_raw.Yoga.Node.set_direction node (raw_direction direction))

  let set_flex_direction node value =
    map_result
      (Opentui_raw.Yoga.Node.set_flex_direction node (raw_flex_direction value))

  let set_justify_content node value =
    map_result
      (Opentui_raw.Yoga.Node.set_justify_content node (raw_justify value))

  let set_align_content node value =
    map_result
      (Opentui_raw.Yoga.Node.set_align_content node (raw_align value))

  let set_align_items node value =
    map_result (Opentui_raw.Yoga.Node.set_align_items node (raw_align value))

  let set_align_self node value =
    map_result (Opentui_raw.Yoga.Node.set_align_self node (raw_align value))

  let set_position_type node value =
    map_result
      (Opentui_raw.Yoga.Node.set_position_type node (raw_position_type value))

  let set_wrap node value =
    map_result (Opentui_raw.Yoga.Node.set_wrap node (raw_wrap value))

  let set_overflow node value =
    map_result (Opentui_raw.Yoga.Node.set_overflow node (raw_overflow value))

  let set_display node value =
    map_result (Opentui_raw.Yoga.Node.set_display node (raw_display value))

  let set_box_sizing node value =
    map_result
      (Opentui_raw.Yoga.Node.set_box_sizing node (raw_box_sizing value))

  let set_flex node value = map_result (Opentui_raw.Yoga.Node.set_flex node value)
  let set_flex_grow node value = map_result (Opentui_raw.Yoga.Node.set_flex_grow node value)
  let set_flex_shrink node value = map_result (Opentui_raw.Yoga.Node.set_flex_shrink node value)
  let set_aspect_ratio node value = map_result (Opentui_raw.Yoga.Node.set_aspect_ratio node value)

  let set_border node ~edge ~value =
    map_result
      (Opentui_raw.Yoga.Node.set_border node ~edge:(raw_edge edge) ~value)

  let set_width_point node width = set_width node (Point width)
  let set_height_point node height = set_height node (Point height)

  let set_padding_point node ~edge ~value =
    set_padding node ~edge (Point value)

  let layout node =
    match Opentui_raw.Yoga.Node.layout node with
    | Error error -> Error (map_error error)
    | Ok layout ->
        Ok
          {
            left = layout.Opentui_raw.Yoga.left;
            top = layout.Opentui_raw.Yoga.top;
            right = layout.Opentui_raw.Yoga.right;
            bottom = layout.Opentui_raw.Yoga.bottom;
            width = layout.Opentui_raw.Yoga.width;
            height = layout.Opentui_raw.Yoga.height;
          }

  module Private = struct
    let attach_native_renderable node renderable =
      map_result
        (Opentui_raw.Native_renderable.attach_yoga_node renderable node)
  end
end
