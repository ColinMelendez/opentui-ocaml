module Data = Lib.Ascii_font_data

type name = Tiny | Block | Shade | Slick | Huge | Grid | Pallet
type definition = { name : string; lines : int; letterspace_size : int; colors : int }
type measure = { width : int; height : int }

let font_names = [ Tiny; Block; Shade; Slick; Huge; Grid; Pallet ]

let string_of_name = function
  | Tiny -> "tiny"
  | Block -> "block"
  | Shade -> "shade"
  | Slick -> "slick"
  | Huge -> "huge"
  | Grid -> "grid"
  | Pallet -> "pallet"

let name_of_string value =
  List.find_opt (fun name -> String.equal (string_of_name name) value) font_names

let raw_font = function
  | Tiny -> Data.tiny
  | Block -> Data.block
  | Shade -> Data.shade
  | Slick -> Data.slick
  | Huge -> Data.huge
  | Grid -> Data.grid
  | Pallet -> Data.pallet

let definition name =
  let font = raw_font name in
  { name = font.name; lines = font.lines; letterspace_size = font.letterspace_size; colors = font.colors }

let rec find_glyph character = function
  | [] -> None
  | (candidate, value) :: rest ->
      if Char.equal candidate character then Some value else find_glyph character rest

let glyph name character = find_glyph character (raw_font name).chars

type segment = { text : string; color_index : int }

let find_substring source ~pattern ~from =
  let limit = String.length source - String.length pattern in
  let result = ref None in
  let cursor = ref (max 0 from) in
  while !cursor <= limit && Option.is_none !result do
    let matches = ref true in
    for index = 0 to String.length pattern - 1 do
      if not (Char.equal (String.get source (!cursor + index)) (String.get pattern index))
      then matches := false
    done;
    if !matches then result := Some !cursor else incr cursor
  done;
  !result

let color_index source start finish =
  let value = ref 0 in
  let valid = ref (start < finish) in
  for index = start to finish - 1 do
    let code = Char.code (String.get source index) in
    if code < 48 || code > 57 then valid := false else value := (!value * 10) + code - 48
  done;
  if !valid then max 0 (!value - 1) else 0

let parse_segments source =
  let result = ref [] in
  let append text color_index =
    if String.length text > 0 then result := { text; color_index } :: !result
  in
  let cursor = ref 0 in
  let length = String.length source in
  while !cursor < length do
    match find_substring source ~pattern:"<c" ~from:!cursor with
    | None -> append (String.sub source !cursor (length - !cursor)) 0; cursor := length
    | Some opening ->
        if opening > !cursor then append (String.sub source !cursor (opening - !cursor)) 0;
        (match find_substring source ~pattern:">" ~from:(opening + 2) with
        | None -> append (String.sub source opening (length - opening)) 0; cursor := length
        | Some opening_end ->
            let color = color_index source (opening + 2) opening_end in
            (match find_substring source ~pattern:"</c" ~from:(opening_end + 1) with
            | None -> append (String.sub source opening (length - opening)) 0; cursor := length
            | Some closing ->
                (match find_substring source ~pattern:">" ~from:(closing + 3) with
                | None -> append (String.sub source opening (length - opening)) 0; cursor := length
                | Some closing_end ->
                    append (String.sub source (opening_end + 1) (closing - opening_end - 1)) color;
                    cursor := closing_end + 1)))
  done;
  List.rev !result

let segment_width segment =
  Array.length (Lib.Text_metrics.scan Lib.Text_metrics.Unicode segment.text)

let segments_for name character line =
  match glyph name character with
  | None -> None
  | Some lines when line < Array.length lines -> Some (parse_segments lines.(line))
  | Some _ -> Some []

let glyph_width name character =
  match segments_for name character 0 with
  | None -> None
  | Some segments -> Some (List.fold_left (fun total segment -> total + segment_width segment) 0 segments)

let points (text : string) : Lib.Text_metrics.codepoint array =
  Lib.Text_metrics.scan Lib.Text_metrics.Unicode text

let character_for_code code =
  if code >= 0 && code <= 127 then Some (Char.uppercase_ascii (Char.chr code)) else None

let fallback_width name = Option.value (glyph_width name ' ') ~default:1

let measure_text ?(font = Tiny) text =
  let values = points text in
  let fallback = fallback_width font in
  let width = ref 0 in
  Array.iteri
    (fun index point ->
      let character = Option.value (character_for_code (Lib.Text_metrics.code point)) ~default:' ' in
      width := !width + Option.value (glyph_width font character) ~default:fallback;
      if index + 1 < Array.length values then width := !width + (definition font).letterspace_size)
    values;
  { width = !width; height = (definition font).lines }

