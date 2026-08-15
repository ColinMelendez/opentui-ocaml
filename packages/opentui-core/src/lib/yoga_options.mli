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

val parse_align : string -> (align, error) result
val parse_align_items : string -> (align, error) result
val parse_box_sizing : string -> (box_sizing, error) result
val parse_dimension : string -> (dimension, error) result
val parse_direction : string -> (direction, error) result
val parse_display : string -> (display, error) result
val parse_edge : string -> (edge, error) result
val parse_flex_direction : string -> (flex_direction, error) result
val parse_gutter : string -> (gutter, error) result
val parse_justify : string -> (justify, error) result
val parse_log_level : string -> (log_level, error) result
val parse_measure_mode : string -> (measure_mode, error) result
val parse_overflow : string -> (overflow, error) result
val parse_position_type : string -> (position_type, error) result
val parse_unit : string -> (unit_kind, error) result
val parse_wrap : string -> (wrap, error) result

val default_align : align
val default_align_items : align
val default_box_sizing : box_sizing
val default_dimension : dimension
val default_direction : direction
val default_display : display
val default_edge : edge
val default_flex_direction : flex_direction
val default_gutter : gutter
val default_justify : justify
val default_log_level : log_level
val default_measure_mode : measure_mode
val default_overflow : overflow
val default_position_type : position_type
val default_unit : unit_kind
val default_wrap : wrap

val message : error -> string
