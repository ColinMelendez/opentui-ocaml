type colors = {
  palette : string option array;
  default_foreground : string option;
  default_background : string option;
  cursor_color : string option;
  mouse_foreground : string option;
  mouse_background : string option;
  tek_foreground : string option;
  tek_background : string option;
  highlight_background : string option;
  highlight_foreground : string option;
}

type normalized = {
  palette : Rgba.t array;
  default_foreground : Rgba.t;
  default_background : Rgba.t;
}

type state_values = {
  mutable palette : string option array;
  mutable default_foreground : string option;
  mutable default_background : string option;
  mutable cursor_color : string option;
  mutable mouse_foreground : string option;
  mutable mouse_background : string option;
  mutable tek_foreground : string option;
  mutable tek_background : string option;
  mutable highlight_background : string option;
  mutable highlight_foreground : string option;
}

type t = {
  mutable pending : string;
  values : state_values;
  requested_size : int;
  mutable saw_response : bool;
}

let empty_colors size =
  {
    palette = Array.make size None;
    default_foreground = None;
    default_background = None;
    cursor_color = None;
    mouse_foreground = None;
    mouse_background = None;
    tek_foreground = None;
    tek_background = None;
    highlight_background = None;
    highlight_foreground = None;
  }

let create ?(size = 16) () =
  let requested_size = max 0 size in
  {
    pending = "";
    values =
      (let initial = empty_colors requested_size in
       {
         palette = initial.palette;
         default_foreground = initial.default_foreground;
         default_background = initial.default_background;
         cursor_color = initial.cursor_color;
         mouse_foreground = initial.mouse_foreground;
         mouse_background = initial.mouse_background;
         tek_foreground = initial.tek_foreground;
         tek_background = initial.tek_background;
         highlight_background = initial.highlight_background;
         highlight_foreground = initial.highlight_foreground;
       });
    requested_size;
    saw_response = false;
  }

let is_digit character =
  let code = Char.code character in
  Int.compare code (Char.code '0') >= 0
  && Int.compare code (Char.code '9') <= 0

let digit character = Char.code character - Char.code '0'

let parse_decimal source start finish =
  if start >= finish then None
  else
    let result = ref 0 in
    let valid = ref true in
    let cursor = ref start in
    while !cursor < finish do
      let character = String.get source !cursor in
      if not (is_digit character) then valid := false
      else if !result > (max_int - digit character) / 10 then valid := false
      else result := (!result * 10) + digit character;
      incr cursor
    done;
    if !valid then Some !result else None

let hex_value character =
  let code = Char.code character in
  if Int.compare code (Char.code '0') >= 0 && Int.compare code (Char.code '9') <= 0 then
    Some (code - Char.code '0')
  else if Int.compare code (Char.code 'a') >= 0 && Int.compare code (Char.code 'f') <= 0 then
    Some (code - Char.code 'a' + 10)
  else if Int.compare code (Char.code 'A') >= 0 && Int.compare code (Char.code 'F') <= 0 then
    Some (code - Char.code 'A' + 10)
  else None

let parse_hex_component source start finish =
  if start >= finish then None
  else
    let value = ref 0 in
    let maximum = ref 0 in
    let valid = ref true in
    let cursor = ref start in
    while !cursor < finish do
      match hex_value (String.get source !cursor) with
      | None -> valid := false
      | Some digit ->
          value := (!value * 16) + digit;
          maximum := (!maximum * 16) + 15;
      incr cursor
    done;
    if not !valid || Int.equal !maximum 0 then None
    else Some (int_of_float (Float.round (float_of_int !value *. 255.0 /. float_of_int !maximum)))

let color_of_payload payload =
  let length = String.length payload in
  if length = 7 && Char.equal (String.get payload 0) '#' then
    match
      parse_hex_component payload 1 3,
      parse_hex_component payload 3 5,
      parse_hex_component payload 5 7
    with
    | Some red, Some green, Some blue ->
        let result = Bytes.create 7 in
        let to_hex value = String.get "0123456789abcdef" value in
        Bytes.set result 0 '#';
        List.iteri
          (fun index value ->
            Bytes.set result (1 + (index * 2)) (to_hex (value lsr 4));
            Bytes.set result (2 + (index * 2)) (to_hex (value land 15)))
          [ red; green; blue ];
        Some (Bytes.unsafe_to_string result)
    | _ -> None
  else if String.length payload > 4 && String.sub payload 0 4 = "rgb:" then
    let starts = ref [ 4 ] in
    for index = 4 to length - 1 do
      if Char.equal (String.get payload index) '/' then
        starts := (index + 1) :: !starts
    done;
    let boundaries = List.rev !starts in
    match boundaries with
    | red_start :: green_start :: blue_start :: _ ->
        let red_end = green_start - 1 in
        let green_end = blue_start - 1 in
        (match
           parse_hex_component payload red_start red_end,
           parse_hex_component payload green_start green_end,
           parse_hex_component payload blue_start length
         with
        | Some red, Some green, Some blue ->
            let result = Bytes.create 7 in
            let to_hex value = String.get "0123456789abcdef" value in
            Bytes.set result 0 '#';
            List.iteri
              (fun index value ->
                Bytes.set result (1 + (index * 2)) (to_hex (value lsr 4));
                Bytes.set result (2 + (index * 2)) (to_hex (value land 15)))
              [ red; green; blue ];
            Some (Bytes.unsafe_to_string result)
        | _ -> None)
    | _ -> None
  else None

