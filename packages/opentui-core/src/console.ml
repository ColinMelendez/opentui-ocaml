module Core_error = Error

type level = Log | Info | Warn | Error | Debug
type position = Top | Bottom | Left | Right
type mouse_action = Mouse_down | Mouse_drag | Mouse_up

type entry = {
  sequence : int64;
  level : level;
  message : string;
}

type display_line = {
  text : string;
  level : level;
}

type bounds = {
  x : int;
  y : int;
  width : int;
  height : int;
}

type selection_point = { line : int; column : int }

type t = {
  mutable width : int;
  mutable height : int;
  mutable position : position;
  mutable size_percent : int;
  mutable bounds : bounds;
  mutable title : string;
  max_stored_logs : int;
  max_display_lines : int;
  mutable next_sequence : int64;
  mutable entries : entry list;
  mutable display_lines : display_line list;
  mutable visible : bool;
  mutable focused : bool;
  mutable selection_start : selection_point option;
  mutable selection_end : selection_point option;
  mutable scroll_top : int;
  mutable dragging : bool;
  mutable destroyed : bool;
}

let ensure_open console =
  if console.destroyed then Result.Error Core_error.Destroyed else Ok ()

let clamp_percent value = max 1 (min 100 value)

let calculate_bounds ~width ~height ~position ~size_percent =
  match position with
  | Top ->
      { x = 0; y = 0; width; height = max 1 (height * size_percent / 100) }
  | Bottom ->
      let console_height = max 1 (height * size_percent / 100) in
      { x = 0; y = height - console_height; width; height = console_height }
  | Left ->
      { x = 0; y = 0; width = max 1 (width * size_percent / 100); height }
  | Right ->
      let console_width = max 1 (width * size_percent / 100) in
      { x = width - console_width; y = 0; width = console_width; height }

let level_tag = function
  | Log -> "LOG"
  | Info -> "INFO"
  | Warn -> "WARN"
  | Error -> "ERROR"
  | Debug -> "DEBUG"

let level_color = function
  | Log -> Color.white
  | Info ->
      Option.value (Result.to_option (Color.rgba ~red:0 ~green:255 ~blue:255 ~alpha:255))
        ~default:Color.white
  | Warn ->
      Option.value (Result.to_option (Color.rgba ~red:255 ~green:255 ~blue:0 ~alpha:255))
        ~default:Color.white
  | Error ->
      Option.value (Result.to_option (Color.rgba ~red:255 ~green:0 ~blue:0 ~alpha:255))
        ~default:Color.white
  | Debug ->
      Option.value (Result.to_option (Color.rgba ~red:128 ~green:128 ~blue:128 ~alpha:255))
        ~default:Color.white

let background_color =
  Option.value (Result.to_option (Color.rgba ~red:26 ~green:26 ~blue:26 ~alpha:230))
    ~default:Color.black

let title_background_color =
  Option.value (Result.to_option (Color.rgba ~red:13 ~green:13 ~blue:13 ~alpha:240))
    ~default:Color.black

let selection_background_color =
  Option.value (Result.to_option (Color.rgba ~red:77 ~green:128 ~blue:204 ~alpha:220))
    ~default:Color.white

let selection_foreground_color = Color.black

let wrap_line ~width ~level text =
  let available = max 1 (width - 1) in
  let prefix = "[" ^ level_tag level ^ "] " in
  let first_width = max 1 (available - String.length prefix) in
  let source_lines = String.split_on_char '\n' text in
  let result = ref [] in
  let push_wrapped prefix_value value chunk_width =
    if String.length value = 0 then result := { text = prefix_value; level } :: !result
    else begin
      let offset = ref 0 in
      while !offset < String.length value do
        let length = min chunk_width (String.length value - !offset) in
        let chunk = String.sub value !offset length in
        result := { text = prefix_value ^ chunk; level } :: !result;
        offset := !offset + length
      done
    end
  in
  List.iteri
    (fun index line ->
      if Int.equal index 0 then push_wrapped prefix line first_width
      else push_wrapped "  " line (max 1 (available - 2)))
    source_lines;
  List.rev !result

let visible_line_count console = max 0 (console.bounds.height - 1)

let max_scroll_top console =
  max 0 (List.length console.display_lines - visible_line_count console)

let clamp_scroll_top console value =
  max 0 (min (max_scroll_top console) value)

let scroll_to_bottom_internal console =
  console.scroll_top <- max_scroll_top console

