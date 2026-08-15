type width_method = Wcwidth | Unicode

type highlight = {
  start : int;
  end_ : int;
  style_id : int;
  priority : int option;
  hl_ref : int option;
}

type t = Text_buffer_internal.t

let raw buffer = Text_buffer_internal.raw buffer

let map_error error =
  match error with
  | Opentui_raw.Error.Closed -> Error.Closed
  | error -> Error.Native (Native.Error.Native error)

let map_result result =
  match result with
  | Ok value -> Ok value
  | Error error -> Result.Error (map_error error)

let raw_width_method = function
  | Wcwidth -> Opentui_raw.Text_buffer.Wcwidth
  | Unicode -> Opentui_raw.Text_buffer.Unicode

let create width_method =
  match
    Opentui_raw.Text_buffer.create (raw_width_method width_method)
  with
  | Error error -> Result.Error (map_error error)
  | Ok buffer ->
      Ok
        (Text_buffer_internal.of_raw buffer
           (match width_method with
           | Wcwidth -> Lib.Text_metrics.Wcwidth
           | Unicode -> Lib.Text_metrics.Unicode))

let ensure_open buffer =
  if Text_buffer_internal.is_open buffer then Ok () else Error Error.Closed

let clear buffer =
  Result.bind (map_result (Opentui_raw.Text_buffer.clear (raw buffer))) (fun () ->
      Text_buffer_internal.clear_text buffer;
      Ok ())

let reset buffer =
  Result.bind (map_result (Opentui_raw.Text_buffer.reset (raw buffer))) (fun () ->
      Text_buffer_internal.reset_text buffer;
      Ok ())

let append buffer text =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer.append (raw buffer) (Bytes.of_string text)))
    (fun () ->
      Text_buffer_internal.append_text buffer text;
      Ok ())

let set_text buffer text =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer.set_text (raw buffer) (Bytes.of_string text)))
    (fun () ->
      Text_buffer_internal.set_text buffer text;
      Ok ())

let load_file buffer ~path =
  Result.bind (ensure_open buffer) (fun () ->
      try
        let contents = In_channel.with_open_bin path In_channel.input_all in
        Result.bind
          (map_result (Opentui_raw.Text_buffer.load_file (raw buffer) path))
          (fun () ->
            Text_buffer_internal.set_text buffer contents;
            Ok ())
      with Sys_error message -> Error (Error.Io message))

let set_styled_text buffer styled_text =
  let chunks =
    List.map
      (fun (chunk : Lib.Styled_text.chunk) ->
        ( chunk.text,
          Option.map
            (fun color ->
              Opentui_raw.Color.Private.to_native (Color.Private.to_raw color))
            chunk.fg,
          Option.map
            (fun color ->
              Opentui_raw.Color.Private.to_native (Color.Private.to_raw color))
            chunk.bg,
          Int32.of_int chunk.attributes,
          chunk.link ))
      (Lib.Styled_text.chunks styled_text)
  in
  Result.bind
    (map_result (Opentui_raw.Text_buffer.set_styled_text (raw buffer) chunks))
    (fun () ->
      Text_buffer_internal.set_styled_text buffer styled_text;
      Ok ())

let length buffer = map_result (Opentui_raw.Text_buffer.length (raw buffer))
let byte_size buffer = map_result (Opentui_raw.Text_buffer.byte_size (raw buffer))
let close buffer = map_result (Opentui_raw.Text_buffer.close (raw buffer))

let text buffer = Result.bind (ensure_open buffer) (fun () -> Ok (Text_buffer_internal.text buffer))
let plain_text buffer = text buffer

let line_count buffer =
  Result.bind (ensure_open buffer) (fun () ->
      Result.map Int32.to_int
        (map_result (Opentui_raw.Text_buffer.line_count (raw buffer))))

let text_range buffer ~start_offset ~end_offset =
  Result.bind (text buffer) (fun value ->
      if start_offset < 0 || end_offset < start_offset then Error Error.Invalid_argument
      else if Int.equal start_offset end_offset then Ok ""
      else
        let width_method = Text_buffer_internal.width_method buffer in
        let tab_width = Text_buffer_internal.tab_width buffer in
        let total_width = Lib.Text_metrics.display_width ~tab_width width_method value in
        if start_offset >= total_width then Ok ""
        else
          let end_offset = min end_offset total_width in
          let start_byte =
            Lib.Text_metrics.byte_offset_at_display ~tab_width width_method value
              start_offset
          in
          let end_byte =
            Lib.Text_metrics.byte_offset_at_display ~tab_width width_method value
              end_offset
          in
          Ok (String.sub value start_byte (end_byte - start_byte)))

