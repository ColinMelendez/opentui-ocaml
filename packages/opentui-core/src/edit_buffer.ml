type width_method = Wcwidth | Unicode
type cursor = { row : int; col : int; offset : int }

type highlight = {
  start : int;
  end_ : int;
  style_id : int;
  priority : int option;
  hl_ref : int option;
}

type change = { start : int; deleted : int; inserted : int }

type snapshot = { text : string; cursor_offset : int }

type t = {
  width_method : width_method;
  mutable text : string;
  mutable cursor_offset : int;
  mutable undo_stack : snapshot list;
  mutable redo_stack : snapshot list;
  mutable default_fg : Lib.Rgba.t option;
  mutable default_bg : Lib.Rgba.t option;
  mutable default_attributes : int option;
  mutable syntax_style : Syntax_style.t option;
  extmarks : Lib.Extmarks.t;
  highlights : (int, highlight list) Hashtbl.t;
  mutable listeners : (int * (change -> unit)) list;
  mutable next_listener : int;
  mutable destroyed : bool;
}

let create width_method =
  {
    width_method;
    text = "";
    cursor_offset = 0;
    undo_stack = [];
    redo_stack = [];
    default_fg = None;
    default_bg = None;
    default_attributes = None;
    syntax_style = None;
    extmarks = Lib.Extmarks.create ();
    highlights = Hashtbl.create 8;
    listeners = [];
    next_listener = 0;
    destroyed = false;
  }

let width_method buffer = buffer.width_method

let metrics_method = function
  | Wcwidth -> Lib.Text_metrics.Wcwidth
  | Unicode -> Lib.Text_metrics.Unicode

let ensure_open buffer = if buffer.destroyed then Error Error.Destroyed else Ok ()
let tab_width = 2

let display_width buffer =
  Lib.Text_metrics.display_width ~tab_width (metrics_method buffer.width_method)
    buffer.text

let scan buffer =
  Lib.Text_metrics.scan ~tab_width (metrics_method buffer.width_method) buffer.text

let byte_offset_at_display buffer value offset =
  Lib.Text_metrics.byte_offset_at_display ~tab_width
    (metrics_method buffer.width_method) value offset

let display_offset_of_byte buffer value offset =
  Lib.Text_metrics.display_offset_of_byte ~tab_width
    (metrics_method buffer.width_method) value offset

let line_starts buffer =
  let result = ref [ 0 ] in
  let offset = ref 0 in
  Array.iter
    (fun (codepoint : Lib.Text_metrics.codepoint) ->
      offset := !offset + codepoint.width;
      if Int.equal codepoint.code 0x0a then result := !offset :: !result)
    (scan buffer);
  Array.of_list (List.rev !result)

let current_snapshot (buffer : t) : snapshot = { text = buffer.text; cursor_offset = buffer.cursor_offset }

let notify buffer change =
  let listeners = buffer.listeners in
  List.iter (fun (_, callback) -> callback change) listeners

let replace_range buffer ~start_offset ~deleted ~inserted_text ~record_history =
  let total = display_width buffer in
  if start_offset < 0 || deleted < 0 || start_offset + deleted > total then
    Error Error.Invalid_argument
  else
    let metrics = metrics_method buffer.width_method in
    let start_byte = byte_offset_at_display buffer buffer.text start_offset in
    let end_byte = byte_offset_at_display buffer buffer.text (start_offset + deleted) in
    if record_history then begin
      buffer.undo_stack <- current_snapshot buffer :: buffer.undo_stack;
      ignore (Lib.Extmarks.save_snapshot buffer.extmarks)
    end;
    buffer.redo_stack <- [];
    buffer.text <-
      String.sub buffer.text 0 start_byte
      ^ inserted_text
      ^ String.sub buffer.text end_byte (String.length buffer.text - end_byte);
    let inserted_width = Lib.Text_metrics.display_width ~tab_width metrics inserted_text in
    let new_offset = start_offset + inserted_width in
    buffer.cursor_offset <- max 0 (min (display_width buffer) new_offset);
    let adjusted =
      Result.bind
        (Lib.Extmarks.adjust_after_deletion buffer.extmarks ~offset:start_offset
           ~length:deleted)
        (fun () ->
          Lib.Extmarks.adjust_after_insertion buffer.extmarks ~offset:start_offset
            ~length:inserted_width)
    in
    Result.bind adjusted (fun () ->
        notify buffer { start = start_offset; deleted; inserted = inserted_width };
        Ok ())