let rebuild_display_lines console =
  let was_at_bottom = console.scroll_top >= max_scroll_top console in
  let lines =
    List.fold_left
      (fun accumulated (entry : entry) ->
        List.rev_append
          (wrap_line ~width:console.bounds.width ~level:entry.level entry.message)
          accumulated)
      [] console.entries
  in
  let lines = List.rev lines in
  let count = List.length lines in
  if count <= console.max_display_lines then console.display_lines <- lines
  else
    console.display_lines <-
      List.filteri
        (fun index line ->
          ignore line;
          index >= count - console.max_display_lines)
        lines;
  if was_at_bottom then scroll_to_bottom_internal console
  else console.scroll_top <- clamp_scroll_top console console.scroll_top

let create ~width ~height ?(position = Bottom) ?(size_percent = 30)
    ?(max_stored_logs = 2000) ?(max_display_lines = 3000) ?(title = "Console") () =
  if width <= 0 || height <= 0 || max_stored_logs <= 0 || max_display_lines <= 0
     || String.length title = 0
  then Result.Error Core_error.Invalid_argument
  else
    let size_percent = clamp_percent size_percent in
    Ok
      {
        width;
        height;
        position;
        size_percent;
        bounds = calculate_bounds ~width ~height ~position ~size_percent;
        title;
        max_stored_logs;
        max_display_lines;
        next_sequence = 0L;
        entries = [];
        display_lines = [];
        visible = false;
        focused = false;
        selection_start = None;
        selection_end = None;
        scroll_top = 0;
        dragging = false;
        destroyed = false;
      }

let append console level message =
  Result.bind (ensure_open console) (fun () ->
      let entry =
        { sequence = console.next_sequence; level; message }
      in
      console.next_sequence <- Int64.add console.next_sequence 1L;
      console.entries <- console.entries @ [ entry ];
      let entry_count = List.length console.entries in
      if entry_count > console.max_stored_logs then
        console.entries <-
          List.filteri
            (fun index entry ->
              ignore entry;
              index >= entry_count - console.max_stored_logs)
            console.entries;
      rebuild_display_lines console;
      Ok ())

let log console message = append console Log message
let info console message = append console Info message
let warn console message = append console Warn message
let error console message = append console Error message
let debug console message = append console Debug message

let entries console = Result.map (fun () -> console.entries) (ensure_open console)
let display_lines console = Result.map (fun () -> console.display_lines) (ensure_open console)
let bounds console = Result.map (fun () -> console.bounds) (ensure_open console)
let position console = Result.map (fun () -> console.position) (ensure_open console)
let size_percent console = Result.map (fun () -> console.size_percent) (ensure_open console)
let visible console = Result.map (fun () -> console.visible) (ensure_open console)
let focused console = Result.map (fun () -> console.focused) (ensure_open console)

let show console =
  Result.bind (ensure_open console) (fun () ->
      console.visible <- true;
      console.focused <- true;
      scroll_to_bottom_internal console;
      Ok ())

let hide console =
  Result.bind (ensure_open console) (fun () ->
      console.visible <- false;
      console.focused <- false;
      console.dragging <- false;
      Ok ())

let toggle console =
  Result.bind (ensure_open console) (fun () ->
      if console.visible then hide console else show console)

let focus console =
  Result.bind (ensure_open console) (fun () ->
      console.visible <- true;
      console.focused <- true;
      scroll_to_bottom_internal console;
      Ok ())

let blur console =
  Result.bind (ensure_open console) (fun () -> console.focused <- false; Ok ())

let clear console =
  Result.bind (ensure_open console) (fun () ->
      console.entries <- [];
      console.display_lines <- [];
      console.selection_start <- None;
      console.selection_end <- None;
      console.scroll_top <- 0;
      console.dragging <- false;
      Ok ())

let resize console ~width ~height =
  Result.bind (ensure_open console) (fun () ->
      if width <= 0 || height <= 0 then Result.Error Core_error.Invalid_argument
      else begin
        console.width <- width;
        console.height <- height;
        console.bounds <-
          calculate_bounds ~width ~height ~position:console.position
            ~size_percent:console.size_percent;
        rebuild_display_lines console;
        Ok ()
      end)

let set_position console position =
  Result.bind (ensure_open console) (fun () ->
      console.position <- position;
      console.bounds <-
        calculate_bounds ~width:console.width ~height:console.height ~position
          ~size_percent:console.size_percent;
      console.scroll_top <- clamp_scroll_top console console.scroll_top;
      Ok ())

