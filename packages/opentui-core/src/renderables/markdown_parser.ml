type inline =
  | Text of string
  | Emphasis of inline list
  | Strong of inline list
  | Delete of inline list
  | Code_span of string
  | Link of { label : inline list; href : string }
  | Image of { alt : string; href : string }
  | Hard_break

type alignment = Align_left | Align_center | Align_right | Align_default
type list_item = { raw : string; inlines : inline list }

type token =
  | Heading of { level : int; raw : string; inlines : inline list }
  | Paragraph of { raw : string; inlines : inline list }
  | Code_block of { raw : string; language : string option; text : string }
  | Blockquote of { raw : string; inlines : inline list }
  | Unordered_list of { raw : string; items : list_item list }
  | Ordered_list of { raw : string; start : int; items : list_item list }
  | Table of { raw : string; headers : inline list list; rows : inline list list list; alignments : alignment list }
  | Horizontal_rule of string
  | Html of string

type parsed = { content : string; tokens : token list; stable_token_count : int }

let trim = String.trim

let starts_with_at source index prefix =
  let prefix_length = String.length prefix in
  index >= 0 && index + prefix_length <= String.length source
  && String.equal (String.sub source index prefix_length) prefix

let find_from source start needle =
  let needle_length = String.length needle in
  let limit = String.length source - needle_length in
  let result = ref None in
  let index = ref start in
  while !index <= limit && Option.is_none !result do
    if String.equal (String.sub source !index needle_length) needle then result := Some !index;
    incr index
  done;
  !result

let utf8_width byte =
  let code = Char.code byte in
  if code land 0x80 = 0 then 1
  else if code land 0xE0 = 0xC0 then 2
  else if code land 0xF0 = 0xE0 then 3
  else if code land 0xF8 = 0xF0 then 4
  else 1

let next_codepoint source index finish =
  if index >= finish then finish
  else min finish (index + utf8_width (String.get source index))

let rec parse_inline source offset finish =
  if offset >= finish then []
  else if starts_with_at source offset "\\" && offset + 1 < finish then
    Text (String.sub source (offset + 1) 1) :: parse_inline source (offset + 2) finish
  else if starts_with_at source offset "\n" then
    Hard_break :: parse_inline source (offset + 1) finish
  else if starts_with_at source offset "![" then
    (match find_from source (offset + 2) "](" with
    | Some separator when separator < finish ->
        (match find_from source (separator + 2) ")" with
        | Some close when close < finish ->
            let alt = String.sub source (offset + 2) (separator - offset - 2) in
            let href = String.sub source (separator + 2) (close - separator - 2) in
            Image { alt; href } :: parse_inline source (close + 1) finish
        | None | Some _ -> Text "!" :: parse_inline source (offset + 1) finish)
    | None | Some _ -> Text "!" :: parse_inline source (offset + 1) finish)
  else if starts_with_at source offset "[" then
    (match find_from source (offset + 1) "](" with
    | Some separator when separator < finish ->
        (match find_from source (separator + 2) ")" with
        | Some close when close < finish ->
            let label = String.sub source (offset + 1) (separator - offset - 1) in
            let href = String.sub source (separator + 2) (close - separator - 2) in
            Link { label = parse_inline label 0 (String.length label); href }
            :: parse_inline source (close + 1) finish
        | None | Some _ -> Text "[" :: parse_inline source (offset + 1) finish)
    | None | Some _ -> Text "[" :: parse_inline source (offset + 1) finish)
  else
    let marker, build =
      if starts_with_at source offset "**" then Some "**", (fun values -> Strong values)
      else if starts_with_at source offset "__" then Some "__", (fun values -> Strong values)
      else if starts_with_at source offset "~~" then Some "~~", (fun values -> Delete values)
      else if starts_with_at source offset "*" then Some "*", (fun values -> Emphasis values)
      else if starts_with_at source offset "_" then Some "_", (fun values -> Emphasis values)
      else if starts_with_at source offset "`" then Some "`", (fun values -> Code_span (inline_text values))
      else None, (fun values -> Text (inline_text values))
    in
    match marker with
    | Some marker ->
        let after = offset + String.length marker in
        (match find_from source after marker with
        | Some close when close < finish && close > after ->
            let inner = parse_inline source after close in
            build inner :: parse_inline source (close + String.length marker) finish
        | None | Some _ ->
            let next =
              match find_from source (offset + 1) " " with
              | Some value -> min finish value
              | None -> finish
            in
            Text (String.sub source offset (next - offset))
            :: parse_inline source next finish)
    | None ->
        let next = ref (next_codepoint source offset finish) in
        while !next < finish
              && not (List.exists (fun marker -> starts_with_at source !next marker)
                        [ "\\"; "\n"; "!["; "["; "**"; "__"; "~~"; "*"; "_"; "`" ]) do
          next := next_codepoint source !next finish
        done;
        Text (String.sub source offset (!next - offset))
        :: parse_inline source !next finish

