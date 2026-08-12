type kind = Down | Up | Move | Drag | Scroll

type scroll_direction =
  | Scroll_up
  | Scroll_down
  | Scroll_left
  | Scroll_right

type modifiers = {
  shift : bool;
  alt : bool;
  ctrl : bool;
}

type scroll = {
  direction : scroll_direction;
  delta : int;
}

type event = {
  kind : kind;
  button : int;
  x : int;
  y : int;
  modifiers : modifiers;
  scroll : scroll option;
}

type encoding = Sgr | X10

type decoded = {
  encoding : encoding;
  event : event;
}

type t = { pressed : bool array }

let create () = { pressed = Array.make 3 false }

let reset decoder = Array.fill decoder.pressed 0 3 false

let bit_set value bit = not (Int.equal (value land bit) 0)

let modifiers_of_code code =
  {
    shift = bit_set code 4;
    alt = bit_set code 8;
    ctrl = bit_set code 16;
  }

let scroll_direction_of_button button =
  match button land 3 with
  | 0 -> Scroll_up
  | 1 -> Scroll_down
  | 2 -> Scroll_left
  | _ -> Scroll_right

let has_pressed_button decoder =
  let pressed = ref false in
  for index = 0 to Array.length decoder.pressed - 1 do
    if decoder.pressed.(index) then pressed := true
  done;
  !pressed

let button_value button = if Int.equal button 3 then 0 else button

let mouse_event ~kind ~button ~x ~y ~modifiers ?scroll () =
  { kind; button; x; y; modifiers; scroll }

let sgr_event decoder ~button_code ~x ~y ~press =
  let button = button_code land 3 in
  let modifiers = modifiers_of_code button_code in
  if bit_set button_code 32 then
    let kind =
      if Int.equal button 3 then Move
      else if has_pressed_button decoder then Drag
      else Move
    in
    Some
      (mouse_event ~kind ~button:(button_value button) ~x ~y ~modifiers ())
  else if bit_set button_code 64 && press then
    Some
      (mouse_event ~kind:Scroll ~button:(button_value button) ~x ~y
         ~modifiers
         ~scroll:
           {
             direction = scroll_direction_of_button button;
             delta = 1;
           }
         ())
  else
    let kind = if press then Down else Up in
    if press then (
      if Int.compare button 3 < 0 then decoder.pressed.(button) <- true)
    else reset decoder;
    Some (mouse_event ~kind ~button:(button_value button) ~x ~y ~modifiers ())

let byte_is bytes index value = Int.equal (Bytes.get_uint8 bytes index) value

let add_decimal_digit current digit =
  if Int.compare !current ((Int.max_int - digit) / 10) > 0 then false
  else (
    current := (!current * 10) + digit;
    true)

let parse_sgr_parameters bytes ~start ~end_exclusive =
  let values = Array.make 3 0 in
  let field = ref 0 in
  let current = ref 0 in
  let has_digit = ref false in
  let valid = ref true in
  for index = start to end_exclusive - 1 do
    let value = Bytes.get_uint8 bytes index in
    if Int.compare value 0x30 >= 0 && Int.compare value 0x39 <= 0 then (
      has_digit := true;
      if not (add_decimal_digit current (value - 0x30)) then valid := false)
    else if Int.equal value 0x3b then
      if not !has_digit || Int.compare !field 2 >= 0 then valid := false
      else (
        values.(!field) <- !current;
        field := !field + 1;
        current := 0;
        has_digit := false)
    else valid := false
  done;
  if not !valid || not !has_digit || not (Int.equal !field 2) then None
  else (
    values.(2) <- !current;
    Some values)

let parse_sgr bytes =
  let length = Bytes.length bytes in
  if Int.compare length 8 < 0 then None
  else if
    not (byte_is bytes 0 0x1b)
    || not (byte_is bytes 1 0x5b)
    || not (byte_is bytes 2 0x3c)
  then None
  else
    let final = Bytes.get_uint8 bytes (length - 1) in
    if not (Int.equal final (Char.code 'M'))
       && not (Int.equal final (Char.code 'm'))
    then None
    else
      match
        parse_sgr_parameters bytes ~start:3 ~end_exclusive:(length - 1)
      with
      | None -> None
      | Some values when Int.compare values.(1) 1 < 0 -> None
      | Some values when Int.compare values.(2) 1 < 0 -> None
      | Some values ->
          Some
            ( values.(0),
              values.(1) - 1,
              values.(2) - 1,
              Int.equal final (Char.code 'M') )

let parse_x10 bytes =
  if not (Int.equal (Bytes.length bytes) 6) then None
  else if
    not (byte_is bytes 0 0x1b)
    || not (byte_is bytes 1 0x5b)
    || not (byte_is bytes 2 0x4d)
  then None
  else
    let button_wire = Bytes.get_uint8 bytes 3 in
    let x_wire = Bytes.get_uint8 bytes 4 in
    let y_wire = Bytes.get_uint8 bytes 5 in
    if Int.compare button_wire 0x20 < 0
       || Int.compare x_wire 0x21 < 0
       || Int.compare y_wire 0x21 < 0
    then None
    else Some (button_wire - 0x20, x_wire - 0x21, y_wire - 0x21)

let decode_x10 ~button_code ~x ~y =
  let button = button_code land 3 in
  let modifiers = modifiers_of_code button_code in
  if bit_set button_code 32 then
    Some
      (mouse_event ~kind:Move
         ~button:(if Int.equal button 3 then -1 else button)
         ~x ~y ~modifiers ())
  else if bit_set button_code 64 then
    Some
      (mouse_event ~kind:Scroll ~button:0 ~x ~y ~modifiers
         ~scroll:
           {
             direction = scroll_direction_of_button button;
             delta = 1;
           }
         ())
  else
    let kind = if Int.equal button 3 then Up else Down in
    Some (mouse_event ~kind ~button:(button_value button) ~x ~y ~modifiers ())

let decode decoder bytes =
  match parse_sgr bytes with
  | Some (button_code, x, y, press) ->
      (match sgr_event decoder ~button_code ~x ~y ~press with
      | Some event -> Some { encoding = Sgr; event }
      | None -> None)
  | None ->
      (match parse_x10 bytes with
      | Some (button_code, x, y) ->
          (match decode_x10 ~button_code ~x ~y with
          | Some event -> Some { encoding = X10; event }
          | None -> None)
      | None -> None)