let set_size_percent console value =
  Result.bind (ensure_open console) (fun () ->
      if value < 1 || value > 100 then Result.Error Core_error.Invalid_argument
      else begin
        console.size_percent <- value;
        console.bounds <-
          calculate_bounds ~width:console.width ~height:console.height
            ~position:console.position ~size_percent:value;
        rebuild_display_lines console;
        Ok ()
      end)

let clamp_selection_point console point =
  let line_count = List.length console.display_lines in
  let line = max 0 (min (max 0 (line_count - 1)) point.line) in
  let line_text =
    match List.nth_opt console.display_lines line with
    | None -> ""
    | Some value -> value.text
  in
  { line; column = max 0 (min (String.length line_text) point.column) }

let select console ~start_line ~start_column ~end_line ~end_column =
  Result.bind (ensure_open console) (fun () ->
      let start = clamp_selection_point console { line = start_line; column = start_column } in
      let finish = clamp_selection_point console { line = end_line; column = end_column } in
      console.selection_start <- Some start;
      console.selection_end <- Some finish;
      Ok ())

let clear_selection console =
  Result.bind (ensure_open console) (fun () ->
      console.selection_start <- None;
      console.selection_end <- None;
      Ok ())

let scroll_top console =
  Result.map (fun () -> console.scroll_top) (ensure_open console)

let scroll_up console =
  Result.bind (ensure_open console) (fun () ->
      console.scroll_top <- clamp_scroll_top console (console.scroll_top - 1);
      Ok ())

let scroll_down console =
  Result.bind (ensure_open console) (fun () ->
      console.scroll_top <- clamp_scroll_top console (console.scroll_top + 1);
      Ok ())

let scroll_to_top console =
  Result.bind (ensure_open console) (fun () -> console.scroll_top <- 0; Ok ())

let scroll_to_bottom console =
  Result.bind (ensure_open console) (fun () ->
      scroll_to_bottom_internal console;
      Ok ())

let normalized_selection console =
  match console.selection_start, console.selection_end with
  | Some start, Some finish ->
      if start.line < finish.line
         || (Int.equal start.line finish.line && start.column <= finish.column)
      then start, finish
      else finish, start
  | None, _ | _, None ->
      { line = 0; column = 0 }, { line = 0; column = 0 }

let has_selection console =
  Result.bind (ensure_open console) (fun () ->
      match console.selection_start, console.selection_end with
      | Some start, Some finish ->
          Ok (not (Int.equal start.line finish.line && Int.equal start.column finish.column))
      | None, _ | _, None -> Ok false)

let selected_text console =
  Result.bind (ensure_open console) (fun () ->
      match console.selection_start, console.selection_end with
      | None, _ | _, None -> Ok ""
      | Some _, Some _ ->
          let start, finish = normalized_selection console in
          let result = ref [] in
          let line_index = ref start.line in
          while !line_index <= finish.line do
            (match List.nth_opt console.display_lines !line_index with
            | None -> ()
            | Some line ->
                let first = if Int.equal !line_index start.line then start.column else 0 in
                let last = if Int.equal !line_index finish.line then finish.column else String.length line.text in
                if last >= first then result := String.sub line.text first (last - first) :: !result);
            line_index := !line_index + 1
          done;
          Ok (String.concat "\n" (List.rev !result)))

let selected_range console line_index line_length =
  match console.selection_start, console.selection_end with
  | Some _, Some _ ->
      let start, finish = normalized_selection console in
      if line_index < start.line || line_index > finish.line then None
      else
        let first = if Int.equal line_index start.line then start.column else 0 in
        let last = if Int.equal line_index finish.line then finish.column else line_length in
        Some (max 0 (min line_length first), max 0 (min line_length last))
  | None, _ | _, None -> None

let clip text width =
  if String.length text <= width then text else String.sub text 0 width