let find_terminator source start =
  let result = ref None in
  let cursor = ref start in
  while !cursor < String.length source && Option.is_none !result do
    if Char.equal (String.get source !cursor) (Char.chr 7) then result := Some !cursor
    else if
      Char.equal (String.get source !cursor) (Char.chr 27)
      && !cursor + 1 < String.length source
      && Char.equal (String.get source (!cursor + 1)) '\\'
    then result := Some !cursor;
    incr cursor
  done;
  !result

let starts_with source prefix =
  String.length source >= String.length prefix
  && String.equal (String.sub source 0 (String.length prefix)) prefix

let set_special values index color =
  match index with
  | 10 -> values.default_foreground <- color
  | 11 -> values.default_background <- color
  | 12 -> values.cursor_color <- color
  | 13 -> values.mouse_foreground <- color
  | 14 -> values.mouse_background <- color
  | 15 -> values.tek_foreground <- color
  | 16 -> values.tek_background <- color
  | 17 -> values.highlight_background <- color
  | 19 -> values.highlight_foreground <- color
  | _ -> ()

let parse_body state body =
  if starts_with body "4;" then begin
    let separator = String.index_from_opt body 2 ';' in
    match separator with
    | None -> ()
    | Some position ->
        (match parse_decimal body 2 position with
        | Some palette_index
          when palette_index >= 0 && palette_index < state.requested_size ->
            let payload = String.sub body (position + 1) (String.length body - position - 1) in
            state.values.palette.(palette_index) <- color_of_payload payload;
            state.saw_response <- true
        | Some _ | None -> ())
  end else
    match String.index_opt body ';' with
    | None -> ()
    | Some separator ->
        (match parse_decimal body 0 separator with
        | None -> ()
        | Some index ->
            let payload = String.sub body (separator + 1) (String.length body - separator - 1) in
            set_special state.values index (color_of_payload payload);
            state.saw_response <- true)

let feed state fragment =
  state.pending <- state.pending ^ fragment;
  let source = state.pending in
  let cursor = ref 0 in
  let retained = ref None in
  while !cursor < String.length source do
    match String.index_from_opt source !cursor (Char.chr 27) with
    | None -> cursor := String.length source
    | Some escape_position ->
        if escape_position + 1 >= String.length source
           || not (Char.equal (String.get source (escape_position + 1)) ']')
        then cursor := escape_position + 1
        else
          match find_terminator source (escape_position + 2) with
          | None ->
              retained := Some escape_position;
              cursor := String.length source
          | Some terminator ->
              let body = String.sub source (escape_position + 2) (terminator - escape_position - 2) in
              parse_body state body;
              cursor :=
                if Char.equal (String.get source terminator) (Char.chr 7) then terminator + 1
                else terminator + 2
  done;
  state.pending <-
    match !retained with
    | None -> ""
    | Some start -> String.sub source start (String.length source - start)

let colors (state : t) : colors =
  {
    palette = Array.copy state.values.palette;
    default_foreground = state.values.default_foreground;
    default_background = state.values.default_background;
    cursor_color = state.values.cursor_color;
    mouse_foreground = state.values.mouse_foreground;
    mouse_background = state.values.mouse_background;
    tek_foreground = state.values.tek_foreground;
    tek_background = state.values.tek_background;
    highlight_background = state.values.highlight_background;
    highlight_foreground = state.values.highlight_foreground;
  }

let complete state = state.saw_response && Int.equal (String.length state.pending) 0

let palette_query ?(size = 16) () =
  let count = max 0 size in
  let result = Stdlib.Buffer.create (count * 8) in
  for index = 0 to count - 1 do
    Stdlib.Buffer.add_string result (Printf.sprintf "\027]4;%d;?\007" index)
  done;
  Stdlib.Buffer.contents result

let special_query ?(is_tmux = false) () =
  let indices = if is_tmux then [ 10; 11; 12 ] else [ 10; 11; 12; 13; 14; 15; 16; 17; 19 ] in
  String.concat "" (List.map (fun index -> Printf.sprintf "\027]%d;?\007" index) indices)

let osc_support_query () = "\027]4;0;?\007"

let wrap_for_legacy_tmux osc =
  let escaped = String.concat "" (List.map (fun character -> if Char.equal character (Char.chr 27) then "\027\027" else String.make 1 character) (List.init (String.length osc) (String.get osc))) in
  "\027Ptmux;" ^ escaped ^ "\027\\"

let fallback_palette () =
  Array.init 256 (fun index ->
      match Rgba.ansi256_index_to_rgb index with
      | Ok (red, green, blue) -> Rgba.from_ints red green blue
      | Error error ->
          ignore error;
          Rgba.from_ints 0 0 0)

let fallback () =
  {
    palette = fallback_palette ();
    default_foreground = Rgba.from_ints 255 255 255;
    default_background = Rgba.from_ints 0 0 0;
  }

let normalize (colors : colors option) =
  let base = fallback () in
  match colors with
  | None -> base
  | Some colors ->
      let palette = Array.copy base.palette in
      let limit = min 256 (Array.length colors.palette) in
      for index = 0 to limit - 1 do
        match colors.palette.(index) with
        | None -> ()
        | Some value ->
            (match Rgba.of_hex value with
            | Ok color -> palette.(index) <- color
            | Error error -> ignore error)
      done;
      let special fallback_value detected =
        match detected with
        | None -> fallback_value
        | Some value ->
            (match Rgba.of_hex value with
            | Ok color -> color
            | Error error ->
                ignore error;
                fallback_value)
      in
      {
        palette;
        default_foreground = special base.default_foreground colors.default_foreground;
        default_background = special base.default_background colors.default_background;
      }
