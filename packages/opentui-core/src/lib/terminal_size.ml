type t = {
  columns : int;
  rows : int;
}

type error = Invalid_dimensions

let message = function
  | Invalid_dimensions -> "terminal dimensions must be positive"

let pp formatter error = Format.pp_print_string formatter (message error)

let create ~columns ~rows =
  if Int.compare columns 0 <= 0 || Int.compare rows 0 <= 0 then
    Error Invalid_dimensions
  else Ok { columns; rows }

let columns size = size.columns
let rows size = size.rows

let equal left right =
  Int.equal left.columns right.columns && Int.equal left.rows right.rows