let draw_line buffer console line_index line_y line =
  let width = console.bounds.width in
  let text = clip line.text (max 1 (width - 1)) in
  let foreground = level_color line.level in
  let text_x = console.bounds.x + 1 in
  match selected_range console line_index (String.length text) with
  | None ->
      Buffer.draw_text buffer ~text ~x:(Int32.of_int text_x) ~y:(Int32.of_int line_y)
        ~foreground ~background:background_color ~attributes:0l
  | Some (start, finish) ->
      let prefix = if start > 0 then String.sub text 0 start else "" in
      let selected = if finish > start then String.sub text start (finish - start) else "" in
      let suffix =
        if finish < String.length text then
          String.sub text finish (String.length text - finish)
        else ""
      in
      if Int.equal start finish then
        Buffer.draw_text buffer ~text ~x:(Int32.of_int text_x)
          ~y:(Int32.of_int line_y) ~foreground ~background:background_color
          ~attributes:0l
      else
        Result.bind
          (Buffer.draw_text buffer ~text:prefix ~x:(Int32.of_int text_x)
             ~y:(Int32.of_int line_y)
             ~foreground ~background:background_color ~attributes:0l)
          (fun () ->
            Result.bind
              (Buffer.fill_rect buffer ~x:(Int32.of_int (text_x + start))
                 ~y:(Int32.of_int line_y)
                 ~width:(Int32.of_int (finish - start)) ~height:1l
                 ~background:selection_background_color)
              (fun () ->
                Result.bind
                  (Buffer.draw_text buffer ~text:selected
                     ~x:(Int32.of_int (text_x + start)) ~y:(Int32.of_int line_y)
                     ~foreground:selection_foreground_color
                     ~background:selection_background_color ~attributes:0l)
                  (fun () ->
                    Buffer.draw_text buffer ~text:suffix
                      ~x:(Int32.of_int (text_x + finish)) ~y:(Int32.of_int line_y)
                      ~foreground ~background:background_color ~attributes:0l)))

let render console buffer =
  Result.bind (ensure_open console) (fun () ->
      if not console.visible then Ok ()
      else
        let bounds = console.bounds in
        Result.bind
          (Buffer.fill_rect buffer ~x:(Int32.of_int bounds.x)
             ~y:(Int32.of_int bounds.y) ~width:(Int32.of_int bounds.width)
             ~height:(Int32.of_int bounds.height) ~background:background_color)
          (fun () ->
            let title = clip console.title (max 1 (bounds.width - 2)) in
            Result.bind
              (Buffer.fill_rect buffer ~x:(Int32.of_int bounds.x)
                 ~y:(Int32.of_int bounds.y) ~width:(Int32.of_int bounds.width)
                 ~height:1l ~background:title_background_color)
              (fun () ->
                Result.bind
                  (Buffer.draw_text buffer ~text:title
                     ~x:(Int32.of_int (bounds.x + 1))
                     ~y:(Int32.of_int bounds.y) ~foreground:Color.white
                     ~background:title_background_color ~attributes:0l)
                  (fun () ->
                    let available = visible_line_count console in
                    let lines =
                      List.filteri
                        (fun index line ->
                          ignore line;
                          index >= console.scroll_top
                          && index < console.scroll_top + available)
                        console.display_lines
                    in
                    let line_index = ref console.scroll_top in
                    let line_offset = ref 0 in
                    let result = ref (Ok ()) in
                    List.iter
                      (fun line ->
                        match !result with
                        | Error _ -> ()
                        | Ok () ->
                            result :=
                              draw_line buffer console !line_index
                                (bounds.y + 1 + !line_offset) line;
                            line_offset := !line_offset + 1;
                            line_index := !line_index + 1)
                      lines;
                    !result))))

let destroy console =
  if not console.destroyed then begin
    console.destroyed <- true;
    console.visible <- false;
    console.focused <- false;
    console.entries <- [];
    console.display_lines <- [];
    console.selection_start <- None;
    console.selection_end <- None;
    console.scroll_top <- 0;
    console.dragging <- false
  end

let is_destroyed console = console.destroyed

let handle_mouse console ~action ~button ~x ~y =
  Result.bind (ensure_open console) (fun () ->
      let bounds = console.bounds in
      let inside =
        x >= bounds.x && x < bounds.x + bounds.width && y >= bounds.y
        && y < bounds.y + bounds.height
      in
      if not inside then Ok false
      else if button <> 0 then Ok false
      else
        match action with
        | Mouse_down ->
            if y = bounds.y then Ok true
            else
              let line = console.scroll_top + y - bounds.y - 1 in
              let column = max 0 (x - bounds.x - 1) in
              Result.bind
                (select console ~start_line:line ~start_column:column
                   ~end_line:line ~end_column:column)
                (fun () ->
                  console.dragging <- true;
                  Ok true)
        | Mouse_drag ->
            if not console.dragging then Ok false
            else
              let line = console.scroll_top + y - bounds.y - 1 in
              let column = max 0 (x - bounds.x - 1) in
              (match console.selection_start with
              | None -> Ok false
              | Some start ->
                  Result.bind
                    (select console ~start_line:start.line
                       ~start_column:start.column ~end_line:line
                       ~end_column:column)
                    (fun () -> Ok true))
        | Mouse_up ->
            let was_dragging = console.dragging in
            console.dragging <- false;
            Ok was_dragging)
