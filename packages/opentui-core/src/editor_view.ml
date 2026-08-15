type viewport = { offset_y : int; offset_x : int; height : int; width : int }
type wrap_mode = No_wrap | Char | Word
type visual_cursor = {
  row : int;
  col : int;
  logical_row : int;
  logical_col : int;
  offset : int;
}

type line_info = {
  line_start_cols : int array;
  line_width_cols : int array;
  line_width_cols_max : int;
  line_sources : int array;
  line_wraps : int array;
}

type measure = { line_count : int; width_cols_max : int }

type visual_line = {
  source_row : int;
  wrap : int;
  start_offset : int;
  end_offset : int;
  start_col : int;
  width : int;
}

type t = {
  edit_buffer : Edit_buffer.t;
  mutable viewport : viewport;
  mutable scroll_margin : int;
  mutable wrap_mode : wrap_mode;
  mutable selection : (int * int) option;
  mutable local_selection : (int * int) option;
  mutable placeholder : Lib.Styled_text.chunk list;
  mutable tab_indicator : string;
  mutable tab_indicator_color : Lib.Rgba.t option;
  mutable destroyed : bool;
}

let create edit_buffer ~viewport_width ~viewport_height =
  {
    edit_buffer;
    viewport = { offset_y = 0; offset_x = 0; width = max 0 viewport_width; height = max 0 viewport_height };
    scroll_margin = 0;
    wrap_mode = No_wrap;
    selection = None;
    local_selection = None;
    placeholder = [];
    tab_indicator = "";
    tab_indicator_color = None;
    destroyed = false;
  }

let ensure_open view = if view.destroyed then Error Error.Destroyed else Ok ()
let metrics_method view =
  match Edit_buffer.width_method view.edit_buffer with
  | Edit_buffer.Wcwidth -> Lib.Text_metrics.Wcwidth
  | Edit_buffer.Unicode -> Lib.Text_metrics.Unicode

let tab_width = 2

let text view = Edit_buffer.text view.edit_buffer

let line_starts value width_method =
  let result = ref [ 0 ] in
  let offset = ref 0 in
  Array.iter
    (fun (codepoint : Lib.Text_metrics.codepoint) ->
      offset := !offset + codepoint.width;
      if Int.equal codepoint.code 0x0a then result := !offset :: !result)
    (Lib.Text_metrics.scan ~tab_width width_method value);
  Array.of_list (List.rev !result)

let logical_line_width_max value metrics starts =
  let total_width = Lib.Text_metrics.display_width ~tab_width metrics value in
  let maximum = ref 0 in
  for row = 0 to Array.length starts - 1 do
    let source_start = starts.(row) in
    let source_end =
      if row + 1 < Array.length starts then starts.(row + 1) - 1
      else total_width
    in
    maximum := max !maximum (source_end - source_start)
  done;
  !maximum

let line_segments view =
  let value = match text view with Ok value -> value | Error _ -> "" in
  let metrics = metrics_method view in
  let starts = line_starts value metrics in
  let codepoints = Lib.Text_metrics.scan ~tab_width metrics value in
  let width_for_range start finish = finish - start in
  let segments = ref [] in
  for row = 0 to Array.length starts - 1 do
    let source_start = starts.(row) in
    let source_end = if row + 1 < Array.length starts then starts.(row + 1) - 1 else Lib.Text_metrics.display_width ~tab_width metrics value in
    let no_wrap = match view.wrap_mode with No_wrap -> true | Char | Word -> false in
    if no_wrap || view.viewport.width <= 0 || source_start = source_end then
      segments := { source_row = row; wrap = 0; start_offset = source_start; end_offset = source_end; start_col = 0; width = width_for_range source_start source_end } :: !segments
    else begin
      let wrap_index = ref 0 in
      let segment_start = ref source_start in
      let segment_width = ref 0 in
      let last_space = ref None in
      let add_segment ~start_offset ~end_offset =
        segments :=
          {
            source_row = row;
            wrap = !wrap_index;
            start_offset;
            end_offset;
            start_col = start_offset - source_start;
            width = end_offset - start_offset;
          }
          :: !segments
      in
      Array.iter
        (fun (codepoint : Lib.Text_metrics.codepoint) ->
          let offset = Lib.Text_metrics.display_offset_of_byte ~tab_width metrics value codepoint.byte_start in
          if offset >= source_start && offset < source_end then begin
            let next_width = !segment_width + codepoint.width in
            if next_width > view.viewport.width && !segment_width > 0 then begin
              let next_start, next_segment_width =
                match view.wrap_mode, !last_space with
                | Word, Some space when space > !segment_start ->
                    add_segment ~start_offset:!segment_start ~end_offset:space;
                    space, offset - space
                | Word, None | Char, _ | No_wrap, _ ->
                    add_segment ~start_offset:!segment_start ~end_offset:offset;
                    offset, 0
                | Word, Some _ ->
                    add_segment ~start_offset:!segment_start ~end_offset:offset;
                    offset, 0
              in
              incr wrap_index;
              segment_start := next_start;
              segment_width := next_segment_width;
              last_space := None
            end;
            segment_width := !segment_width + codepoint.width;
            if codepoint.code = Char.code ' ' || codepoint.code = Char.code '\t' then
              last_space := Some (offset + codepoint.width)
          end)
        codepoints;
      if !segment_start < source_end || !wrap_index = 0 then
        add_segment ~start_offset:!segment_start ~end_offset:source_end
    end
  done;
  Array.of_list (List.rev !segments)