let set_text buffer text =
  Result.bind (ensure_open buffer) (fun () ->
      let deleted = display_width buffer in
      buffer.text <- text;
      buffer.cursor_offset <- 0;
      buffer.undo_stack <- [];
      buffer.redo_stack <- [];
      Hashtbl.clear buffer.highlights;
      ignore (Lib.Extmarks.clear buffer.extmarks);
      notify buffer
        {
          start = 0;
          deleted;
          inserted = Lib.Text_metrics.display_width ~tab_width
            (metrics_method buffer.width_method) text;
        };
      Ok ())

let replace_text buffer text =
  Result.bind (ensure_open buffer) (fun () ->
      replace_range buffer ~start_offset:0 ~deleted:(display_width buffer)
        ~inserted_text:text ~record_history:true)

let line_count buffer =
  Result.bind (ensure_open buffer) (fun () -> Ok (Array.length (line_starts buffer)))
let text buffer = Result.bind (ensure_open buffer) (fun () -> Ok buffer.text)

let insert_text buffer value =
  Result.bind (ensure_open buffer) (fun () ->
      replace_range buffer ~start_offset:buffer.cursor_offset ~deleted:0
        ~inserted_text:value ~record_history:true)

let insert_char buffer value =
  if String.length value = 0 then Error Error.Invalid_argument else insert_text buffer value

let next_codepoint_at buffer offset =
  let codepoints = scan buffer in
  let result = ref None in
  Array.iter
    (fun (codepoint : Lib.Text_metrics.codepoint) ->
      if Option.is_none !result
         && codepoint.width > 0
         && codepoint.byte_start
            >= byte_offset_at_display buffer buffer.text offset
      then result := Some codepoint)
    codepoints;
  !result

let previous_codepoint_before buffer offset =
  let byte = byte_offset_at_display buffer buffer.text offset in
  let result = ref None in
  Array.iter
    (fun (codepoint : Lib.Text_metrics.codepoint) ->
      if codepoint.width > 0 && codepoint.byte_end <= byte then
        result := Some codepoint)
    (scan buffer);
  !result

let delete_char buffer =
  Result.bind (ensure_open buffer) (fun () ->
      match next_codepoint_at buffer buffer.cursor_offset with
      | None -> Ok ()
      | Some codepoint ->
          let width = codepoint.width in
          replace_range buffer ~start_offset:buffer.cursor_offset ~deleted:width
            ~inserted_text:"" ~record_history:true)

let delete_char_backward buffer =
  Result.bind (ensure_open buffer) (fun () ->
      match previous_codepoint_before buffer buffer.cursor_offset with
      | None -> Ok ()
      | Some codepoint ->
          let start = buffer.cursor_offset - codepoint.width in
          replace_range buffer ~start_offset:start ~deleted:codepoint.width
            ~inserted_text:"" ~record_history:true)

let offset_for_position buffer ~row ~col =
  if row < 0 || col < 0 then Error Error.Invalid_argument
  else
    let starts = line_starts buffer in
    let row = min row (Array.length starts - 1) in
    let start = starts.(row) in
    let finish =
      if row + 1 < Array.length starts then starts.(row + 1) - 1 else display_width buffer
    in
    Ok (min finish (start + col))

