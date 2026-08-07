type named_key =
  | Return
  | Linefeed
  | Tab
  | Backspace
  | Escape
  | Space
  | Up
  | Down
  | Right
  | Left
  | Clear
  | Home
  | End
  | Insert
  | Delete
  | Page_up
  | Page_down
  | F1
  | F2
  | F3
  | F4
  | F5
  | F6
  | F7
  | F8
  | F9
  | F10
  | F11
  | F12
  | Menu

type modifiers = {
  shift : bool;
  meta : bool;
  ctrl : bool;
}

type key = Character of bytes | Named of named_key

type event =
  | Key of { key : key; modifiers : modifiers }
  | Sequence of { protocol : Stdin_parser.protocol; bytes : bytes }
  | Paste of bytes

let named_key_name = function
  | Return -> "return"
  | Linefeed -> "linefeed"
  | Tab -> "tab"
  | Backspace -> "backspace"
  | Escape -> "escape"
  | Space -> "space"
  | Up -> "up"
  | Down -> "down"
  | Right -> "right"
  | Left -> "left"
  | Clear -> "clear"
  | Home -> "home"
  | End -> "end"
  | Insert -> "insert"
  | Delete -> "delete"
  | Page_up -> "pageup"
  | Page_down -> "pagedown"
  | F1 -> "f1"
  | F2 -> "f2"
  | F3 -> "f3"
  | F4 -> "f4"
  | F5 -> "f5"
  | F6 -> "f6"
  | F7 -> "f7"
  | F8 -> "f8"
  | F9 -> "f9"
  | F10 -> "f10"
  | F11 -> "f11"
  | F12 -> "f12"
  | Menu -> "menu"

let no_modifiers = { shift = false; meta = false; ctrl = false }

let modifiers_of_wire value =
  if Int.compare value 0 <= 0 then no_modifiers
  else
    let bits = value - 1 in
    {
      shift = not (Int.equal (bits land 1) 0);
      meta = not (Int.equal (bits land 2) 0);
      ctrl = not (Int.equal (bits land 4) 0);
    }

let wire_modifier_supported value =
  if Int.compare value 1 < 0 then true
  else Int.equal ((value - 1) land lnot 7) 0

let combine_modifiers left right =
  {
    shift = left.shift || right.shift;
    meta = left.meta || right.meta;
    ctrl = left.ctrl || right.ctrl;
  }

let key_event key modifiers = Key { key; modifiers }

let named_event named modifiers = key_event (Named named) modifiers

let character_event bytes modifiers =
  key_event (Character (Bytes.copy bytes)) modifiers

let single_byte_key ~meta value =
  let base_modifiers = { no_modifiers with meta } in
  match value with
  | 0 -> (Named Space, { base_modifiers with ctrl = true })
  | 8 | 127 -> (Named Backspace, base_modifiers)
  | 9 -> (Named Tab, base_modifiers)
  | 10 -> (Named Linefeed, base_modifiers)
  | 13 -> (Named Return, base_modifiers)
  | 27 -> (Named Escape, base_modifiers)
  | 32 -> (Named Space, base_modifiers)
  | value when Int.compare value 1 >= 0 && Int.compare value 26 <= 0 ->
      ( Character (Bytes.make 1 (Char.chr (value + 96))),
        { base_modifiers with ctrl = true } )
  | value when Int.compare value 28 >= 0 && Int.compare value 31 <= 0 ->
      ( Character (Bytes.make 1 (Char.chr (value + 64))),
        { base_modifiers with ctrl = true } )
  | value when Int.compare value 65 >= 0 && Int.compare value 90 <= 0 ->
      ( Character (Bytes.make 1 (Char.chr value)),
        { base_modifiers with shift = true } )
  | value -> Character (Bytes.make 1 (Char.chr value)), base_modifiers

let ground_key bytes =
  if Int.equal (Bytes.length bytes) 1 then
    let key, modifiers = single_byte_key ~meta:false (Bytes.get_uint8 bytes 0) in
    key_event key modifiers
  else character_event bytes no_modifiers

let ascii_equal bytes text =
  let text_length = String.length text in
  if not (Int.equal (Bytes.length bytes) text_length) then false
  else
    let equal = ref true in
    for index = 0 to text_length - 1 do
      if not (Int.equal (Bytes.get_uint8 bytes index) (Char.code (String.get text index)))
      then equal := false
    done;
    !equal

