type pixel_resolution = {
  width : int32;
  height : int32;
}

let escape = Char.chr 27
let bell = Char.chr 7
let backslash = Char.chr 92

let is_digit character =
  let code = Char.code character in
  Int.compare code (Char.code '0') >= 0
  && Int.compare code (Char.code '9') <= 0

let starts_at source position marker =
  let source_length = String.length source in
  let marker_length = String.length marker in
  Int.compare position 0 >= 0
  && Int.compare (position + marker_length) source_length <= 0
  && String.sub source position marker_length |> String.equal marker

let lowercase_ascii character =
  let code = Char.code character in
  if Int.compare code (Char.code 'A') >= 0
     && Int.compare code (Char.code 'Z') <= 0
  then Char.chr (code + (Char.code 'a' - Char.code 'A'))
  else character

let starts_at_case_insensitive source position marker =
  let source_length = String.length source in
  let marker_length = String.length marker in
  if Int.compare position 0 < 0
     || Int.compare (position + marker_length) source_length > 0
  then false
  else begin
    let matches = ref true in
    for offset = 0 to marker_length - 1 do
      if
        not
          (Char.equal
             (lowercase_ascii (String.get source (position + offset)))
             (lowercase_ascii (String.get marker offset)))
      then matches := false
    done;
    !matches
  end

let find_substring source marker position =
  let source_length = String.length source in
  let result = ref None in
  let cursor = ref position in
  while Int.compare !cursor source_length <= 0 && Option.is_none !result do
    if starts_at source !cursor marker then result := Some !cursor;
    incr cursor
  done;
  !result

let find_terminated source position =
  let source_length = String.length source in
  let result = ref None in
  let cursor = ref position in
  while Int.compare !cursor source_length < 0 && Option.is_none !result do
    if Char.equal (String.get source !cursor) bell then result := Some !cursor
    else if
      Char.equal (String.get source !cursor) escape
      && Int.compare (!cursor + 1) source_length < 0
      && Char.equal (String.get source (!cursor + 1)) backslash
    then result := Some !cursor;
    incr cursor
  done;
  !result

let find_escape_terminated source position =
  let source_length = String.length source in
  let result = ref None in
  let cursor = ref position in
  while Int.compare !cursor source_length < 0 && Option.is_none !result do
    if
      Char.equal (String.get source !cursor) escape
      && Int.compare (!cursor + 1) source_length < 0
      && Char.equal (String.get source (!cursor + 1)) backslash
    then result := Some !cursor;
    incr cursor
  done;
  !result

let find_strict_escape_terminated source position =
  let source_length = String.length source in
  let result = ref None in
  let valid = ref true in
  let cursor = ref position in
  while Int.compare !cursor source_length < 0 && !valid && Option.is_none !result do
    if Char.equal (String.get source !cursor) escape then
      if
        Int.compare (!cursor + 1) source_length < 0
        && Char.equal (String.get source (!cursor + 1)) backslash
      then result := Some !cursor
      else valid := false
    else incr cursor
  done;
  !result

let consume_digits source position =
  let source_length = String.length source in
  let cursor = ref position in
  while Int.compare !cursor source_length < 0 && is_digit (String.get source !cursor) do
    incr cursor
  done;
  if Int.equal !cursor position then None else Some !cursor

let match_decrpm source position =
  if not (starts_at source position "\027[?") then false
  else
    match consume_digits source (position + 3) with
    | None -> false
    | Some after_first_number ->
        let cursor = ref after_first_number in
        let valid = ref true in
        while
          !valid
          && Int.compare !cursor (String.length source) < 0
          && Char.equal (String.get source !cursor) ';'
        do
          match consume_digits source (!cursor + 1) with
          | None -> valid := false
          | Some after_number -> cursor := after_number
        done;
        !valid && starts_at source !cursor "$y"

let match_capability_cpr source position =
  if not (starts_at source position "\027[1;") then false
  else
    let digits_start = position + 4 in
    match consume_digits source digits_start with
    | None -> false
    | Some after_digits when
        Int.compare after_digits (String.length source) < 0
        && Char.equal (String.get source after_digits) 'R' ->
        let digits = String.sub source digits_start (after_digits - digits_start) in
        not (String.equal digits "1")
    | Some _ -> false

let match_xtversion source position =
  starts_at source position "\027P>|"
  && Option.is_some (find_escape_terminated source (position + 4))

let match_xtgettcap source position =
  if not (starts_at source position "\027P") then false
  else
    let after_prefix = position + 2 in
    let has_payload after_payload =
      if
        starts_at source after_payload "\027\\"
      then true
      else if
        Int.compare after_payload (String.length source) < 0
        && Char.equal (String.get source after_payload) '='
      then
        Option.is_some
          (find_strict_escape_terminated source (after_payload + 1))
      else false
    in
    (starts_at_case_insensitive source after_prefix "1+r4d73"
     && has_payload (after_prefix + 7))
    ||
    if starts_at_case_insensitive source after_prefix "0+r" then
      let after_zero = after_prefix + 3 in
      let optional_payload_length =
        if starts_at_case_insensitive source after_zero "4d73" then 4 else 0
      in
      let after_payload = after_zero + optional_payload_length in
      Option.is_some (find_strict_escape_terminated source after_payload)
    else false

