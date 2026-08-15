type rgb_triplet = int * int * int

type color_intent = Rgb | Indexed | Default

type t = {
  red : int;
  green : int;
  blue : int;
  alpha : int;
  intent : color_intent;
  slot : int option;
}

let clamp value = max 0 (min 255 value)

let from_ints ?(alpha = 255) red green blue =
  {
    red = clamp red;
    green = clamp green;
    blue = clamp blue;
    alpha = clamp alpha;
    intent = Rgb;
    slot = None;
  }

let finite value =
  match classify_float value with FP_nan | FP_infinite -> 0.0 | FP_normal | FP_subnormal | FP_zero -> value

let from_values ?(alpha = 1.0) red green blue =
  let byte value = int_of_float (Float.round (max 0.0 (min 1.0 (finite value)) *. 255.0)) in
  from_ints ~alpha:(byte alpha) (byte red) (byte green) (byte blue)

let normalize_index index =
  if Int.compare index 0 < 0 || Int.compare index 255 > 0 then
    Error "indexed color must be in the range 0..255"
  else Ok index

let ansi16 =
  [|
    (0, 0, 0);
    (128, 0, 0);
    (0, 128, 0);
    (128, 128, 0);
    (0, 0, 128);
    (128, 0, 128);
    (0, 128, 128);
    (192, 192, 192);
    (128, 128, 128);
    (255, 0, 0);
    (0, 255, 0);
    (255, 255, 0);
    (0, 0, 255);
    (255, 0, 255);
    (0, 255, 255);
    (255, 255, 255);
  |]

let ansi256_index_to_rgb index =
  match normalize_index index with
  | Error error -> Error error
  | Ok index when Int.compare index 16 < 0 -> Ok ansi16.(index)
  | Ok index when Int.compare index 232 < 0 ->
      let cube = index - 16 in
      let levels = [| 0; 95; 135; 175; 215; 255 |] in
      Ok (levels.(cube / 36), levels.((cube / 6) mod 6), levels.(cube mod 6))
  | Ok index ->
      let value = 8 + ((index - 232) * 10) in
      Ok (value, value, value)

let from_index ?snapshot index =
  match normalize_index index with
  | Error error -> Error error
  | Ok index ->
      let base =
        match snapshot with
        | Some value -> value
        | None ->
            (match ansi256_index_to_rgb index with
            | Ok (red, green, blue) -> from_ints red green blue
            | Error error ->
                ignore error;
                from_ints 0 0 0)
      in
      Ok { base with intent = Indexed; slot = Some index }

let default_foreground ?snapshot () =
  let base = Option.value snapshot ~default:(from_ints 255 255 255) in
  { base with intent = Default; slot = None }

let default_background ?snapshot () =
  let base = Option.value snapshot ~default:(from_ints 0 0 0) in
  { base with intent = Default; slot = None }

let hex_value character =
  let code = Char.code character in
  if Int.compare code (Char.code '0') >= 0 && Int.compare code (Char.code '9') <= 0 then
    Some (code - Char.code '0')
  else if Int.compare code (Char.code 'a') >= 0 && Int.compare code (Char.code 'f') <= 0 then
    Some (code - Char.code 'a' + 10)
  else if Int.compare code (Char.code 'A') >= 0 && Int.compare code (Char.code 'F') <= 0 then
    Some (code - Char.code 'A' + 10)
  else None

let byte_of_hex source start =
  match hex_value (String.get source start), hex_value (String.get source (start + 1)) with
  | Some high, Some low -> Some ((high lsl 4) lor low)
  | Some _, None | None, Some _ | None, None -> None

let of_hex source =
  let start =
    if String.length source > 0 && Char.equal (String.get source 0) '#' then 1 else 0
  in
  let length = String.length source - start in
  if not (List.exists (Int.equal length) [ 3; 4; 6; 8 ]) then
    Error "hex color must contain 3, 4, 6, or 8 digits"
  else
    let nibble index = hex_value (String.get source (start + index)) in
    let expanded index =
      Option.map (fun value -> (value lsl 4) lor value) (nibble index)
    in
    let byte index = byte_of_hex source (start + index) in
    if Int.equal length 3 then
      match expanded 0, expanded 1, expanded 2 with
      | Some red, Some green, Some blue -> Ok (from_ints red green blue)
      | _ -> Error "hex color contains a non-hexadecimal digit"
    else if Int.equal length 4 then
      match expanded 0, expanded 1, expanded 2, expanded 3 with
      | Some red, Some green, Some blue, Some alpha ->
          Ok (from_ints ~alpha red green blue)
      | _ -> Error "hex color contains a non-hexadecimal digit"
    else
      match byte 0, byte 2, byte 4 with
      | Some red, Some green, Some blue ->
          let alpha = if Int.equal length 8 then byte 6 else Some 255 in
          (match alpha with
          | Some alpha -> Ok (from_ints ~alpha red green blue)
          | None -> Error "hex color contains a non-hexadecimal digit")
      | _ -> Error "hex color contains a non-hexadecimal digit"

