type highlight = {
  start : int;
  end_ : int;
  style_id : int;
  priority : int option;
  hl_ref : int option;
}

type t = {
  raw : Opentui_raw.Text_buffer.t;
  mutable text : string;
  mutable styled_text : Lib.Styled_text.t option;
  mutable default_fg : Color.t option;
  mutable default_bg : Color.t option;
  mutable default_attributes : int option;
  mutable syntax_style : Syntax_style.t option;
  mutable tab_width : int;
  width_method : Lib.Text_metrics.width_method;
  highlights : (int, highlight list) Hashtbl.t;
}

let normalize_line_endings value =
  let result = Stdlib.Buffer.create (String.length value) in
  let index = ref 0 in
  while !index < String.length value do
    let character = String.get value !index in
    if Char.equal character '\r' then begin
      Stdlib.Buffer.add_char result '\n';
      incr index;
      if !index < String.length value && Char.equal (String.get value !index) '\n'
      then incr index
    end else begin
      Stdlib.Buffer.add_char result character;
      incr index
    end
  done;
  Stdlib.Buffer.contents result

let of_raw raw width_method =
  {
    raw;
    text = "";
    styled_text = None;
    default_fg = None;
    default_bg = None;
    default_attributes = None;
    syntax_style = None;
    tab_width = 2;
    width_method;
    highlights = Hashtbl.create 8;
  }

let raw buffer = buffer.raw
let is_open buffer = Opentui_raw.Text_buffer.Private.is_open buffer.raw
let width_method buffer = buffer.width_method

let text buffer = buffer.text
let set_text buffer value =
  buffer.text <- normalize_line_endings value;
  buffer.styled_text <- None

let append_text buffer value =
  buffer.text <- buffer.text ^ normalize_line_endings value;
  buffer.styled_text <- None
let clear_text buffer = buffer.text <- ""; buffer.styled_text <- None
let reset_text buffer =
  buffer.text <- "";
  buffer.styled_text <- None;
  Hashtbl.clear buffer.highlights

let styled_text buffer = buffer.styled_text
let set_styled_text buffer value =
  buffer.styled_text <- Some value;
  buffer.text <- normalize_line_endings (Lib.Styled_text.plain_text value);
  Hashtbl.clear buffer.highlights

let default_fg buffer = buffer.default_fg
let set_default_fg buffer value = buffer.default_fg <- value
let default_bg buffer = buffer.default_bg
let set_default_bg buffer value = buffer.default_bg <- value
let default_attributes buffer = buffer.default_attributes
let set_default_attributes buffer value = buffer.default_attributes <- value

let reset_defaults buffer =
  buffer.default_fg <- None;
  buffer.default_bg <- None;
  buffer.default_attributes <- None

let syntax_style buffer = buffer.syntax_style
let set_syntax_style buffer value = buffer.syntax_style <- value

let tab_width buffer = buffer.tab_width
let set_tab_width buffer value = buffer.tab_width <- value

let add_highlight buffer ~line highlight =
  let current = Option.value (Hashtbl.find_opt buffer.highlights line) ~default:[] in
  Hashtbl.replace buffer.highlights line (highlight :: current)

let remove_highlights_by_ref buffer reference =
  Hashtbl.iter
    (fun line highlights ->
      Hashtbl.replace buffer.highlights line
        (List.filter
           (fun highlight -> not (Option.equal Int.equal highlight.hl_ref (Some reference)))
           highlights))
    buffer.highlights

let clear_line_highlights buffer line = Hashtbl.remove buffer.highlights line
let clear_all_highlights buffer = Hashtbl.clear buffer.highlights
let line_highlights buffer line = Option.value (Hashtbl.find_opt buffer.highlights line) ~default:[]

let highlight_count buffer =
  Hashtbl.fold (fun _ highlights count -> count + List.length highlights) buffer.highlights 0