let exact_csi_key bytes =
  let exact text named =
    if ascii_equal bytes text then Some (named_event named no_modifiers)
    else None
  in
  let shifted text named =
    if ascii_equal bytes text then
      Some (named_event named { no_modifiers with shift = true })
    else None
  in
  if ascii_equal bytes "\x1b[Z" then shifted "\x1b[Z" Tab
  else if ascii_equal bytes "\x1b[A" then exact "\x1b[A" Up
  else if ascii_equal bytes "\x1b[B" then exact "\x1b[B" Down
  else if ascii_equal bytes "\x1b[C" then exact "\x1b[C" Right
  else if ascii_equal bytes "\x1b[D" then exact "\x1b[D" Left
  else if ascii_equal bytes "\x1b[E" then exact "\x1b[E" Clear
  else if ascii_equal bytes "\x1b[F" then exact "\x1b[F" End
  else if ascii_equal bytes "\x1b[H" then exact "\x1b[H" Home
  else if ascii_equal bytes "\x1b[P" then exact "\x1b[P" F1
  else if ascii_equal bytes "\x1b[Q" then exact "\x1b[Q" F2
  else if ascii_equal bytes "\x1b[S" then exact "\x1b[S" F4
  else if ascii_equal bytes "\x1b[[A" then exact "\x1b[[A" F1
  else if ascii_equal bytes "\x1b[[B" then exact "\x1b[[B" F2
  else if ascii_equal bytes "\x1b[[C" then exact "\x1b[[C" F3
  else if ascii_equal bytes "\x1b[[D" then exact "\x1b[[D" F4
  else if ascii_equal bytes "\x1b[[E" then exact "\x1b[[E" F5
  else if ascii_equal bytes "\x1b[[5~" then
    Some (named_event Page_up no_modifiers)
  else if ascii_equal bytes "\x1b[[6~" then
    Some (named_event Page_down no_modifiers)
  else None

let numeric_key code =
  match code with
  | 1 | 7 -> Some Home
  | 2 -> Some Insert
  | 3 -> Some Delete
  | 4 | 8 -> Some End
  | 5 -> Some Page_up
  | 6 -> Some Page_down
  | 11 -> Some F1
  | 12 -> Some F2
  | 13 -> Some F3
  | 14 -> Some F4
  | 15 -> Some F5
  | 17 -> Some F6
  | 18 -> Some F7
  | 19 -> Some F8
  | 20 -> Some F9
  | 21 -> Some F10
  | 23 -> Some F11
  | 24 -> Some F12
  | 29 -> Some Menu
  | 57427 -> Some Clear
  | _ -> None

let rxvt_key code =
  match code with
  | 2 -> Some Insert
  | 3 -> Some Delete
  | 5 -> Some Page_up
  | 6 -> Some Page_down
  | 7 -> Some Home
  | 8 -> Some End
  | _ -> None

let final_key value =
  match value with
  | value when Int.equal value (Char.code 'A') -> Some Up
  | value when Int.equal value (Char.code 'B') -> Some Down
  | value when Int.equal value (Char.code 'C') -> Some Right
  | value when Int.equal value (Char.code 'D') -> Some Left
  | value when Int.equal value (Char.code 'E') -> Some Clear
  | value when Int.equal value (Char.code 'F') -> Some End
  | value when Int.equal value (Char.code 'H') -> Some Home
  | value when Int.equal value (Char.code 'P') -> Some F1
  | value when Int.equal value (Char.code 'Q') -> Some F2
  | value when Int.equal value (Char.code 'S') -> Some F4
  | value when Int.equal value (Char.code 'a') -> Some Up
  | value when Int.equal value (Char.code 'b') -> Some Down
  | value when Int.equal value (Char.code 'c') -> Some Right
  | value when Int.equal value (Char.code 'd') -> Some Left
  | value when Int.equal value (Char.code 'e') -> Some Clear
  | _ -> None

let parse_numeric_params bytes ~start ~end_exclusive =
  if Int.equal start end_exclusive then Some ([||], 0)
  else
    let values = Array.make 4 0 in
    let count = ref 0 in
    let current = ref 0 in
    let has_digit = ref false in
    let valid = ref true in
    for index = start to end_exclusive - 1 do
      let value = Bytes.get_uint8 bytes index in
      if Int.compare value 0x30 >= 0 && Int.compare value 0x39 <= 0 then (
        current := (!current * 10) + value - 0x30;
        has_digit := true)
      else if Int.equal value 0x3b then
        if not !has_digit || Int.compare !count 3 >= 0 then valid := false
        else (
          values.(!count) <- !current;
          count := !count + 1;
          current := 0;
          has_digit := false)
      else valid := false
    done;
    if not !valid || not !has_digit then None
    else (
      values.(!count) <- !current;
      Some (values, !count + 1))