let parse source =
  match String.lowercase_ascii source with
  | "black" -> Ok (from_ints 0 0 0)
  | "white" -> Ok (from_ints 255 255 255)
  | "red" -> Ok (from_ints 255 0 0)
  | "green" -> Ok (from_ints 0 128 0)
  | "blue" -> Ok (from_ints 0 0 255)
  | "yellow" -> Ok (from_ints 255 255 0)
  | "cyan" | "aqua" -> Ok (from_ints 0 255 255)
  | "magenta" | "fuchsia" -> Ok (from_ints 255 0 255)
  | "silver" -> Ok (from_ints 192 192 192)
  | "gray" | "grey" -> Ok (from_ints 128 128 128)
  | "maroon" -> Ok (from_ints 128 0 0)
  | "olive" -> Ok (from_ints 128 128 0)
  | "lime" -> Ok (from_ints 0 255 0)
  | "teal" -> Ok (from_ints 0 128 128)
  | "navy" -> Ok (from_ints 0 0 128)
  | "purple" -> Ok (from_ints 128 0 128)
  | "orange" -> Ok (from_ints 255 165 0)
  | "transparent" -> Ok (from_ints ~alpha:0 0 0 0)
  | "brightblack" -> Ok (from_ints 102 102 102)
  | "brightred" -> Ok (from_ints 255 102 102)
  | "brightgreen" -> Ok (from_ints 102 255 102)
  | "brightyellow" -> Ok (from_ints 255 255 102)
  | "brightblue" -> Ok (from_ints 102 102 255)
  | "brightmagenta" -> Ok (from_ints 255 102 255)
  | "brightcyan" -> Ok (from_ints 102 255 255)
  | "brightwhite" -> Ok (from_ints 255 255 255)
  | "default" -> Ok (default_foreground ())
  | value ->
      if String.length value > 0 && Char.equal (String.get value 0) '#' then of_hex value
      else Error "unknown color name"

let clone color = color
let channels color = color.red, color.green, color.blue, color.alpha
let to_ints = channels
let map color callback =
  callback (float_of_int color.red /. 255.0),
  callback (float_of_int color.green /. 255.0),
  callback (float_of_int color.blue /. 255.0),
  callback (float_of_int color.alpha /. 255.0)
let red color = color.red
let green color = color.green
let blue color = color.blue
let alpha color = color.alpha
let intent color = color.intent
let slot color = color.slot

let to_color color =
  let red, green, blue, alpha = channels color in
  Color.rgba ~red ~green ~blue ~alpha

let hex_digit value = String.get "0123456789abcdef" value

let to_hex color =
  let length = if Int.equal color.alpha 255 then 7 else 9 in
  let result = Bytes.create length in
  Bytes.set result 0 '#';
  let channels = [| color.red; color.green; color.blue; color.alpha |] in
  let last_channel = if Int.equal length 7 then 2 else 3 in
  for channel = 0 to last_channel do
    let value = channels.(channel) in
    Bytes.set result ((channel * 2) + 1) (hex_digit (value lsr 4));
    Bytes.set result ((channel * 2) + 2) (hex_digit (value land 15))
  done;
  Bytes.unsafe_to_string result

let rgb_to_hex = to_hex

let hsv_to_rgb hue saturation value =
  let sector_value = Float.floor (hue /. 60.0) in
  let sector = Int.rem (int_of_float sector_value) 6 in
  let sector = if Int.compare sector 0 < 0 then sector + 6 else sector in
  let fraction = hue /. 60.0 -. sector_value in
  let p = value *. (1.0 -. saturation) in
  let q = value *. (1.0 -. (fraction *. saturation)) in
  let t = value *. (1.0 -. ((1.0 -. fraction) *. saturation)) in
  match sector with
  | 0 -> from_values value t p
  | 1 -> from_values q value p
  | 2 -> from_values p value t
  | 3 -> from_values p q value
  | 4 -> from_values t p value
  | _ -> from_values value p q

let equal left right =
  Int.equal left.red right.red && Int.equal left.green right.green
  && Int.equal left.blue right.blue && Int.equal left.alpha right.alpha
  &&
  (match left.intent, right.intent with
  | Rgb, Rgb | Indexed, Indexed | Default, Default -> true
  | Rgb, Indexed | Rgb, Default | Indexed, Rgb | Indexed, Default
  | Default, Rgb | Default, Indexed -> false)
  &&
  (match left.slot, right.slot with
  | None, None -> true
  | Some left, Some right -> Int.equal left right
  | None, Some _ | Some _, None -> false)
