type error =
  | Empty
  | Reserved
  | Invalid_character of char
  | Trailing_space_or_dot
  | Dot_name

let message = function
  | Empty -> "directory name must not be empty or whitespace"
  | Reserved -> "directory name is reserved by the host platform"
  | Invalid_character character ->
      Printf.sprintf "directory name contains invalid character %C" character
  | Trailing_space_or_dot -> "directory name must not end in a space or dot"
  | Dot_name -> "directory name must not be . or .."

let reserved value =
  let upper = String.uppercase_ascii value in
  match upper with
  | "CON" | "PRN" | "AUX" | "NUL" -> true
  | value when String.length value = 4 ->
      let prefix = String.sub value 0 3 in
      let last = String.get value 3 in
      (String.equal prefix "COM" || String.equal prefix "LPT")
      && Char.code last >= Char.code '1'
      && Char.code last <= Char.code '9'
  | _ -> false

let invalid character =
  let code = Char.code character in
  code = 0 || code < 32
  || List.exists (Char.equal character) [ '<'; '>'; ':'; '"'; '|'; '?'; '*'; '/'; '\\' ]

let validate value =
  if String.length value = 0 || String.trim value = "" then Error Empty
  else if String.equal value "." || String.equal value ".." then Error Dot_name
  else if reserved value then Error Reserved
  else if Char.equal (String.get value (String.length value - 1)) ' '
          || Char.equal (String.get value (String.length value - 1)) '.'
  then Error Trailing_space_or_dot
  else
    let failure = ref None in
    for index = 0 to String.length value - 1 do
      match !failure with
      | Some _ -> ()
      | None ->
          let character = String.get value index in
          if invalid character then failure := Some (Invalid_character character)
    done;
    match !failure with None -> Ok () | Some error -> Error error

let is_valid value = Result.is_ok (validate value)