let set_cursor_by_offset buffer offset =
  Result.bind (ensure_open buffer) (fun () ->
      if offset < 0 then Error Error.Invalid_argument
      else begin
        buffer.cursor_offset <- min offset (display_width buffer);
        Ok ()
      end)

let offset_to_position buffer offset =
  Result.bind (ensure_open buffer) (fun () ->
      if offset < 0 || offset > display_width buffer then Ok None
      else
        let starts = line_starts buffer in
        let row = ref 0 in
        for index = 0 to Array.length starts - 1 do
          if starts.(index) <= offset then row := index
        done;
        Ok (Some (!row, offset - starts.(!row))))

let position_to_offset buffer ~row ~col =
  Result.bind (ensure_open buffer) (fun () -> offset_for_position buffer ~row ~col)

let cursor buffer =
  Result.bind (ensure_open buffer) (fun () ->
      match offset_to_position buffer buffer.cursor_offset with
      | Error error -> Error error
      | Ok None -> Error Error.Invalid_argument
      | Ok (Some (row, col)) -> Ok { row; col; offset = buffer.cursor_offset })

let move_cursor_left buffer =
  Result.bind (ensure_open buffer) (fun () ->
      if buffer.cursor_offset = 0 then Ok ()
      else
        match previous_codepoint_before buffer buffer.cursor_offset with
        | None -> Ok ()
        | Some codepoint ->
            buffer.cursor_offset <- buffer.cursor_offset - codepoint.width;
            Ok ())

let move_cursor_right buffer =
  Result.bind (ensure_open buffer) (fun () ->
      match next_codepoint_at buffer buffer.cursor_offset with
      | None -> Ok ()
      | Some codepoint ->
          buffer.cursor_offset <- min (display_width buffer) (buffer.cursor_offset + codepoint.width);
          Ok ())

let move_cursor_up buffer =
  Result.bind (cursor buffer) (fun current ->
      if current.row = 0 then Ok ()
      else
        Result.bind
          (offset_for_position buffer ~row:(current.row - 1) ~col:current.col)
          (set_cursor_by_offset buffer))

let move_cursor_down buffer =
  Result.bind (cursor buffer) (fun current ->
      let count = Array.length (line_starts buffer) in
      if current.row + 1 >= count then Ok ()
      else
        Result.bind
          (offset_for_position buffer ~row:(current.row + 1) ~col:current.col)
          (set_cursor_by_offset buffer))

let set_cursor_to_line_col buffer ~line ~col =
  Result.bind (offset_for_position buffer ~row:line ~col) (set_cursor_by_offset buffer)

let set_cursor buffer ~line ~col = set_cursor_to_line_col buffer ~line ~col

let goto_line buffer line = set_cursor buffer ~line ~col:0

let line_start_offset buffer line =
  Result.bind (ensure_open buffer) (fun () ->
      let starts = line_starts buffer in
      if line < 0 || line >= Array.length starts then Error Error.Invalid_argument
      else Ok starts.(line))

let eol buffer =
  Result.bind (cursor buffer) (fun current ->
      let starts = line_starts buffer in
      let finish = if current.row + 1 < Array.length starts then starts.(current.row + 1) - 1 else display_width buffer in
      Ok { row = current.row; col = finish - starts.(current.row); offset = finish })

type word_class = Ascii_word | Cjk_word | Other_word

type word_break = { offset : int; width : int; code : int }

let is_ascii_word code =
  (code >= Char.code 'a' && code <= Char.code 'z')
  || (code >= Char.code 'A' && code <= Char.code 'Z')
  || (code >= Char.code '0' && code <= Char.code '9')
  || Int.equal code (Char.code '_')