let styled_text buffer = Result.bind (ensure_open buffer) (fun () -> Ok (Text_buffer_internal.styled_text buffer))

let set_default_fg buffer value =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer.set_default_fg (raw buffer)
          (Option.map Color.Private.to_raw value)))
    (fun () -> Text_buffer_internal.set_default_fg buffer value; Ok ())

let default_fg buffer = Result.bind (ensure_open buffer) (fun () -> Ok (Text_buffer_internal.default_fg buffer))

let set_default_bg buffer value =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer.set_default_bg (raw buffer)
          (Option.map Color.Private.to_raw value)))
    (fun () -> Text_buffer_internal.set_default_bg buffer value; Ok ())

let default_bg buffer = Result.bind (ensure_open buffer) (fun () -> Ok (Text_buffer_internal.default_bg buffer))

let set_default_attributes buffer value =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer.set_default_attributes (raw buffer)
          (Option.map Int32.of_int value)))
    (fun () -> Text_buffer_internal.set_default_attributes buffer value; Ok ())

let default_attributes buffer =
  Result.bind (ensure_open buffer) (fun () -> Ok (Text_buffer_internal.default_attributes buffer))

let reset_defaults buffer =
  Result.bind
    (map_result (Opentui_raw.Text_buffer.reset_defaults (raw buffer)))
    (fun () -> Text_buffer_internal.reset_defaults buffer; Ok ())

let set_syntax_style buffer value =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer.set_syntax_style (raw buffer)
          (Option.bind value Syntax_style.Private.native)))
    (fun () -> Text_buffer_internal.set_syntax_style buffer value; Ok ())

let syntax_style buffer = Result.bind (ensure_open buffer) (fun () -> Ok (Text_buffer_internal.syntax_style buffer))

let to_internal_highlight (highlight : highlight) : Text_buffer_internal.highlight =
  { start = highlight.start; end_ = highlight.end_; style_id = highlight.style_id; priority = highlight.priority; hl_ref = highlight.hl_ref }

let of_internal_highlight (highlight : Text_buffer_internal.highlight) : highlight =
  { start = highlight.start; end_ = highlight.end_; style_id = highlight.style_id; priority = highlight.priority; hl_ref = highlight.hl_ref }

let uint32_limit = Int32.to_int Int32.max_int

let raw_highlight (highlight : highlight) =
  let valid_uint32 value = value >= 0 && value <= uint32_limit in
  let valid_priority =
    match highlight.priority with
    | None -> true
    | Some value -> value >= 0 && value <= 255
  in
  let valid_reference =
    match highlight.hl_ref with
    | None -> true
    | Some value -> value >= 0 && value <= 65535
  in
  if not (valid_uint32 highlight.start && valid_uint32 highlight.end_
          && valid_uint32 highlight.style_id && valid_priority
          && valid_reference)
  then Error Error.Invalid_argument
  else
    Ok
      {
        Opentui_raw.Text_buffer.start = Int32.of_int highlight.start;
        end_ = Int32.of_int highlight.end_;
        style_id = Int32.of_int highlight.style_id;
        priority = Option.value highlight.priority ~default:0;
        hl_ref = Option.value highlight.hl_ref ~default:0;
      }

let add_highlight buffer ~line (highlight : highlight) =
  Result.bind (ensure_open buffer) (fun () ->
      if line < 0 || highlight.start < 0 || highlight.end_ < highlight.start then Error Error.Invalid_argument
      else if highlight.start >= highlight.end_ then Ok ()
      else
        Result.bind (line_count buffer) (fun line_count ->
            if line >= line_count || line > uint32_limit then Error Error.Invalid_argument
            else
              Result.bind (raw_highlight highlight) (fun native_highlight ->
                  Result.bind
                    (map_result
                       (Opentui_raw.Text_buffer.add_highlight (raw buffer)
                          ~line native_highlight))
                    (fun () ->
                      Text_buffer_internal.add_highlight buffer ~line
                        (to_internal_highlight highlight);
                      Ok ()))))