let modify_other_key params count =
  if Int.compare count 3 < 0 then None
  else
    let modifier = modifiers_of_wire params.(1) in
    let char_code = params.(2) in
    if not (wire_modifier_supported params.(1))
       || Int.compare char_code 255 > 0
    then None
    else
      match char_code with
      | 8 | 127 -> Some (named_event Backspace modifier)
      | 9 -> Some (named_event Tab modifier)
      | 13 -> Some (named_event Return modifier)
      | 27 -> Some (named_event Escape modifier)
      | 32 -> Some (named_event Space modifier)
      | char_code ->
          Some (character_event (Bytes.make 1 (Char.chr char_code)) modifier)

let csi_key_from_params final params count =
  let modifier_wire =
    if Int.compare count 2 >= 0 && Int.equal params.(0) 27 then params.(1)
    else if Int.compare count 2 >= 0 then params.(count - 1)
    else 1
  in
  if not (wire_modifier_supported modifier_wire) then None
  else
    let modifier = modifiers_of_wire modifier_wire in
    if Int.equal final (Char.code '~') then
      if Int.equal count 0 then None
      else if Int.equal params.(0) 27 then modify_other_key params count
      else
        (match numeric_key params.(0) with
        | Some named -> Some (named_event named modifier)
        | None -> None)
    else if Int.equal final (Char.code '$') then
      if Int.equal count 0 then None
      else
        (match rxvt_key params.(0) with
        | Some named -> Some (named_event named (combine_modifiers modifier { no_modifiers with shift = true }))
        | None -> None)
    else if Int.equal final (Char.code '^') then
      if Int.equal count 0 then None
      else
        (match rxvt_key params.(0) with
        | Some named -> Some (named_event named (combine_modifiers modifier { no_modifiers with ctrl = true }))
        | None -> None)
    else
      match final_key final with
      | Some named ->
          let final_modifier =
            if Int.compare final (Char.code 'a') >= 0
               && Int.compare final (Char.code 'e') <= 0
            then { no_modifiers with shift = true }
            else no_modifiers
          in
          Some
            (named_event named (combine_modifiers modifier final_modifier))
      | None -> None

let csi_key_core bytes =
  match exact_csi_key bytes with
  | Some event -> Some event
  | None ->
      let length = Bytes.length bytes in
      if Int.compare length 3 < 0
         || not (Int.equal (Bytes.get_uint8 bytes 0) 0x1b)
         || not (Int.equal (Bytes.get_uint8 bytes 1) 0x5b)
      then None
      else
        let final = Bytes.get_uint8 bytes (length - 1) in
        if Int.compare final 0x40 < 0 || Int.compare final 0x7e > 0 then None
        else
          match
            parse_numeric_params bytes ~start:2 ~end_exclusive:(length - 1)
          with
          | None -> None
          | Some (params, count) -> csi_key_from_params final params count

let leading_escape_count bytes =
  let length = Bytes.length bytes in
  let leading_escapes = ref 0 in
  while
    Int.compare !leading_escapes length < 0
    && Int.equal (Bytes.get_uint8 bytes !leading_escapes) 0x1b
  do
    leading_escapes := !leading_escapes + 1
  done;
  !leading_escapes

let normalize_leading_escapes bytes leading_escapes =
  let length = Bytes.length bytes in
  let normalized_length = length - (leading_escapes - 1) in
  let normalized = Bytes.create normalized_length in
  Bytes.set_uint8 normalized 0 0x1b;
  for index = leading_escapes to length - 1 do
    Bytes.set_uint8 normalized (index - leading_escapes + 1)
      (Bytes.get_uint8 bytes index)
  done;
  normalized

let csi_key bytes =
  let length = Bytes.length bytes in
  let leading_escapes = leading_escape_count bytes in
  if Int.equal leading_escapes 1 then csi_key_core bytes
  else if Int.compare leading_escapes 2 >= 0
          && Int.compare leading_escapes length < 0
          && Int.equal (Bytes.get_uint8 bytes leading_escapes) 0x5b
  then
    let normalized = normalize_leading_escapes bytes leading_escapes in
    (match csi_key_core normalized with
    | Some (Key { key; modifiers }) ->
        Some
          (Key
             {
               key;
               modifiers = { modifiers with meta = true };
             })
    | None -> None
    | Some (Sequence _) -> None
    | Some (Paste _) -> None)
  else None

