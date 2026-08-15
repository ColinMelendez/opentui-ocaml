type error =
  | Empty
  | Reserved
  | Invalid_character of char
  | Trailing_space_or_dot
  | Dot_name

val validate : string -> (unit, error) result
val is_valid : string -> bool
val message : error -> string
