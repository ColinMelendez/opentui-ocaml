type error = Unknown of string
type align = Yoga.align
type box_sizing = Yoga.box_sizing
type dimension = Width | Height
type direction = Yoga.direction
type display = Yoga.display
type edge = Yoga.edge
type flex_direction = Yoga.flex_direction
type gutter = Yoga.gutter
type justify = Yoga.justify
type log_level = Error | Warn | Info | Debug | Verbose | Fatal
type measure_mode = Undefined | Exactly | At_most
type overflow = Yoga.overflow
type position_type = Yoga.position_type
type unit_kind = Undefined_unit | Point | Percent | Auto
type wrap = Yoga.wrap

let unknown value = Result.Error (Unknown value)
let normalize value = String.lowercase_ascii value

let parse_align value =
  match normalize value with
  | "auto" -> Ok Yoga.Align_auto
  | "flex-start" -> Ok Yoga.Align_flex_start
  | "center" -> Ok Yoga.Align_center
  | "flex-end" -> Ok Yoga.Align_flex_end
  | "stretch" -> Ok Yoga.Align_stretch
  | "baseline" -> Ok Yoga.Align_baseline
  | "space-between" -> Ok Yoga.Align_space_between
  | "space-around" -> Ok Yoga.Align_space_around
  | "space-evenly" -> Ok Yoga.Align_space_evenly
  | _ -> unknown value

let parse_align_items = parse_align

let parse_box_sizing value =
  match normalize value with
  | "border-box" -> Ok Yoga.Box_sizing_border_box
  | "content-box" -> Ok Yoga.Box_sizing_content_box
  | _ -> unknown value

let parse_dimension value =
  match normalize value with "width" -> Ok Width | "height" -> Ok Height | _ -> unknown value

let parse_direction value =
  match normalize value with
  | "inherit" -> Ok Yoga.Inherit
  | "ltr" -> Ok Yoga.Ltr
  | "rtl" -> Ok Yoga.Rtl
  | _ -> unknown value

let parse_display value =
  match normalize value with
  | "flex" -> Ok Yoga.Display_flex
  | "none" -> Ok Yoga.Display_none
  | "contents" -> Ok Yoga.Display_contents
  | _ -> unknown value

let parse_edge value =
  match normalize value with
  | "left" -> Ok Yoga.Left
  | "top" -> Ok Yoga.Top
  | "right" -> Ok Yoga.Right
  | "bottom" -> Ok Yoga.Bottom
  | "start" -> Ok Yoga.Start
  | "end" -> Ok Yoga.End
  | "horizontal" -> Ok Yoga.Horizontal
  | "vertical" -> Ok Yoga.Vertical
  | "all" -> Ok Yoga.All
  | _ -> unknown value

let parse_flex_direction value =
  match normalize value with
  | "column" -> Ok Yoga.Flex_column
  | "column-reverse" -> Ok Yoga.Flex_column_reverse
  | "row" -> Ok Yoga.Flex_row
  | "row-reverse" -> Ok Yoga.Flex_row_reverse
  | _ -> unknown value

let parse_gutter value =
  match normalize value with
  | "column" -> Ok Yoga.Gutter_column
  | "row" -> Ok Yoga.Gutter_row
  | "all" -> Ok Yoga.Gutter_all
  | _ -> unknown value

let parse_justify value =
  match normalize value with
  | "flex-start" -> Ok Yoga.Justify_flex_start
  | "center" -> Ok Yoga.Justify_center
  | "flex-end" -> Ok Yoga.Justify_flex_end
  | "space-between" -> Ok Yoga.Justify_space_between
  | "space-around" -> Ok Yoga.Justify_space_around
  | "space-evenly" -> Ok Yoga.Justify_space_evenly
  | _ -> unknown value

let parse_log_level value =
  match normalize value with
  | "error" -> Ok Error
  | "warn" | "warning" -> Ok Warn
  | "info" -> Ok Info
  | "debug" -> Ok Debug
  | "verbose" -> Ok Verbose
  | "fatal" -> Ok Fatal
  | _ -> unknown value

let parse_measure_mode value =
  match normalize value with
  | "undefined" -> Ok Undefined
  | "exactly" -> Ok Exactly
  | "at-most" | "at_most" -> Ok At_most
  | _ -> unknown value

let parse_overflow value =
  match normalize value with
  | "visible" -> Ok Yoga.Overflow_visible
  | "hidden" -> Ok Yoga.Overflow_hidden
  | "scroll" -> Ok Yoga.Overflow_scroll
  | _ -> unknown value

let parse_position_type value =
  match normalize value with
  | "static" -> Ok Yoga.Position_static
  | "relative" -> Ok Yoga.Position_relative
  | "absolute" -> Ok Yoga.Position_absolute
  | _ -> unknown value

let parse_unit value =
  match normalize value with
  | "undefined" -> Ok Undefined_unit
  | "point" | "points" -> Ok Point
  | "percent" | "%" -> Ok Percent
  | "auto" -> Ok Auto
  | _ -> unknown value

let parse_wrap value =
  match normalize value with
  | "no-wrap" | "nowrap" -> Ok Yoga.Wrap_no_wrap
  | "wrap" -> Ok Yoga.Wrap
  | "wrap-reverse" -> Ok Yoga.Wrap_reverse
  | _ -> unknown value

let default_align = Yoga.Align_auto
let default_align_items = Yoga.Align_stretch
let default_box_sizing = Yoga.Box_sizing_border_box
let default_dimension = Width
let default_direction = Yoga.Ltr
let default_display = Yoga.Display_flex
let default_edge = Yoga.All
let default_flex_direction = Yoga.Flex_column
let default_gutter = Yoga.Gutter_all
let default_justify = Yoga.Justify_flex_start
let default_log_level = Info
let default_measure_mode = Undefined
let default_overflow = Yoga.Overflow_visible
let default_position_type = Yoga.Position_relative
let default_unit = Point
let default_wrap = Yoga.Wrap_no_wrap

let message (Unknown value) = "unknown Yoga option: " ^ value
