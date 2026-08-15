module K = Key_decoder

let split_on character source =
  let pieces = ref [] in
  let start = ref 0 in
  for index = 0 to String.length source - 1 do
    if Char.equal (String.get source index) character then begin
      pieces := String.sub source !start (index - !start) :: !pieces;
      start := index + 1
    end
  done;
  pieces := String.sub source !start (String.length source - !start) :: !pieces;
  List.rev !pieces

let int_of_digits value =
  if String.length value = 0 then None
  else
    let valid = ref true in
    for index = 0 to String.length value - 1 do
      let code = Char.code (String.get value index) in
      if code < Char.code '0' || code > Char.code '9' then valid := false
    done;
    if !valid then int_of_string_opt value else None

let utf8 codepoint =
  if codepoint < 0 || codepoint > 0x10ffff
     || (codepoint >= 0xd800 && codepoint <= 0xdfff) then None
  else if codepoint < 0x80 then Some (Bytes.make 1 (Char.chr codepoint))
  else if codepoint < 0x800 then
    let value = Bytes.create 2 in
    Bytes.set_uint8 value 0 (0xc0 lor (codepoint lsr 6));
    Bytes.set_uint8 value 1 (0x80 lor (codepoint land 0x3f));
    Some value
  else if codepoint < 0x10000 then
    let value = Bytes.create 3 in
    Bytes.set_uint8 value 0 (0xe0 lor (codepoint lsr 12));
    Bytes.set_uint8 value 1 (0x80 lor ((codepoint lsr 6) land 0x3f));
    Bytes.set_uint8 value 2 (0x80 lor (codepoint land 0x3f));
    Some value
  else
    let value = Bytes.create 4 in
    Bytes.set_uint8 value 0 (0xf0 lor (codepoint lsr 18));
    Bytes.set_uint8 value 1 (0x80 lor ((codepoint lsr 12) land 0x3f));
    Bytes.set_uint8 value 2 (0x80 lor ((codepoint lsr 6) land 0x3f));
    Bytes.set_uint8 value 3 (0x80 lor (codepoint land 0x3f));
    Some value

let append_bytes buffer value =
  Stdlib.Buffer.add_bytes buffer value

let text_of_codepoints values =
  let output = Stdlib.Buffer.create 16 in
  List.iter
    (fun value ->
      if value > 0 then
        match utf8 value with
        | Some bytes -> append_bytes output bytes
        | None -> ())
    values;
  Stdlib.Buffer.contents output

let valid_codepoint value =
  if value > 0 && value <= 0x10ffff
     && not (value >= 0xd800 && value <= 0xdfff)
  then Some value
  else None

let uppercase_ascii bytes =
  let result = Bytes.copy bytes in
  for index = 0 to Bytes.length result - 1 do
    let value = Bytes.get_uint8 result index in
    if value >= Char.code 'a' && value <= Char.code 'z' then
      Bytes.set_uint8 result index (value - (Char.code 'a' - Char.code 'A'))
  done;
  result