let line_info view =
  let segments = line_segments view in
  let value = match text view with Ok value -> value | Error _ -> "" in
  let metrics = metrics_method view in
  let logical_starts = line_starts value metrics in
  let starts = Array.map (fun line -> line.start_offset) segments in
  let widths = Array.map (fun line -> line.width) segments in
  let sources = Array.map (fun line -> line.source_row) segments in
  let wraps = Array.map (fun line -> line.wrap) segments in
  let maximum = logical_line_width_max value metrics logical_starts in
  { line_start_cols = starts; line_width_cols = widths; line_width_cols_max = maximum; line_sources = sources; line_wraps = wraps }

let logical_line_info view = line_info view

let set_viewport_size view ~width ~height =
  view.viewport <- { view.viewport with width = max 0 width; height = max 0 height };
  let total_lines = Array.length (line_segments view) in
  let maximum_y = max 0 (total_lines - view.viewport.height) in
  let maximum_x =
    match view.wrap_mode with
    | No_wrap -> max 0 (logical_line_width_max
                          (match text view with Ok value -> value | Error _ -> "")
                          (metrics_method view)
                          (line_starts
                             (match text view with Ok value -> value | Error _ -> "")
                             (metrics_method view))
                          - view.viewport.width)
    | Char | Word -> 0
  in
  view.viewport <-
    { view.viewport with
      offset_y = min view.viewport.offset_y maximum_y;
      offset_x = min view.viewport.offset_x maximum_x }

let set_viewport view ~x ~y ~width ~height ?(move_cursor = true) () =
  view.viewport <-
    { offset_x = max 0 x; offset_y = max 0 y; width = max 0 width; height = max 0 height };
  if move_cursor then begin
    (match Edit_buffer.cursor view.edit_buffer with
    | Error _ -> ()
    | Ok cursor ->
        let lines = line_segments view in
        if Array.length lines > 0 && view.viewport.height > 0 then begin
          let current_row = ref 0 in
          Array.iteri
            (fun index line ->
              if cursor.offset >= line.start_offset
                 && cursor.offset <= line.end_offset
              then current_row := index)
            lines;
          let target_row =
            if !current_row < view.viewport.offset_y then Some view.viewport.offset_y
            else if !current_row >= view.viewport.offset_y + view.viewport.height then
              Some (view.viewport.offset_y + view.viewport.height - 1)
            else None
          in
          match target_row with
          | None -> ()
          | Some target_row ->
              let target_row = min (Array.length lines - 1) (max 0 target_row) in
              let target = lines.(target_row) in
              let target_col = min target.width cursor.col in
              ignore
                (Edit_buffer.set_cursor_by_offset view.edit_buffer
                   (target.start_offset + target_col))
        end)
  end

let viewport view = view.viewport
let set_scroll_margin view margin = view.scroll_margin <- max 0 margin
let set_wrap_mode view mode = view.wrap_mode <- mode
let wrap_mode view = view.wrap_mode

let virtual_line_count view = Array.length (line_segments view)
let total_virtual_line_count view = virtual_line_count view

let normalized_selection start finish = if start <= finish then start, finish else finish, start
let set_selection view ~start ~end_ = view.selection <- Some (normalized_selection start end_)
let update_selection view ~end_ =
  match view.selection with None -> () | Some (start, _) -> view.selection <- Some (normalized_selection start end_)
let reset_selection view = view.selection <- None
let selection view = view.selection
let selected_range view =
  match view.local_selection with Some value -> Some value | None -> view.selection

let has_selection view = Option.is_some (selected_range view)

let local_selection_from_coordinates view ~anchor_x ~anchor_y ~focus_x ~focus_y =
  let lines = line_segments view in
  let offset_at x y =
    let visual_y = y + view.viewport.offset_y in
    let visual_x =
      x +
      (match view.wrap_mode with
      | No_wrap -> view.viewport.offset_x
      | Char | Word -> 0)
    in
    if visual_y < 0 || visual_y >= Array.length lines then None
    else
      let line = lines.(visual_y) in
      Some
        (min line.end_offset
           (max line.start_offset (line.start_offset + visual_x)))
  in
  match offset_at anchor_x anchor_y, offset_at focus_x focus_y with
  | Some anchor, Some focus -> Some (normalized_selection anchor focus)
  | _ -> None

let set_local_selection view ~anchor_x ~anchor_y ~focus_x ~focus_y =
  view.local_selection <- local_selection_from_coordinates view ~anchor_x ~anchor_y ~focus_x ~focus_y