let character_positions ?(font = Tiny) text =
  let values = points text in
  let positions = Array.make (Array.length values + 1) 0 in
  let current = ref 0 in
  let fallback = fallback_width font in
  Array.iteri
    (fun index point ->
      let character = Option.value (character_for_code (Lib.Text_metrics.code point)) ~default:' ' in
      current := !current + Option.value (glyph_width font character) ~default:fallback;
      if index + 1 < Array.length values then current := !current + (definition font).letterspace_size;
      positions.(index + 1) <- !current)
    values;
  positions

let coordinate_to_character_index ?(font = Tiny) x text =
  let positions = character_positions ~font text in
  if x < 0 then 0
  else
    let answer = ref (Array.length positions - 1) in
    let index = ref 0 in
    while !index + 1 < Array.length positions do
      let left = positions.(!index) in
      let right = positions.(!index + 1) in
      if x >= left && x < right
         && Int.equal !answer (Array.length positions - 1) then
        answer := if 2 * (x - left) < right - left then !index else !index + 1;
      incr index
    done;
    !answer

let color_at colors index =
  match List.nth_opt colors index with
  | Some color -> color
  | None ->
      (match colors with color :: _ -> color | [] -> Color.white)

let render_to_surface ~buffer_width ~buffer_height ~set_cell ?(text = "")
    ?(x = 0) ?(y = 0) ?(colors = [ Color.white ])
    ?(background_color = Color.transparent) ?(font = Tiny) () =
  let font_definition = definition font in
  if y < 0 || y + font_definition.lines > buffer_height then
    Ok { width = 0; height = font_definition.lines }
  else
    let values = points text in
    let current = ref x in
    let start = x in
    let fallback = fallback_width font in
    let result = ref (Ok ()) in
    let draw_cell render_x render_y code color =
      if render_x >= 0 && render_x < buffer_width && render_y >= 0
         && render_y < buffer_height && not (Int.equal code 32) then
        match !result with
        | Error _ -> ()
        | Ok () ->
            result :=
              set_cell ~x:render_x ~y:render_y ~character:(Int32.of_int code)
                ~foreground:color ~background:background_color ~attributes:0l
    in
    Array.iteri
      (fun index point ->
        let character =
          Option.value (character_for_code (Lib.Text_metrics.code point))
            ~default:' '
        in
        let character_width =
          Option.value (glyph_width font character) ~default:fallback
        in
        if !current < buffer_width && !current + character_width >= 0 then
          for line = 0 to font_definition.lines - 1 do
            match segments_for font character line with
            | None -> ()
            | Some segments ->
                let segment_x = ref !current in
                List.iter
                  (fun segment ->
                    let segment_values = points segment.text in
                    let segment_color = color_at colors segment.color_index in
                    Array.iteri
                      (fun segment_index segment_point ->
                        draw_cell (!segment_x + segment_index) (y + line)
                          (Lib.Text_metrics.code segment_point) segment_color)
                      segment_values;
                    segment_x := !segment_x + segment_width segment)
                  segments
          done;
        current := !current + character_width;
        if index + 1 < Array.length values then
          current := !current + font_definition.letterspace_size)
      values;
    Result.bind !result (fun () -> Ok { width = !current - start; height = font_definition.lines })

let render_to_frame_buffer buffer ?(text = "") ?(x = 0) ?(y = 0)
    ?(colors = [ Color.white ]) ?(background_color = Color.transparent)
    ?(font = Tiny) () =
  Result.bind (Owned_buffer.width buffer) (fun buffer_width ->
      Result.bind (Owned_buffer.height buffer) (fun buffer_height ->
          render_to_surface ~buffer_width ~buffer_height
            ~set_cell:(fun ~x ~y ~character ~foreground ~background ~attributes ->
              Owned_buffer.set_cell_with_alpha_blending buffer ~x ~y ~character
                ~foreground ~background ~attributes)
            ~text ~x ~y ~colors ~background_color ~font ()))

let render_to_buffer buffer ?(text = "") ?(x = 0) ?(y = 0)
    ?(colors = [ Color.white ]) ?(background_color = Color.transparent)
    ?(font = Tiny) () =
  Result.bind (Buffer.width buffer) (fun buffer_width ->
      Result.bind (Buffer.height buffer) (fun buffer_height ->
          render_to_surface ~buffer_width:(Int32.to_int buffer_width)
            ~buffer_height:(Int32.to_int buffer_height)
            ~set_cell:(fun ~x ~y ~character ~foreground ~background ~attributes ->
              Buffer.set_cell_with_alpha_blending buffer ~x:(Int32.of_int x)
                ~y:(Int32.of_int y) ~character ~foreground ~background
                ~attributes)
            ~text ~x ~y ~colors ~background_color ~font ()))