let named_of_code code =
  match code with
  | 27 -> Some K.Escape | 9 -> Some K.Tab | 13 -> Some K.Return | 127 -> Some K.Backspace
  | 57344 -> Some K.Escape | 57345 -> Some K.Return | 57346 -> Some K.Tab
  | 57347 -> Some K.Backspace | 57348 -> Some K.Insert | 57349 -> Some K.Delete
  | 57350 -> Some K.Left | 57351 -> Some K.Right | 57352 -> Some K.Up
  | 57353 -> Some K.Down | 57354 -> Some K.Page_up | 57355 -> Some K.Page_down
  | 57356 -> Some K.Home | 57357 -> Some K.End | 57358 -> Some K.Capslock
  | 57359 -> Some K.Scrolllock | 57360 -> Some K.Numlock | 57361 -> Some K.Printscreen
  | 57362 -> Some K.Pause | 57363 -> Some K.Menu | 57427 -> Some K.Clear
  | code when code >= 57364 && code <= 57398 ->
      let index = code - 57364 in
      Some
        (match index with
        | 0 -> K.F1 | 1 -> K.F2 | 2 -> K.F3 | 3 -> K.F4 | 4 -> K.F5 | 5 -> K.F6
        | 6 -> K.F7 | 7 -> K.F8 | 8 -> K.F9 | 9 -> K.F10 | 10 -> K.F11 | 11 -> K.F12
        | 12 -> K.F13 | 13 -> K.F14 | 14 -> K.F15 | 15 -> K.F16 | 16 -> K.F17
        | 17 -> K.F18 | 18 -> K.F19 | 19 -> K.F20 | 20 -> K.F21 | 21 -> K.F22
        | 22 -> K.F23 | 23 -> K.F24 | 24 -> K.F25 | 25 -> K.F26 | 26 -> K.F27
        | 27 -> K.F28 | 28 -> K.F29 | 29 -> K.F30 | 30 -> K.F31 | 31 -> K.F32
        | 32 -> K.F33 | 33 -> K.F34 | 34 -> K.F35 | _ -> K.F1)
  | code when code >= 57399 && code <= 57426 ->
      let index = code - 57399 in
      Some
        (match index with
        | 0 -> K.Kp0 | 1 -> K.Kp1 | 2 -> K.Kp2 | 3 -> K.Kp3 | 4 -> K.Kp4
        | 5 -> K.Kp5 | 6 -> K.Kp6 | 7 -> K.Kp7 | 8 -> K.Kp8 | 9 -> K.Kp9
        | 10 -> K.Kpdecimal | 11 -> K.Kpdivide | 12 -> K.Kpmultiply
        | 13 -> K.Kpminus | 14 -> K.Kpplus | 15 -> K.Kpenter | 16 -> K.Kpequal
        | 17 -> K.Kpseparator | 18 -> K.Kpleft | 19 -> K.Kpright | 20 -> K.Kpup
        | 21 -> K.Kpdown | 22 -> K.Kppageup | 23 -> K.Kppagedown | 24 -> K.Kphome
        | 25 -> K.Kpend | 26 -> K.Kpinsert | 27 -> K.Kpdelete | _ -> K.Kp0)
  | 57428 -> Some K.Mediaplay | 57429 -> Some K.Mediapause
  | 57430 -> Some K.Mediaplaypause | 57431 -> Some K.Mediareverse
  | 57432 -> Some K.Mediastop | 57433 -> Some K.Mediafastforward
  | 57434 -> Some K.Mediarewind | 57435 -> Some K.Medianext
  | 57436 -> Some K.Mediaprev | 57437 -> Some K.Mediarecord
  | 57438 -> Some K.Volumedown | 57439 -> Some K.Volumeup | 57440 -> Some K.Mute
  | 57441 -> Some K.Leftshift | 57442 -> Some K.Leftctrl | 57443 -> Some K.Leftalt
  | 57444 -> Some K.Leftsuper | 57445 -> Some K.Lefthyper | 57446 -> Some K.Leftmeta
  | 57447 -> Some K.Rightshift | 57448 -> Some K.Rightctrl | 57449 -> Some K.Rightalt
  | 57450 -> Some K.Rightsuper | 57451 -> Some K.Righthyper | 57452 -> Some K.Rightmeta
  | 57453 -> Some K.Iso_level3_shift | 57454 -> Some K.Iso_level5_shift
  | _ -> None

let keypad_text = function
  | K.Kp0 -> Some "0" | K.Kp1 -> Some "1" | K.Kp2 -> Some "2" | K.Kp3 -> Some "3"
  | K.Kp4 -> Some "4" | K.Kp5 -> Some "5" | K.Kp6 -> Some "6" | K.Kp7 -> Some "7"
  | K.Kp8 -> Some "8" | K.Kp9 -> Some "9" | K.Kpdecimal -> Some "."
  | K.Kpdivide -> Some "/" | K.Kpmultiply -> Some "*" | K.Kpminus -> Some "-"
  | K.Kpplus -> Some "+" | K.Kpequal -> Some "=" | K.Kpseparator -> Some ","
  | _ -> None

let functional_key = function
  | 'A' -> Some K.Up | 'B' -> Some K.Down | 'C' -> Some K.Right | 'D' -> Some K.Left
  | 'E' -> Some K.Clear | 'F' -> Some K.End | 'H' -> Some K.Home
  | 'P' -> Some K.F1 | 'Q' -> Some K.F2 | 'S' -> Some K.F4 | _ -> None

let tilde_key value =
  match int_of_digits value with
  | None -> None
  | Some code ->
      (match code with
      | 1 | 7 -> Some K.Home | 2 -> Some K.Insert | 3 -> Some K.Delete
      | 4 | 8 -> Some K.End | 5 -> Some K.Page_up | 6 -> Some K.Page_down
      | 11 -> Some K.F1 | 12 -> Some K.F2 | 13 -> Some K.F3 | 14 -> Some K.F4
      | 15 -> Some K.F5 | 17 -> Some K.F6 | 18 -> Some K.F7 | 19 -> Some K.F8
      | 20 -> Some K.F9 | 21 -> Some K.F10 | 23 -> Some K.F11 | 24 -> Some K.F12
      | 29 -> Some K.Menu | 57427 -> Some K.Clear | _ -> None)

let modifiers wire =
  if wire < 1 then None
  else
    let bits = wire - 1 in
    Some
      ({ K.shift = not (Int.equal (bits land 1) 0);
         meta = not (Int.equal (bits land 2) 0) || not (Int.equal (bits land 32) 0);
         ctrl = not (Int.equal (bits land 4) 0) },
       not (Int.equal (bits land 2) 0), not (Int.equal (bits land 8) 0),
       not (Int.equal (bits land 16) 0), not (Int.equal (bits land 64) 0),
       not (Int.equal (bits land 128) 0))

let event_type value = match value with 2 -> K.Repeat, true | 3 -> K.Release, false | _ -> K.Press, false