and inline_text values =
  String.concat ""
    (List.map
       (function
         | Text value -> value
         | Emphasis values | Strong values | Delete values -> inline_text values
         | Code_span value -> value
         | Link { label; _ } -> inline_text label
         | Image { alt; _ } -> alt
         | Hard_break -> "\n")
       values)

let split_lines content =
  let normalized =
    let bytes = Bytes.of_string content in
    let result = Stdlib.Buffer.create (String.length content) in
    let index = ref 0 in
    while !index < Bytes.length bytes do
      if Bytes.get bytes !index = '\r' then begin
        if !index + 1 < Bytes.length bytes && Bytes.get bytes (!index + 1) = '\n' then incr index;
        Stdlib.Buffer.add_char result '\n'
      end else Stdlib.Buffer.add_char result (Bytes.get bytes !index);
      incr index
    done;
    Stdlib.Buffer.contents result
  in
  Array.of_list (String.split_on_char '\n' normalized)

let line_is_blank line = String.length (trim line) = 0

let heading line =
  let count = ref 0 in
  while !count < String.length line && String.get line !count = '#' && !count < 6 do incr count done;
  if !count > 0 && !count < String.length line && String.get line !count = ' ' then
    Some (!count, String.sub line (!count + 1) (String.length line - !count - 1))
  else None

let fence line =
  if starts_with_at line 0 "```" then Some "```"
  else if starts_with_at line 0 "~~~" then Some "~~~"
  else None

let unordered_item line =
  if String.length line >= 2
     && (String.get line 0 = '-' || String.get line 0 = '*' || String.get line 0 = '+')
     && String.get line 1 = ' '
  then Some (String.sub line 2 (String.length line - 2))
  else None

let ordered_item line =
  let index = ref 0 in
  while !index < String.length line
        && String.get line !index >= '0' && String.get line !index <= '9' do incr index done;
  if !index > 0 && !index + 1 < String.length line
     && String.get line !index = '.' && String.get line (!index + 1) = ' '
  then
    let number = int_of_string (String.sub line 0 !index) in
    Some (number, String.sub line (!index + 2) (String.length line - !index - 2))
  else None

let horizontal_rule line =
  let value = trim line in
  String.equal value "---" || String.equal value "***" || String.equal value "___"

let split_table_row line =
  let value = trim line in
  let value =
    if String.length value > 0 && String.get value 0 = '|' then String.sub value 1 (String.length value - 1) else value
  in
  let value =
    if String.length value > 0 && String.get value (String.length value - 1) = '|' then String.sub value 0 (String.length value - 1) else value
  in
  List.map (fun cell -> parse_inline cell 0 (String.length cell))
    (String.split_on_char '|' value)

let table_cells line =
  let value = trim line in
  let value =
    if String.length value > 0 && String.get value 0 = '|' then
      String.sub value 1 (String.length value - 1)
    else value
  in
  let value =
    if String.length value > 0 && String.get value (String.length value - 1) = '|' then
      String.sub value 0 (String.length value - 1)
    else value
  in
  String.split_on_char '|' value

let table_separator line =
  let cells = table_cells line in
  List.length cells > 1
  && List.for_all
       (fun cell ->
         let value = trim cell in
         String.length value >= 3
         && String.for_all (fun c -> c = '-' || c = ':' || c = ' ') value)
       cells

let table_alignments line =
  List.map
    (fun cell ->
      let value = trim cell in
      let left = String.length value > 0 && String.get value 0 = ':' in
      let right = String.length value > 0 && String.get value (String.length value - 1) = ':' in
      match left, right with
      | true, true -> Align_center
      | true, false -> Align_left
      | false, true -> Align_right
      | false, false -> Align_default)
    (table_cells line)

let raw_lines lines start finish =
  let values = ref [] in
  for index = start to finish - 1 do values := lines.(index) :: !values done;
  String.concat "\n" (List.rev !values)