let is_cjk_word code =
  (code >= 0x3400 && code <= 0x4dbf)
  || (code >= 0x4e00 && code <= 0x9fff)
  || (code >= 0xf900 && code <= 0xfaff)
  || (code >= 0x20000 && code <= 0x2ee5d)
  || (code >= 0x2f800 && code <= 0x2fa1f)
  || (code >= 0x3040 && code <= 0x30ff)
  || (code >= 0x31f0 && code <= 0x31ff)
  || (code >= 0xff66 && code <= 0xff9d)
  || (code >= 0x1100 && code <= 0x11ff)
  || (code >= 0x3130 && code <= 0x318f)
  || (code >= 0xa960 && code <= 0xa97f)
  || (code >= 0xac00 && code <= 0xd7ff)

let word_class code =
  if is_ascii_word code then Ascii_word
  else if is_cjk_word code then Cjk_word
  else Other_word

let is_wrap_break code =
  match code with
  | 0x20 | 0x09 | 0x2d | 0x2f | 0x5c | 0x2e | 0x2c | 0x3b | 0x3a
  | 0x21 | 0x3f | 0x28 | 0x29 | 0x5b | 0x5d | 0x7b | 0x7d
  | 0xa0 | 0x1680 | 0x202f | 0x205f | 0x3000 | 0x200b | 0x00ad
  | 0x2010 | 0x3001 | 0x3002 | 0xff01 | 0xff0c | 0xff1a | 0xff1f -> true
  | value when value >= 0x2000 && value <= 0x200a -> true
  | _ -> false

let word_breaks buffer =
  let result = ref [] in
  let previous : Lib.Text_metrics.codepoint option ref = ref None in
  let previous_class = ref Other_word in
  Array.iter
    (fun (codepoint : Lib.Text_metrics.codepoint) ->
      let current_class = word_class codepoint.code in
      (match !previous with
      | Some previous_codepoint ->
          (match !previous_class, current_class with
          | Cjk_word, Ascii_word | Ascii_word, Cjk_word ->
              result :=
                {
                  offset = display_offset_of_byte buffer buffer.text
                      previous_codepoint.byte_start;
                  width = previous_codepoint.width;
                  code = previous_codepoint.code;
                }
                :: !result
          | _ -> ())
      | None -> ());
      if is_wrap_break codepoint.code then
        result :=
          {
            offset = display_offset_of_byte buffer buffer.text codepoint.byte_start;
            width = codepoint.width;
            code = codepoint.code;
          }
          :: !result;
      previous := Some codepoint;
      previous_class := current_class)
    (scan buffer);
  Array.of_list (List.rev !result)

let word_boundary buffer ~forward =
  let current = buffer.cursor_offset in
  let breaks = word_breaks buffer in
  let result = ref None in
  if forward then begin
    Array.iter
      (fun (break : word_break) ->
        if Option.is_none !result
           && (break.offset > current
               || (Int.equal break.offset current
                   && (is_ascii_word break.code || is_cjk_word break.code)))
        then result := Some (break.offset + break.width))
      breaks
  end else begin
    Array.iter
      (fun (break : word_break) ->
        let boundary = break.offset + break.width in
        if boundary < current then result := Some boundary)
      breaks
  end;
  let target =
    match !result with
    | Some offset -> offset
    | None ->
        let cursor =
          match cursor buffer with
          | Ok value -> value
          | Error _ -> { row = 0; col = 0; offset = 0 }
        in
        let starts = line_starts buffer in
        if forward then
          if cursor.row + 1 < Array.length starts then
            starts.(cursor.row + 1)
          else display_width buffer
        else if cursor.row > 0 then
          starts.(cursor.row) - 1
        else 0
  in
  match offset_to_position buffer target with
  | Ok (Some (row, col)) -> Ok { row; col; offset = target }
  | Ok None -> Error Error.Invalid_argument
  | Error error -> Error error

let next_word_boundary buffer = Result.bind (ensure_open buffer) (fun () -> word_boundary buffer ~forward:true)
let previous_word_boundary buffer = Result.bind (ensure_open buffer) (fun () -> word_boundary buffer ~forward:false)