let parse_event_field value =
  match split_on ':' value with
  | modifier :: event :: _ ->
      (match int_of_digits modifier, int_of_digits event with
      | Some modifier, Some event -> Some (modifier, event)
      | Some modifier, None -> Some (modifier, 1)
      | None, _ -> None)
  | modifier :: [] -> Option.map (fun value -> value, 1) (int_of_digits modifier)
  | [] -> None

let parse_special body terminator =
  match split_on ';' body with
  | key_code :: modifier_field :: _ ->
      let key = if Char.equal terminator '~' then tilde_key key_code else
        match int_of_digits key_code with Some 1 -> functional_key terminator | _ -> None
      in
      (match key, parse_event_field modifier_field with
      | Some named, Some (wire, event) ->
          (match modifiers wire with
          | None -> None
          | Some (modifier, option, super, hyper, caps_lock, num_lock) ->
              let event_type, repeated = event_type event in
              Some { K.key = K.Named named; modifiers = modifier;
                     metadata = K.kitty_metadata ~event_type ~repeated ~option ~super
                       ~hyper ~caps_lock ~num_lock () })
      | _ -> None)
  | _ -> None

let rec parse_unicode body =
  match split_on ';' body with
  | first :: modifier_field :: text_fields ->
      (match split_on ':' first with
      | code_text :: shifted_text :: base_text :: _ ->
          (match int_of_digits code_text, int_of_digits shifted_text, int_of_digits base_text with
          | Some code, shifted, base -> parse_unicode_values code shifted base modifier_field text_fields
          | _ -> None)
      | code_text :: [] ->
          (match int_of_digits code_text with Some code -> parse_unicode_values code None None modifier_field text_fields | None -> None)
      | code_text :: shifted_text :: [] ->
          (match int_of_digits code_text, int_of_digits shifted_text with
          | Some code, shifted -> parse_unicode_values code shifted None modifier_field text_fields
          | _ -> None)
      | _ -> None)
  | first :: [] ->
      (match int_of_digits first with Some code -> parse_unicode_values code None None "1" [] | None -> None)
  | _ -> None

and parse_unicode_values code shifted base modifier_field text_fields =
  let shifted = Option.bind shifted valid_codepoint in
  let named = named_of_code code in
  let base =
    match named with None -> Option.bind base valid_codepoint | Some _ -> None
  in
  match modifiers (match parse_event_field modifier_field with Some (wire, _) -> wire | None -> 1), parse_event_field modifier_field with
  | Some (modifier, option, super, hyper, caps_lock, num_lock), Some (_, event) ->
      let code_bytes = if code = 0 then None else Option.bind (valid_codepoint code) utf8 in
      let explicit_text = text_of_codepoints (List.filter_map int_of_digits text_fields) in
      if (code <> 0 && Option.is_none code_bytes)
         || (code = 0 && String.length explicit_text = 0) then None
      else
          let event_type, repeated = event_type event in
          let key, generated_text, number =
            match named with
            | Some value -> K.Named value, Option.value (keypad_text value) ~default:"", false
            | None ->
                let text =
                  if String.length explicit_text > 0 then explicit_text
                  else
                    match shifted, modifier.shift with
                    | Some value, true ->
                        Option.value (Option.bind (valid_codepoint value) utf8)
                          ~default:(Option.value code_bytes ~default:Bytes.empty)
                        |> Bytes.to_string
                    | None, true ->
                        Option.value code_bytes ~default:Bytes.empty
                        |> uppercase_ascii |> Bytes.to_string
                    | _ -> Option.value code_bytes ~default:Bytes.empty |> Bytes.to_string
                in
                K.Character (Bytes.of_string text), text, false
          in
          let generated_text =
            if String.length generated_text = 0 then explicit_text else generated_text
          in
          Some { K.key; modifiers = modifier;
                 metadata = K.kitty_metadata ~event_type ~repeated ~option ~super ~hyper
                   ~caps_lock ~num_lock ~number
                   ?code:(if code = 0 then None else Some code)
                   ?base_code:base
                   ?text:(if String.length generated_text = 0 then None else Some generated_text) () }
  | _ -> None

let parse raw =
  let source = Bytes.to_string raw in
  let length = String.length source in
  if length < 4 || not (String.equal (String.sub source 0 2) "\027[") then None
  else
    let terminator = String.get source (length - 1) in
    let body = String.sub source 2 (length - 3) in
    if Char.equal terminator 'u' then parse_unicode body
    else if Char.equal terminator '~' || (Char.code terminator >= Char.code 'A' && Char.code terminator <= Char.code 'Z') then parse_special body terminator
    else None

let build_flags ?(disambiguate = true) ?(alternate_keys = true) ?(events = false)
    ?(all_keys_as_escapes = false) ?(report_text = false) () =
  let value = ref 0 in
  if disambiguate then value := !value lor 1;
  if events then value := !value lor 2;
  if alternate_keys then value := !value lor 4;
  if all_keys_as_escapes then value := !value lor 8;
  if report_text then value := !value lor 16;
  !value

let push_sequence ~flags = Bytes.of_string (Printf.sprintf "\027[>%du" flags)
let pop_sequence = Bytes.of_string "\027[<u"