let parse content =
  let lines = split_lines content in
  let last = Array.length lines in
  let result = ref [] in
  let index = ref 0 in
  while !index < last do
    let line = lines.(!index) in
    if line_is_blank line then incr index
    else
      match fence line with
      | Some marker ->
          let info = trim (String.sub line 3 (String.length line - 3)) in
          let body = ref [] in
          let finish = ref (!index + 1) in
          while !finish < last && not (starts_with_at lines.(!finish) 0 marker) do
            body := lines.(!finish) :: !body;
            incr finish
          done;
          let raw_finish = if !finish < last then !finish + 1 else !finish in
          result := Code_block { raw = raw_lines lines !index raw_finish; language = Lib.Tree_sitter_resolve_filetype.info_string_to_filetype info; text = String.concat "\n" (List.rev !body) } :: !result;
          index := raw_finish
      | None ->
          (match heading line with
          | Some (level, text) ->
              result := Heading { level; raw = line; inlines = parse_inline text 0 (String.length text) } :: !result;
              incr index
          | None when horizontal_rule line ->
              result := Horizontal_rule line :: !result;
              incr index
          | None when !index + 1 < last && String.contains line '|' && table_separator lines.(!index + 1) ->
              let finish = ref (!index + 2) in
              while !finish < last && String.contains lines.(!finish) '|' && not (line_is_blank lines.(!finish)) do incr finish done;
              let rows = ref [] in
              for row = !index + 2 to !finish - 1 do rows := split_table_row lines.(row) :: !rows done;
              result := Table { raw = raw_lines lines !index !finish; headers = split_table_row line; rows = List.rev !rows; alignments = table_alignments lines.(!index + 1) } :: !result;
              index := !finish
          | None when starts_with_at line 0 ">" ->
              let finish = ref !index in
              let values = ref [] in
              while !finish < last && starts_with_at lines.(!finish) 0 ">" do
                let value = if String.length lines.(!finish) > 1 && String.get lines.(!finish) 1 = ' ' then String.sub lines.(!finish) 2 (String.length lines.(!finish) - 2) else String.sub lines.(!finish) 1 (String.length lines.(!finish) - 1) in
                values := value :: !values;
                incr finish
              done;
              let text = String.concat "\n" (List.rev !values) in
              result := Blockquote { raw = raw_lines lines !index !finish; inlines = parse_inline text 0 (String.length text) } :: !result;
              index := !finish
          | None ->
              (match unordered_item line, ordered_item line with
              | Some _, _ ->
                  let finish = ref !index in
                  let items = ref [] in
                  while !finish < last && Option.is_some (unordered_item lines.(!finish)) do
                    let value = Option.get (unordered_item lines.(!finish)) in
                    items := { raw = lines.(!finish); inlines = parse_inline value 0 (String.length value) } :: !items;
                    incr finish
                  done;
                  result := Unordered_list { raw = raw_lines lines !index !finish; items = List.rev !items } :: !result;
                  index := !finish
              | None, Some (start, _) ->
                  let finish = ref !index in
                  let items = ref [] in
                  while !finish < last && Option.is_some (ordered_item lines.(!finish)) do
                    let number, value = Option.get (ordered_item lines.(!finish)) in
                    items := { raw = lines.(!finish); inlines = parse_inline value 0 (String.length value) } :: !items;
                    incr finish;
                    ignore number
                  done;
                  result := Ordered_list { raw = raw_lines lines !index !finish; start; items = List.rev !items } :: !result;
                  index := !finish
              | None, None when String.length (trim line) > 0 && String.get (trim line) 0 = '<' ->
                  result := Html line :: !result; incr index
              | None, None ->
                  let finish = ref (!index + 1) in
                  while !finish < last && not (line_is_blank lines.(!finish))
                        && Option.is_none (heading lines.(!finish))
                        && Option.is_none (fence lines.(!finish))
                        && not (horizontal_rule lines.(!finish))
                        && not (starts_with_at lines.(!finish) 0 ">")
                        && Option.is_none (unordered_item lines.(!finish))
                        && (match ordered_item lines.(!finish) with None -> true | Some _ -> false)
                        && not
                             (!finish + 1 < last
                             && String.contains lines.(!finish) '|'
                             && table_separator lines.(!finish + 1)) do
                    incr finish
                  done;
                  let text = raw_lines lines !index !finish in
                  result := Paragraph { raw = text; inlines = parse_inline text 0 (String.length text) } :: !result;
                  index := !finish))
  done;
  { content; tokens = List.rev !result; stable_token_count = 0 }

let token_raw = function
  | Heading { raw; _ } | Paragraph { raw; _ } | Code_block { raw; _ }
  | Blockquote { raw; _ } | Unordered_list { raw; _ } | Ordered_list { raw; _ }
  | Table { raw; _ } -> raw
  | Horizontal_rule raw | Html raw -> raw

let parse_incremental ?(trailing_unstable = 2) content previous =
  let current = parse content in
  let stable_limit = max 0 (List.length current.tokens - trailing_unstable) in
  match previous with
  | None -> { current with stable_token_count = stable_limit }
  | Some previous when List.is_empty previous.tokens ->
      { current with stable_token_count = stable_limit }
  | Some previous ->
      let rec common left right count =
        match left, right with
        | left :: left_tail, right :: right_tail
          when String.equal (token_raw left) (token_raw right) ->
            common left_tail right_tail (count + 1)
        | _ -> count
      in
      let common_count = common current.tokens previous.tokens 0 in
      { current with stable_token_count = min stable_limit common_count }

let content parsed = parsed.content
let tokens parsed = parsed.tokens
let stable_token_count parsed = parsed.stable_token_count