let ss3_key_core bytes =
  let length = Bytes.length bytes in
  if not (Int.equal length 3)
     || not (Int.equal (Bytes.get_uint8 bytes 0) 0x1b)
     || not (Int.equal (Bytes.get_uint8 bytes 1) 0x4f)
  then None
  else
    let value = Bytes.get_uint8 bytes 2 in
    let named named_key modifiers = Some (named_event named_key modifiers) in
    match value with
    | value when Int.equal value (Char.code 'A') -> named Up no_modifiers
    | value when Int.equal value (Char.code 'B') -> named Down no_modifiers
    | value when Int.equal value (Char.code 'C') -> named Right no_modifiers
    | value when Int.equal value (Char.code 'D') -> named Left no_modifiers
    | value when Int.equal value (Char.code 'E') -> named Clear no_modifiers
    | value when Int.equal value (Char.code 'F') -> named End no_modifiers
    | value when Int.equal value (Char.code 'H') -> named Home no_modifiers
    | value when Int.equal value (Char.code 'P') -> named F1 no_modifiers
    | value when Int.equal value (Char.code 'Q') -> named F2 no_modifiers
    | value when Int.equal value (Char.code 'R') -> named F3 no_modifiers
    | value when Int.equal value (Char.code 'S') -> named F4 no_modifiers
    | value when Int.equal value (Char.code 'a') ->
        named Up { no_modifiers with ctrl = true }
    | value when Int.equal value (Char.code 'b') ->
        named Down { no_modifiers with ctrl = true }
    | value when Int.equal value (Char.code 'c') ->
        named Right { no_modifiers with ctrl = true }
    | value when Int.equal value (Char.code 'd') ->
        named Left { no_modifiers with ctrl = true }
    | value when Int.equal value (Char.code 'e') ->
        named Clear { no_modifiers with ctrl = true }
    | value when Int.equal value (Char.code 'M') -> named Return no_modifiers
    | value when Int.equal value (Char.code 'j') ->
        Some (character_event (Bytes.of_string "*") no_modifiers)
    | value when Int.equal value (Char.code 'k') ->
        Some (character_event (Bytes.of_string "+") no_modifiers)
    | value when Int.equal value (Char.code 'l') ->
        Some (character_event (Bytes.of_string ",") no_modifiers)
    | value when Int.equal value (Char.code 'm') ->
        Some (character_event (Bytes.of_string "-") no_modifiers)
    | value when Int.equal value (Char.code 'n') ->
        Some (character_event (Bytes.of_string ".") no_modifiers)
    | value when Int.equal value (Char.code 'o') ->
        Some (character_event (Bytes.of_string "/") no_modifiers)
    | value when Int.equal value (Char.code 'X') ->
        Some (character_event (Bytes.of_string "=") no_modifiers)
    | value when Int.compare value (Char.code 'p') >= 0
               && Int.compare value (Char.code 'y') <= 0 ->
        let digit =
          if Int.equal value (Char.code 'p') then '0'
          else Char.chr (Char.code '0' + value - Char.code 'p')
        in
        Some (character_event (Bytes.make 1 digit) no_modifiers)
    | _ -> None

let ss3_key bytes =
  let length = Bytes.length bytes in
  let leading_escapes = leading_escape_count bytes in
  if Int.equal leading_escapes 1 then ss3_key_core bytes
  else if Int.compare leading_escapes 2 >= 0
          && Int.compare leading_escapes length < 0
          && Int.equal (Bytes.get_uint8 bytes leading_escapes) 0x4f
  then
    let normalized = normalize_leading_escapes bytes leading_escapes in
    match ss3_key_core normalized with
    | Some (Key { key; modifiers }) ->
        Some
          (Key
             {
               key;
               modifiers = { modifiers with meta = true };
             })
    | None -> None
    | Some (Sequence _) -> None
    | Some (Paste _) -> None
  else None

let unknown_key bytes =
  let length = Bytes.length bytes in
  if Int.equal length 2 && Int.equal (Bytes.get_uint8 bytes 0) 0x1b then
    let value = Bytes.get_uint8 bytes 1 in
    if Int.compare value 0x7f <= 0 then
      if Int.equal value (Char.code 'F') then
        Some (named_event Right { no_modifiers with meta = true })
      else if Int.equal value (Char.code 'B') then
        Some (named_event Left { no_modifiers with meta = true })
      else
        let key, modifiers = single_byte_key ~meta:true value in
        Some (key_event key modifiers)
    else None
  else None

let decode_sequence protocol bytes =
  match protocol with
  | Stdin_parser.Csi -> csi_key bytes
  | Stdin_parser.Ss3 -> ss3_key bytes
  | Stdin_parser.Unknown -> unknown_key bytes
  | Stdin_parser.Osc | Stdin_parser.Dcs | Stdin_parser.Apc -> None

let decode = function
  | Stdin_parser.Key bytes -> ground_key bytes
  | Stdin_parser.Sequence { protocol; bytes } ->
      (match decode_sequence protocol bytes with
      | Some event -> event
      | None -> Sequence { protocol; bytes = Bytes.copy bytes })
  | Stdin_parser.Paste bytes -> Paste (Bytes.copy bytes)