let match_kitty_graphics source position =
  starts_at source position "\027_G"
  && Option.is_some (find_escape_terminated source (position + 3))

let match_kitty_keyboard source position =
  if not (starts_at source position "\027[?") then false
  else
    match consume_digits source (position + 3) with
    | None -> false
    | Some after_first_number ->
        let cursor = ref after_first_number in
        let valid = ref true in
        if
          Int.compare !cursor (String.length source) < 0
          && Char.equal (String.get source !cursor) ';'
        then begin
          match consume_digits source (!cursor + 1) with
          | None -> valid := false
          | Some after_second_number -> cursor := after_second_number
        end;
        !valid
        && starts_at source !cursor "u"

let match_da1 source position =
  if not (starts_at source position "\027[?") then false
  else
    let cursor = ref (position + 3) in
    while
      Int.compare !cursor (String.length source) < 0
      && (is_digit (String.get source !cursor)
          || Char.equal (String.get source !cursor) ';')
    do
      incr cursor
    done;
    starts_at source !cursor "c"

let match_osc99 source position =
  let prefix = "\027]99;" in
  if not (starts_at source position prefix) then false
  else
    match find_terminated source (position + String.length prefix) with
    | None -> false
    | Some terminator ->
        let body =
          String.sub source
            (position + String.length prefix)
            (terminator - position - String.length prefix)
        in
        let input_marker = "i=opentui-notifications" in
        let parameter_marker = "p=?" in
        match find_substring body input_marker 0 with
        | None -> false
        | Some input_start ->
            Option.is_some
              (find_substring body parameter_marker
                 (input_start + String.length input_marker))

let match_osc1337 source position =
  let prefix = "\027]1337;Capabilities=" in
  starts_at source position prefix
  && Option.is_some (find_terminated source (position + String.length prefix))

let capability_match_at source position =
  match_decrpm source position
  || match_capability_cpr source position
  || match_xtversion source position
  || match_xtgettcap source position
  || match_kitty_graphics source position
  || match_kitty_keyboard source position
  || match_da1 source position
  || match_osc99 source position
  || match_osc1337 source position

let first_capability_match source =
  let source_length = String.length source in
  let result = ref None in
  let cursor = ref 0 in
  while Int.compare !cursor source_length < 0 && Option.is_none !result do
    if Char.equal (String.get source !cursor) escape
       && capability_match_at source !cursor
    then result := Some !cursor;
    incr cursor
  done;
  !result

let is_capability_response sequence =
  Option.is_some (first_capability_match sequence)

type pixel_match = {
  height_start : int;
  height_end : int;
  width_start : int;
  width_end : int;
}

let pixel_match_at source position =
  if not (starts_at source position "\027[4;") then None
  else
    match consume_digits source (position + 4) with
    | None -> None
    | Some height_end ->
        if
          Int.compare height_end (String.length source) >= 0
          || not (Char.equal (String.get source height_end) ';')
        then None
        else
          match consume_digits source (height_end + 1) with
          | None -> None
          | Some width_end when
              starts_at source width_end "t" ->
              Some
                {
                  height_start = position + 4;
                  height_end;
                  width_start = height_end + 1;
                  width_end;
                }
          | Some _ -> None

let first_pixel_match sequence =
  let source_length = String.length sequence in
  let result = ref None in
  let cursor = ref 0 in
  while Int.compare !cursor source_length < 0 && Option.is_none !result do
    if Char.equal (String.get sequence !cursor) escape then
      result := pixel_match_at sequence !cursor;
    incr cursor
  done;
  !result

let is_pixel_resolution_response sequence =
  Option.is_some (first_pixel_match sequence)

let bounded_integer source start_index end_index =
  let maximum = 2_147_483_647L in
  let value = ref 0L in
  let valid = ref true in
  for index = start_index to end_index - 1 do
    let digit = Int64.of_int (Char.code (String.get source index) - Char.code '0') in
    if Int64.compare !value (Int64.div (Int64.sub maximum digit) 10L) > 0 then
      valid := false
    else value := Int64.add (Int64.mul !value 10L) digit
  done;
  if !valid then Some (Int32.of_int (Int64.to_int !value)) else None

let parse_pixel_resolution sequence =
  match first_pixel_match sequence with
  | None -> None
  | Some match_ ->
      (match
         bounded_integer sequence match_.height_start match_.height_end,
         bounded_integer sequence match_.width_start match_.width_end
       with
      | Some height, Some width -> Some { width; height }
      | None, _ | _, None -> None)

let pixel_resolution_query () = "\027[14t"