let text_range buffer ~start_offset ~end_offset =
  Result.bind (ensure_open buffer) (fun () ->
      if start_offset < 0 || end_offset < start_offset then Error Error.Invalid_argument
      else if start_offset >= end_offset || start_offset >= display_width buffer then Ok ""
      else
        let start_byte = byte_offset_at_display buffer buffer.text start_offset in
        let end_byte =
          byte_offset_at_display buffer buffer.text
            (min end_offset (display_width buffer))
        in
        Ok (String.sub buffer.text start_byte (end_byte - start_byte)))

let text_range_by_coords buffer ~start_row ~start_col ~end_row ~end_col =
  Result.bind (position_to_offset buffer ~row:start_row ~col:start_col) (fun start_offset ->
      Result.bind (position_to_offset buffer ~row:end_row ~col:end_col) (fun end_offset ->
          let left, right = if start_offset <= end_offset then start_offset, end_offset else end_offset, start_offset in
          text_range buffer ~start_offset:left ~end_offset:right))

let delete_range buffer ~start_row ~start_col ~end_row ~end_col =
  Result.bind (position_to_offset buffer ~row:start_row ~col:start_col) (fun start_offset ->
      Result.bind (position_to_offset buffer ~row:end_row ~col:end_col) (fun end_offset ->
          let left, right = if start_offset <= end_offset then start_offset, end_offset else end_offset, start_offset in
          replace_range buffer ~start_offset:left ~deleted:(right - left) ~inserted_text:"" ~record_history:true))

let delete_line buffer =
  Result.bind (cursor buffer) (fun current ->
      let starts = line_starts buffer in
      let start = starts.(current.row) in
      let finish = if current.row + 1 < Array.length starts then starts.(current.row + 1) else display_width buffer in
      replace_range buffer ~start_offset:start ~deleted:(finish - start) ~inserted_text:"" ~record_history:true)

let new_line buffer = insert_text buffer "\n"

let restore_snapshot (buffer : t) (snapshot : snapshot) =
  buffer.text <- snapshot.text;
  buffer.cursor_offset <- min snapshot.cursor_offset (display_width buffer)

let undo buffer =
  Result.bind (ensure_open buffer) (fun () ->
      match buffer.undo_stack with
      | [] -> Ok None
      | snapshot :: rest ->
          buffer.undo_stack <- rest;
          buffer.redo_stack <- current_snapshot buffer :: buffer.redo_stack;
          let old_text = buffer.text in
          let old_width = display_width buffer in
          restore_snapshot buffer snapshot;
          let new_width = display_width buffer in
          ignore (Lib.Extmarks.undo buffer.extmarks);
          notify buffer { start = 0; deleted = old_width; inserted = new_width };
          Ok (Some old_text))

let redo buffer =
  Result.bind (ensure_open buffer) (fun () ->
      match buffer.redo_stack with
      | [] -> Ok None
      | snapshot :: rest ->
          buffer.redo_stack <- rest;
          buffer.undo_stack <- current_snapshot buffer :: buffer.undo_stack;
          let old_text = buffer.text in
          let old_width = display_width buffer in
          restore_snapshot buffer snapshot;
          let new_width = display_width buffer in
          ignore (Lib.Extmarks.redo buffer.extmarks);
          notify buffer { start = 0; deleted = old_width; inserted = new_width };
          Ok (Some old_text))

let can_undo buffer = Result.bind (ensure_open buffer) (fun () -> Ok (not (List.is_empty buffer.undo_stack)))
let can_redo buffer = Result.bind (ensure_open buffer) (fun () -> Ok (not (List.is_empty buffer.redo_stack)))
let clear_history buffer = Result.bind (ensure_open buffer) (fun () -> buffer.undo_stack <- []; buffer.redo_stack <- []; Ok ())

