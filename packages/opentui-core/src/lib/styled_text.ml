type chunk = {
  text : string;
  fg : Color.t option;
  bg : Color.t option;
  attributes : int;
  link : string option;
}

type t = chunk list

type style_attrs = {
  fg : Color.t option;
  bg : Color.t option;
  bold : bool;
  italic : bool;
  underline : bool;
  strikethrough : bool;
  dim : bool;
  reverse : bool;
  blink : bool;
  hidden : bool;
}

type stylable_input = Text of string | Integer of int | Boolean of bool | Chunk of chunk

let chunk ?fg ?bg ?(attributes = 0) ?link text =
  { text; fg; bg; attributes; link }

let create chunks = chunks
let of_string text = [ chunk text ]
let chunks text = text

let plain_text text =
  String.concat "" (List.map (fun chunk -> chunk.text) text)

let is_empty text = List.is_empty text
let append left right = left @ right
let map callback text = List.map callback text

let style_attrs ?fg ?bg ?(bold = false) ?(italic = false) ?(underline = false)
    ?(strikethrough = false) ?(dim = false) ?(reverse = false) ?(blink = false)
    ?(hidden = false) () =
  { fg; bg; bold; italic; underline; strikethrough; dim; reverse; blink; hidden }

let text_of_input = function
  | Text value -> value
  | Integer value -> string_of_int value
  | Boolean value -> string_of_bool value
  | Chunk value -> value.text

let chunk_of_input = function Chunk value -> value | value -> chunk (text_of_input value)

let apply_style input style =
  let existing = chunk_of_input input in
  let style_attributes =
    Text_attributes.of_flags ~bold:style.bold ~italic:style.italic
      ~underline:style.underline ~strikethrough:style.strikethrough
      ~dim:style.dim ~inverse:style.reverse ~blink:style.blink
      ~hidden:style.hidden ()
  in
  {
    text = existing.text;
    fg = (match style.fg with Some value -> Some value | None -> existing.fg);
    bg = (match style.bg with Some value -> Some value | None -> existing.bg);
    attributes = existing.attributes lor style_attributes;
    link = existing.link;
  }

let string_to_styled_text text = of_string text

let link url input =
  let value = chunk_of_input input in
  { value with link = Some url }

let fg color input = apply_style input (style_attrs ~fg:color ())
let bg color input = apply_style input (style_attrs ~bg:color ())
let bold input = apply_style input (style_attrs ~bold:true ())
let italic input = apply_style input (style_attrs ~italic:true ())
let underline input = apply_style input (style_attrs ~underline:true ())
let strikethrough input = apply_style input (style_attrs ~strikethrough:true ())
let dim input = apply_style input (style_attrs ~dim:true ())
let reverse input = apply_style input (style_attrs ~reverse:true ())
let blink input = apply_style input (style_attrs ~blink:true ())
let hidden input = apply_style input (style_attrs ~hidden:true ())

let color ~red ~green ~blue =
  match Color.rgb ~red ~green ~blue with
  | Ok value -> value
  | Error _ -> failwith "styled text color constant is invalid"

let black_color = Color.black
let red_color = color ~red:255 ~green:0 ~blue:0
let green_color = color ~red:0 ~green:128 ~blue:0
let yellow_color = color ~red:128 ~green:128 ~blue:0
let blue_color = color ~red:0 ~green:0 ~blue:255
let magenta_color = color ~red:128 ~green:0 ~blue:128
let cyan_color = color ~red:0 ~green:128 ~blue:128
let white_color = Color.white
let bright_black_color = color ~red:128 ~green:128 ~blue:128
let bright_red_color = color ~red:255 ~green:0 ~blue:0
let bright_green_color = color ~red:0 ~green:255 ~blue:0
let bright_yellow_color = color ~red:255 ~green:255 ~blue:0
let bright_blue_color = color ~red:0 ~green:0 ~blue:255
let bright_magenta_color = color ~red:255 ~green:0 ~blue:255
let bright_cyan_color = color ~red:0 ~green:255 ~blue:255
let bright_white_color = color ~red:255 ~green:255 ~blue:255

let black input = fg black_color input
let red input = fg red_color input
let green input = fg green_color input
let yellow input = fg yellow_color input
let blue input = fg blue_color input
let magenta input = fg magenta_color input
let cyan input = fg cyan_color input
let white input = fg white_color input
let bright_black input = fg bright_black_color input
let bright_red input = fg bright_red_color input
let bright_green input = fg bright_green_color input
let bright_yellow input = fg bright_yellow_color input
let bright_blue input = fg bright_blue_color input
let bright_magenta input = fg bright_magenta_color input
let bright_cyan input = fg bright_cyan_color input
let bright_white input = fg bright_white_color input
let bg_black input = bg black_color input
let bg_red input = bg red_color input
let bg_green input = bg green_color input
let bg_yellow input = bg yellow_color input
let bg_blue input = bg blue_color input
let bg_magenta input = bg magenta_color input
let bg_cyan input = bg cyan_color input
let bg_white input = bg white_color input

let template ~strings ~values =
  let result = ref [] in
  let string_count = List.length strings in
  let value_array = Array.of_list values in
  let string_array = Array.of_list strings in
  for index = 0 to string_count - 1 do
    let value = string_array.(index) in
    if String.length value > 0 then result := !result @ [ chunk value ];
    if Int.compare index (Array.length value_array) < 0 then
      result := !result @ [ chunk_of_input value_array.(index) ]
  done;
  create !result