let update_local_selection view ~anchor_x ~anchor_y ~focus_x ~focus_y =
  set_local_selection view ~anchor_x ~anchor_y ~focus_x ~focus_y

let reset_local_selection view = view.local_selection <- None

let selected_range view = match view.local_selection with Some value -> Some value | None -> view.selection

let selected_text view =
  Result.bind (ensure_open view) (fun () ->
      match selected_range view with
      | None -> Ok ""
      | Some (start, finish) -> Edit_buffer.text_range view.edit_buffer ~start_offset:start ~end_offset:finish)

let cursor view =
  Result.map (fun (value : Edit_buffer.cursor) -> value.row, value.col)
    (Edit_buffer.cursor view.edit_buffer)
let text view = Edit_buffer.text view.edit_buffer

let absolute_visual_cursor view =
  Result.bind (ensure_open view) (fun () ->
      Result.bind (Edit_buffer.cursor view.edit_buffer) (fun current ->
      let lines = line_segments view in
      let result = ref {
          row = 0;
          col = 0;
          logical_row = current.row;
          logical_col = current.col;
          offset = current.offset;
        }
      in
      Array.iteri
        (fun index line ->
          if current.offset >= line.start_offset && current.offset <= line.end_offset then
            result := {
              row = index;
              col = current.offset - line.start_offset;
              logical_row = current.row;
              logical_col = current.col;
              offset = current.offset;
            })
        lines;
      Ok !result))

let visual_cursor view =
  Result.bind (absolute_visual_cursor view) (fun current ->
      let viewport = view.viewport in
      Ok
        {
          current with
          row = max 0 (current.row - viewport.offset_y);
          col =
            (match view.wrap_mode with
            | No_wrap -> max 0 (current.col - viewport.offset_x)
            | Char | Word -> current.col);
        })

let set_visual_cursor view target_row target_col =
  let lines = line_segments view in
  if target_row < 0 || target_row >= Array.length lines then Ok ()
  else
    let line = lines.(target_row) in
    Edit_buffer.set_cursor_by_offset view.edit_buffer (min line.end_offset (max line.start_offset (line.start_offset + target_col)))

let move_up_visual view =
  Result.bind (absolute_visual_cursor view) (fun current -> set_visual_cursor view (current.row - 1) current.col)

let move_down_visual view =
  Result.bind (absolute_visual_cursor view) (fun current -> set_visual_cursor view (current.row + 1) current.col)

let delete_selected_text view =
  Result.bind (ensure_open view) (fun () ->
      match selected_range view with
      | None -> Ok ()
      | Some (start, finish) ->
          Result.bind (Edit_buffer.offset_to_position view.edit_buffer start) (fun start_position ->
              Result.bind (Edit_buffer.offset_to_position view.edit_buffer finish) (fun finish_position ->
                  match start_position, finish_position with
                  | Some (start_row, start_col), Some (end_row, end_col) ->
                      Result.bind (Edit_buffer.delete_range view.edit_buffer ~start_row ~start_col ~end_row ~end_col) (fun () -> view.selection <- None; view.local_selection <- None; Ok ())
                  | _ -> Error Error.Invalid_argument)))

let set_cursor_by_offset view offset = Edit_buffer.set_cursor_by_offset view.edit_buffer offset
let next_word_boundary view = Edit_buffer.next_word_boundary view.edit_buffer
let previous_word_boundary view = Edit_buffer.previous_word_boundary view.edit_buffer
let eol view = Edit_buffer.eol view.edit_buffer

let visual_sol view =
  Result.bind (absolute_visual_cursor view) (fun current ->
      let lines = line_segments view in
      if current.row < Array.length lines then
        let line = lines.(current.row) in
        Ok { row = current.row; col = 0; offset = line.start_offset;
             logical_row = line.source_row; logical_col = line.start_col }
      else Ok current)

let visual_eol view =
  Result.bind (absolute_visual_cursor view) (fun current ->
      let lines = line_segments view in
      if current.row < Array.length lines then
        let line = lines.(current.row) in
        Ok { row = current.row; col = line.width; offset = line.end_offset;
             logical_row = line.source_row;
             logical_col = line.start_col + line.width }
      else Ok current)

let set_placeholder_styled_text view chunks = view.placeholder <- chunks
let placeholder_styled_text view = view.placeholder
let set_tab_indicator view indicator = view.tab_indicator <- indicator
let tab_indicator view = view.tab_indicator
let set_tab_indicator_color view color = view.tab_indicator_color <- Some color
let tab_indicator_color view = view.tab_indicator_color

let measure_for_dimensions view ~width ~height =
  let previous = view.viewport in
  set_viewport_size view ~width ~height;
  let info = line_info view in
  view.viewport <- previous;
  { line_count = Array.length info.line_width_cols; width_cols_max = info.line_width_cols_max }

let edit_buffer view = view.edit_buffer
let extmarks view = Edit_buffer.extmarks view.edit_buffer
let destroy view = view.destroyed <- true
let is_destroyed view = view.destroyed