let add_highlight_to_overlapping_lines buffer highlight =
  let value = Text_buffer_internal.text buffer in
  let metrics = Text_buffer_internal.width_method buffer in
  let tab_width = Text_buffer_internal.tab_width buffer in
  let starts =
    let result = ref [ 0 ] in
    let offset = ref 0 in
    Array.iter
      (fun (codepoint : Lib.Text_metrics.codepoint) ->
        offset := !offset + codepoint.width;
        if Int.equal codepoint.code (Char.code '\n') then
          result := !offset :: !result)
      (Lib.Text_metrics.scan ~tab_width metrics value);
    Array.of_list (List.rev !result)
  in
  let total = Lib.Text_metrics.display_width ~tab_width metrics value in
  for line = 0 to Array.length starts - 1 do
    let line_start = starts.(line) in
    let line_end =
      if line + 1 < Array.length starts then starts.(line + 1) - 1 else total
    in
    let overlap_start = max line_start highlight.start in
    let overlap_end = min line_end highlight.end_ in
    if overlap_start < overlap_end then
      Text_buffer_internal.add_highlight buffer ~line
        { (to_internal_highlight highlight) with
          start = overlap_start - line_start;
          end_ = overlap_end - line_start }
  done

let add_highlight_by_char_range buffer (highlight : highlight) =
  Result.bind (line_count buffer) (fun line_count ->
      if highlight.start < 0 || highlight.end_ < highlight.start then Error Error.Invalid_argument
      else if highlight.start >= highlight.end_ then Ok ()
      else
        let value = Text_buffer_internal.text buffer in
        let metrics = Text_buffer_internal.width_method buffer in
        if highlight.end_ > Lib.Text_metrics.display_width
             ~tab_width:(Text_buffer_internal.tab_width buffer) metrics value
        then Error Error.Invalid_argument
        else
          Result.bind (raw_highlight highlight) (fun native_highlight ->
              Result.bind
                (map_result
                   (Opentui_raw.Text_buffer.add_highlight_by_char_range
                      (raw buffer) native_highlight))
                (fun () ->
                  if line_count > 0 then
                    add_highlight_to_overlapping_lines buffer highlight;
                  Ok ())))

let remove_highlights_by_ref buffer reference =
  Result.bind (ensure_open buffer) (fun () ->
      if reference < 0 || reference > 65535 then Error Error.Invalid_argument
      else
        Result.bind
          (map_result
             (Opentui_raw.Text_buffer.remove_highlights_by_ref (raw buffer)
                reference))
          (fun () ->
            Text_buffer_internal.remove_highlights_by_ref buffer reference;
            Ok ()))

let clear_line_highlights buffer line =
  Result.bind (ensure_open buffer) (fun () ->
      if line < 0 then Error Error.Invalid_argument
      else if line > uint32_limit then Error Error.Invalid_argument
      else
        Result.bind
          (map_result
             (Opentui_raw.Text_buffer.clear_line_highlights (raw buffer)
                line))
          (fun () ->
            Text_buffer_internal.clear_line_highlights buffer line;
            Ok ()))

let clear_all_highlights buffer =
  Result.bind (ensure_open buffer) (fun () ->
      Result.bind
        (map_result
           (Opentui_raw.Text_buffer.clear_all_highlights (raw buffer)))
        (fun () ->
          Text_buffer_internal.clear_all_highlights buffer;
          Ok ()))

let line_highlights buffer line =
  Result.bind (ensure_open buffer) (fun () ->
      if line < 0 then Error Error.Invalid_argument
      else Ok (List.map of_internal_highlight (Text_buffer_internal.line_highlights buffer line)))

let highlight_count buffer =
  Result.bind (ensure_open buffer) (fun () ->
      Ok (Text_buffer_internal.highlight_count buffer))

let set_tab_width buffer width =
  Result.bind (ensure_open buffer) (fun () ->
      if width < 0 || width > 255 then Error Error.Invalid_argument
      else
        Result.bind
          (map_result
             (Opentui_raw.Text_buffer.set_tab_width (raw buffer)
                (Int32.of_int width)))
          (fun () ->
            Result.bind
              (map_result (Opentui_raw.Text_buffer.tab_width (raw buffer)))
              (fun actual_width ->
                Text_buffer_internal.set_tab_width buffer
                  (Int32.to_int actual_width);
                Ok ())))

let tab_width buffer =
  Result.bind (ensure_open buffer) (fun () ->
      Result.bind
        (map_result (Opentui_raw.Text_buffer.tab_width (raw buffer)))
        (fun actual_width ->
          let actual_width = Int32.to_int actual_width in
          Text_buffer_internal.set_tab_width buffer actual_width;
          Ok actual_width))
