type style = Single | Double | Rounded | Heavy

type side = Top | Right | Bottom | Left

type border = No_border | All_borders | Sides of side list

type alignment = Left | Center | Right

type sides = {
  top : bool;
  right : bool;
  bottom : bool;
  left : bool;
}

type characters = { codepoints : int32 array }

let no_border = No_border
let all_borders = All_borders

let invalid_argument =
  Error.Native (Native.Error.Native Opentui_raw.Error.Invalid_argument)

let has_side side sides =
  let rec loop = function
    | [] -> false
    | current :: rest ->
        (match side, current with
        | Top, Top | Right, Right | Bottom, Bottom | Left, Left -> true
        | _ -> loop rest)
  in
  loop sides

let to_sides = function
  | No_border -> { top = false; right = false; bottom = false; left = false }
  | All_borders -> { top = true; right = true; bottom = true; left = true }
  | Sides sides ->
      {
        top = has_side Top sides;
        right = has_side Right sides;
        bottom = has_side Bottom sides;
        left = has_side Left sides;
      }

let top sides = sides.top
let right sides = sides.right
let bottom sides = sides.bottom
let left sides = sides.left

let codepoint value = Int32.of_int value

let make_characters codepoints = { codepoints = Array.of_list codepoints }

let single_characters =
  make_characters
    [
      codepoint 0x250c;
      codepoint 0x2510;
      codepoint 0x2514;
      codepoint 0x2518;
      codepoint 0x2500;
      codepoint 0x2502;
      codepoint 0x252c;
      codepoint 0x2534;
      codepoint 0x251c;
      codepoint 0x2524;
      codepoint 0x253c;
    ]

let double_characters =
  make_characters
    [
      codepoint 0x2554;
      codepoint 0x2557;
      codepoint 0x255a;
      codepoint 0x255d;
      codepoint 0x2550;
      codepoint 0x2551;
      codepoint 0x2566;
      codepoint 0x2569;
      codepoint 0x2560;
      codepoint 0x2563;
      codepoint 0x256c;
    ]

let rounded_characters =
  make_characters
    [
      codepoint 0x256d;
      codepoint 0x256e;
      codepoint 0x2570;
      codepoint 0x256f;
      codepoint 0x2500;
      codepoint 0x2502;
      codepoint 0x252c;
      codepoint 0x2534;
      codepoint 0x251c;
      codepoint 0x2524;
      codepoint 0x253c;
    ]

let heavy_characters =
  make_characters
    [
      codepoint 0x250f;
      codepoint 0x2513;
      codepoint 0x2517;
      codepoint 0x251b;
      codepoint 0x2501;
      codepoint 0x2503;
      codepoint 0x2533;
      codepoint 0x253b;
      codepoint 0x2523;
      codepoint 0x252b;
      codepoint 0x254b;
    ]

let characters style =
  match style with
  | Single -> single_characters
  | Double -> double_characters
  | Rounded -> rounded_characters
  | Heavy -> heavy_characters

let of_codepoints codepoints =
  if Array.length codepoints <> 11 then Error invalid_argument
  else begin
    let valid = ref true in
    for index = 0 to Array.length codepoints - 1 do
      if Int32.compare codepoints.(index) 0l < 0 then valid := false
    done;
    if not !valid then Error invalid_argument
    else Ok { codepoints = Array.copy codepoints }
  end

let alignment_code = function Left -> 0 | Center -> 1 | Right -> 2

let border_bits border =
  let sides = to_sides border in
  let bits = ref 0 in
  if sides.left then bits := !bits lor 0b0001;
  if sides.bottom then bits := !bits lor 0b0010;
  if sides.right then bits := !bits lor 0b0100;
  if sides.top then bits := !bits lor 0b1000;
  !bits

module Private = struct
  let to_native characters = characters.codepoints

  let pack_draw_options ~border ~should_fill ~title_alignment
      ~bottom_title_alignment =
    let bits = border_bits border in
    let bits = if should_fill then bits lor (1 lsl 4) else bits in
    let bits = bits lor (alignment_code title_alignment lsl 5) in
    let bits = bits lor (alignment_code bottom_title_alignment lsl 7) in
    Int32.of_int bits
end