let set_default_fg buffer value = Result.bind (ensure_open buffer) (fun () -> buffer.default_fg <- value; Ok ())
let set_default_bg buffer value = Result.bind (ensure_open buffer) (fun () -> buffer.default_bg <- value; Ok ())
let set_default_attributes buffer value = Result.bind (ensure_open buffer) (fun () -> buffer.default_attributes <- value; Ok ())
let reset_defaults buffer = Result.bind (ensure_open buffer) (fun () -> buffer.default_fg <- None; buffer.default_bg <- None; buffer.default_attributes <- None; Ok ())
let default_fg buffer = Result.bind (ensure_open buffer) (fun () -> Ok buffer.default_fg)
let default_bg buffer = Result.bind (ensure_open buffer) (fun () -> Ok buffer.default_bg)
let default_attributes buffer = Result.bind (ensure_open buffer) (fun () -> Ok buffer.default_attributes)

let set_syntax_style buffer value = Result.bind (ensure_open buffer) (fun () -> buffer.syntax_style <- value; Ok ())
let syntax_style buffer = Result.bind (ensure_open buffer) (fun () -> Ok buffer.syntax_style)
let extmarks buffer = Result.bind (ensure_open buffer) (fun () -> Ok buffer.extmarks)

let add_highlight buffer ~line (highlight : highlight) =
  Result.bind (ensure_open buffer) (fun () ->
      if line < 0 || highlight.start < 0 || highlight.end_ < highlight.start
         || highlight.style_id < 0
         || (match highlight.priority with
             | Some value -> value < 0 || value > 255
             | None -> false)
         || (match highlight.hl_ref with
             | Some value -> value < 0 || value > 65535
             | None -> false)
      then Error Error.Invalid_argument
      else
        let current = Option.value (Hashtbl.find_opt buffer.highlights line) ~default:[] in
        Hashtbl.replace buffer.highlights line (highlight :: current);
        Ok ())

let add_highlight_by_char_range buffer (highlight : highlight) =
  Result.bind (ensure_open buffer) (fun () ->
      if highlight.start < 0 || highlight.end_ < highlight.start
         || highlight.end_ > display_width buffer
      then Error Error.Invalid_argument
      else
        Result.bind (offset_to_position buffer highlight.start) (fun position ->
            match position with
            | None -> Error Error.Invalid_argument
            | Some (line, _) -> add_highlight buffer ~line highlight))

let remove_highlights_by_ref buffer reference =
  Result.bind (ensure_open buffer) (fun () ->
      Hashtbl.iter
        (fun line highlights ->
          let retained = List.filter (fun highlight -> not (Option.equal Int.equal highlight.hl_ref (Some reference))) highlights in
          Hashtbl.replace buffer.highlights line retained)
        buffer.highlights;
      Ok ())

let clear_line_highlights buffer line =
  Result.bind (ensure_open buffer) (fun () -> Hashtbl.remove buffer.highlights line; Ok ())

let clear_all_highlights buffer = Result.bind (ensure_open buffer) (fun () -> Hashtbl.clear buffer.highlights; Ok ())
let line_highlights buffer line = Result.bind (ensure_open buffer) (fun () -> Ok (Option.value (Hashtbl.find_opt buffer.highlights line) ~default:[]))

let on_change buffer callback =
  let id = buffer.next_listener in
  buffer.next_listener <- id + 1;
  let subscription =
    Event_subscription.Private.create (fun () ->
        buffer.listeners <- List.filter (fun (current, _) -> not (Int.equal current id)) buffer.listeners)
  in
  buffer.listeners <- buffer.listeners @ [ id, callback ];
  subscription

let clear buffer =
  Result.bind (ensure_open buffer) (fun () ->
      replace_range buffer ~start_offset:0 ~deleted:(display_width buffer)
        ~inserted_text:"" ~record_history:false)

let destroy buffer =
  buffer.destroyed <- true;
  buffer.listeners <- [];
  Hashtbl.clear buffer.highlights;
  Lib.Extmarks.destroy buffer.extmarks
let is_destroyed buffer = buffer.destroyed
