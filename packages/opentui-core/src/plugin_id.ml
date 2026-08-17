type t = string

type error =
  | Empty
  | Nul_character of int

let create value =
  let length = String.length value in
  if Int.equal length 0 then Error Empty
  else
    let position = ref 0 in
    let invalid = ref None in
    while not (Int.equal !position length) && Option.is_none !invalid do
      if Char.equal value.[!position] '\000' then
        invalid := Some !position
      else position := !position + 1
    done;
    match !invalid with
    | None -> Ok value
    | Some position -> Error (Nul_character position)

let to_string value = value
let equal left right = String.equal left right
let compare left right = String.compare left right

let error_message error =
  match error with
  | Empty -> "an identifier must not be empty"
  | Nul_character position ->
      Format.asprintf "an identifier contains a NUL character at byte %d" position

let pp_error formatter error = Format.pp_print_string formatter (error_message error)
