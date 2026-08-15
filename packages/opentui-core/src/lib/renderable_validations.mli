type error = Invalid_number of string | Invalid_percentage of string | Invalid_value of string

type spacing = Pixels of float | Percentage of float | Auto
type dimension = Pixels of float | Percentage of float | Auto | Undefined
type position = spacing
type overflow = Visible | Hidden | Scroll
type position_type = Relative | Absolute | Static

val nonnegative : name:string -> float -> (unit, error) result
val validate_options :
  id:string -> width:float option -> height:float option -> (unit, error) result
val is_valid_percentage : string -> bool
val percentage : string -> (float, error) result
val margin : string -> (spacing, error) result
val padding : string -> (spacing, error) result
val position : string -> (position, error) result
val dimension : string -> (dimension, error) result
val flex_basis : string -> (spacing option, error) result
val size : string -> (dimension option, error) result
val overflow : string -> (overflow, error) result
val position_type : string -> (position_type, error) result
val message : error -> string
