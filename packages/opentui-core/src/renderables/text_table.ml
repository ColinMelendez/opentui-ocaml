type cell_content = Empty | Text of string | Styled of Lib.Styled_text.t
type content = cell_content list list
type alignment = Default | Left | Center | Right
type column_width_mode = Content | Full
type column_fitter = Proportional | Balanced

type cell_state = {
  text_buffer : Text_buffer.t;
  text_buffer_view : Text_buffer_view.t;
  syntax_style : Syntax_style.t;
}

type border_layout = {
  left : bool;
  right : bool;
  top : bool;
  bottom : bool;
  inner_vertical : bool;
  inner_horizontal : bool;
}

type layout = {
  column_widths : int array;
  row_heights : int array;
  column_offsets : int array;
  row_offsets : int array;
  table_width : int;
  table_height : int;
}

type t = {
  renderable : Renderable.t;
  buffer : Owned_buffer.t;
  width_method : Text_buffer.width_method;
  mutable content : content;
  mutable column_alignments : alignment list;
  mutable cells : cell_state array array;
  mutable wrap_mode : Text_buffer_view.wrap_mode;
  mutable column_width_mode : column_width_mode;
  mutable column_fitter : column_fitter;
  mutable cell_padding_x : int;
  mutable cell_padding_y : int;
  mutable column_gap : int;
  mutable show_borders : bool;
  mutable border : bool;
  mutable outer_border : bool;
  mutable selectable : bool;
  mutable selection_bg : Color.t option;
  mutable selection_fg : Color.t option;
  mutable border_style : Lib.Border.style;
  mutable border_color : Color.t;
  mutable border_background_color : Color.t;
  mutable background_color : Color.t;
  mutable default_fg : Color.t;
  mutable default_bg : Color.t;
  mutable default_attributes : int32;
  mutable local_selection : Lib.Selection.local_bounds option;
  mutable layout : layout;
  mutable layout_dirty : bool;
  mutable raster_dirty : bool;
  mutable cached_measure : (int option * layout) option;
  mutable destroyed : bool;
}

let empty_layout =
  {
    column_widths = [||];
    row_heights = [||];
    column_offsets = [| 0 |];
    row_offsets = [| 0 |];
    table_width = 0;
    table_height = 0;
  }

let normalize_nonnegative value = max 0 value

let styled_text_of_content = function
  | Empty -> Lib.Styled_text.of_string ""
  | Text value -> Lib.Styled_text.of_string value
  | Styled value -> value

let alignment_for_column state column =
  match List.nth_opt state.column_alignments column with
  | Some alignment -> alignment
  | None -> Default

let cell_content_width state column =
  max 1 (state.layout.column_widths.(column) - state.cell_padding_x * 2)

let cell_alignment_offset state cell column =
  let content_width = cell_content_width state column in
  match alignment_for_column state column with
  | Default | Left -> 0
  | Center | Right ->
      (match
         Text_buffer_view.measure_for_dimensions cell.text_buffer_view
           ~width:(Int32.of_int content_width) ~height:10000l
       with
      | Error _ -> 0
      | Ok measure ->
          let text_width = max 0 (Int32.to_int measure.width_cols_max) in
          let remaining = max 0 (content_width - min content_width text_width) in
          match alignment_for_column state column with
          | Center -> remaining / 2
          | Right -> remaining
          | Default | Left -> 0)

let close_cell cell =
  ignore (Text_buffer_view.close cell.text_buffer_view);
  ignore (Text_buffer.set_syntax_style cell.text_buffer None);
  ignore (Text_buffer.close cell.text_buffer);
  Syntax_style.destroy cell.syntax_style

let close_cells cells =
  Array.iter (fun row -> Array.iter close_cell row) cells

let create_cell state content =
  Result.bind (Text_buffer.create state.width_method) (fun text_buffer ->
      let syntax_style = Syntax_style.create () in
      let cleanup () =
        ignore (Text_buffer.set_syntax_style text_buffer None);
        ignore (Text_buffer.close text_buffer);
        Syntax_style.destroy syntax_style
      in
      Result.bind
        (Text_buffer.set_default_fg text_buffer (Some state.default_fg))
        (fun () ->
          Result.bind
            (Text_buffer.set_default_bg text_buffer (Some state.default_bg))
            (fun () ->
              Result.bind
                (Text_buffer.set_default_attributes text_buffer
                   (Some (Int32.to_int state.default_attributes)))
                (fun () ->
                  Result.bind
                    (Text_buffer.set_syntax_style text_buffer
                       (Some syntax_style))
                    (fun () ->
                      Result.bind
                        (Text_buffer.set_styled_text text_buffer
                           (styled_text_of_content content))
                        (fun () ->
                          match Text_buffer_view.create text_buffer with
                          | Error error -> cleanup (); Error error
                          | Ok text_buffer_view ->
                              (match
                                 Text_buffer_view.set_wrap_mode text_buffer_view
                                   state.wrap_mode
                               with
                              | Ok () ->
                                  Ok { text_buffer; text_buffer_view; syntax_style }
                              | Error error ->
                                  ignore
                                    (Text_buffer_view.close text_buffer_view);
                                  cleanup ();
                                  Error error)))))))

let create_cells state content =
  let rows = ref [] in
  let current_row = ref [||] in
  let failure = ref None in
  List.iter
    (fun row_content ->
      match !failure with
      | Some _ -> ()
      | None ->
          let row = ref [] in
          current_row := [||];
          List.iter
            (fun cell_content ->
              match !failure with
              | Some _ -> ()
              | None ->
                  (match create_cell state cell_content with
                  | Ok cell -> row := cell :: !row
                  | Error error ->
                      current_row := Array.of_list (List.rev !row);
                      failure := Some error))
            row_content;
          (match !failure with
          | Some _ -> ()
          | None ->
              current_row := Array.of_list (List.rev !row);
              rows := !current_row :: !rows))
    content;
  match !failure with
  | Some error ->
      List.iter (fun row -> Array.iter close_cell row) !rows;
      Array.iter close_cell !current_row;
      Error error
  | None -> Ok (Array.of_list (List.rev !rows))

let row_count state = Array.length state.cells

let column_count state =
  let columns = ref 0 in
  Array.iter (fun row -> columns := max !columns (Array.length row)) state.cells;
  !columns

let resolve_border_layout state =
  {
    left = state.outer_border;
    right = state.outer_border;
    top = state.outer_border;
    bottom = state.outer_border;
    inner_vertical = state.border && column_count state > 1;
    inner_horizontal = state.border && row_count state > 1;
  }

let vertical_border_count borders columns =
  (if borders.left then 1 else 0)
  + (if borders.right then 1 else 0)
  + if borders.inner_vertical then max 0 (columns - 1) else 0

let total_inter_column_gap state borders columns =
  if borders.inner_vertical then 0 else max 0 (columns - 1) * state.column_gap

let intrinsic_column_widths state columns =
  let padding = state.cell_padding_x * 2 in
  let widths = Array.make columns (1 + padding) in
  Array.iter
    (fun row ->
      for column = 0 to Array.length row - 1 do
        let measure =
          Text_buffer_view.measure_for_dimensions row.(column).text_buffer_view
            ~width:0l ~height:10000l
        in
        match measure with
        | Error _ -> ()
        | Ok measure ->
            widths.(column) <-
              max widths.(column) (max 1 (Int32.to_int measure.width_cols_max) + padding)
      done)
    state.cells;
  widths

let expand_column_widths widths target_width =
  let result = Array.copy widths in
  let total = Array.fold_left ( + ) 0 result in
  if total < target_width && Array.length result > 0 then begin
    let extra = target_width - total in
    let shared = extra / Array.length result in
    let remainder = extra mod Array.length result in
    for index = 0 to Array.length result - 1 do
      result.(index) <- result.(index) + shared + if index < remainder then 1 else 0
    done
  end;
  result

let allocate_shrink shrinkable target_shrink =
  let count = Array.length shrinkable in
  let shrink = Array.make count 0 in
  if target_shrink <= 0 then shrink
  else
    let weights =
      Array.map
        (fun value -> if value <= 0 then 0.0 else sqrt (float_of_int value))
        shrinkable
    in
    let total_weight = Array.fold_left ( +. ) 0.0 weights in
    if total_weight <= 0.0 then shrink
    else begin
      let fractions = Array.make count 0.0 in
      let used = ref 0 in
      for index = 0 to count - 1 do
        if shrinkable.(index) > 0 && weights.(index) > 0.0 then begin
          let exact = weights.(index) /. total_weight *. float_of_int target_shrink in
          let whole = min shrinkable.(index) (int_of_float (Float.floor exact)) in
          shrink.(index) <- whole;
          fractions.(index) <- exact -. float_of_int whole;
          used := !used + whole
        end
      done;
      let remaining = ref (target_shrink - !used) in
      while !remaining > 0 do
        let best = ref (-1) in
        for index = 0 to count - 1 do
          if shrinkable.(index) - shrink.(index) > 0 then
      if Int.equal !best (-1) || fractions.(index) > fractions.(!best)
               || (Float.equal fractions.(index) fractions.(!best)
                   && shrinkable.(index) > shrinkable.(!best))
            then best := index
        done;
        if Int.equal !best (-1) then remaining := 0
        else begin
          shrink.(!best) <- shrink.(!best) + 1;
          fractions.(!best) <- 0.0;
          decr remaining
        end
      done;
      shrink
    end

let fit_balanced widths target_width min_width =
  let count = Array.length widths in
  let total = Array.fold_left ( + ) 0 widths in
  if Int.equal count 0 || total <= target_width then Array.copy widths
  else
    let even_share = max min_width (target_width / count) in
    let preferred = Array.map (fun width -> min width even_share) widths in
    let preferred_total = Array.fold_left ( + ) 0 preferred in
    let floor_widths =
      if preferred_total <= target_width then preferred
      else Array.make count min_width
    in
    let floor_total = Array.fold_left ( + ) 0 floor_widths in
    let clamped_target = max floor_total target_width in
    if total <= clamped_target then Array.copy widths
    else
      let shrinkable =
        Array.mapi (fun index width -> width - floor_widths.(index)) widths
      in
      let total_shrinkable = Array.fold_left ( + ) 0 shrinkable in
      if total_shrinkable <= 0 then Array.copy floor_widths
      else
        let shrink = allocate_shrink shrinkable (total - clamped_target) in
        Array.mapi
          (fun index width -> max floor_widths.(index) (width - shrink.(index)))
          widths

let compute_column_widths state max_table_width borders columns =
  let intrinsic = intrinsic_column_widths state columns in
  match max_table_width with
  | None -> intrinsic
  | Some max_width ->
      let max_content_width =
        max 1
          (max_width - vertical_border_count borders columns
          - total_inter_column_gap state borders columns)
      in
      let current_width = Array.fold_left ( + ) 0 intrinsic in
      if Int.equal current_width max_content_width then intrinsic
      else if current_width < max_content_width then
        (match state.column_width_mode with
        | Full -> expand_column_widths intrinsic max_content_width
        | Content -> intrinsic)
      else
        match state.wrap_mode with
        | Text_buffer_view.No_wrap -> intrinsic
        | Text_buffer_view.Char | Text_buffer_view.Word ->
            let min_width = 1 + state.cell_padding_x * 2 in
            (match state.column_fitter with
            | Proportional ->
                Array.of_list
                  (Text_table_width.allocate_proportional_column_widths
                     ~widths:(Array.to_list intrinsic)
                     ~target_width:max_content_width ~min_width)
            | Balanced -> fit_balanced intrinsic max_content_width min_width)

let compute_row_heights state column_widths =
  let rows = row_count state in
  let columns = column_count state in
  let heights = Array.make rows (1 + state.cell_padding_y * 2) in
  let horizontal_padding = state.cell_padding_x * 2 in
  let vertical_padding = state.cell_padding_y * 2 in
  for row_index = 0 to rows - 1 do
    let row = state.cells.(row_index) in
    for column = 0 to min (Array.length row) columns - 1 do
      let content_width = max 1 (column_widths.(column) - horizontal_padding) in
      let wrap_width =
        match state.wrap_mode with
        | Text_buffer_view.No_wrap -> None
        | Text_buffer_view.Char | Text_buffer_view.Word ->
            Some (Int32.of_int content_width)
      in
      ignore
        (Text_buffer_view.set_wrap_width row.(column).text_buffer_view wrap_width);
      let measure =
        Text_buffer_view.measure_for_dimensions row.(column).text_buffer_view
          ~width:(Int32.of_int content_width) ~height:10000l
      in
      match measure with
      | Error _ -> ()
      | Ok measure ->
          heights.(row_index) <-
            max heights.(row_index)
              (max 1 (Int32.to_int measure.line_count) + vertical_padding)
    done
  done;
  heights

let compute_offsets parts start_boundary end_boundary inner_boundary inner_gap =
  let initial = if start_boundary then 0 else -1 in
  let offsets = ref [ initial ] in
  let cursor = ref initial in
  Array.iteri
    (fun index part ->
      let separator_after =
        if index < Array.length parts - 1 then
          if inner_boundary then 1 else inner_gap
        else if end_boundary then 1
        else 0
      in
      cursor := !cursor + part + separator_after;
      offsets := !cursor :: !offsets)
    parts;
  Array.of_list (List.rev !offsets)

let compute_layout state max_table_width =
  let rows = row_count state in
  let columns = column_count state in
  if Int.equal rows 0 || Int.equal columns 0 then empty_layout
  else
    let borders = resolve_border_layout state in
    let widths = compute_column_widths state max_table_width borders columns in
    let heights = compute_row_heights state widths in
    let gap = if borders.inner_vertical then 0 else state.column_gap in
    let column_offsets =
      compute_offsets widths borders.left borders.right borders.inner_vertical gap
    in
    let row_offsets =
      compute_offsets heights borders.top borders.bottom borders.inner_horizontal 0
    in
    {
      column_widths = widths;
      row_heights = heights;
      column_offsets;
      row_offsets;
      table_width = column_offsets.(Array.length column_offsets - 1) + 1;
      table_height = row_offsets.(Array.length row_offsets - 1) + 1;
    }

let resolve_width_constraint state width width_mode =
  match width_mode with
  | Measure_callback.Undefined -> None
  | Measure_callback.Exactly | Measure_callback.At_most ->
      if (match classify_float width with FP_nan | FP_infinite -> true | _ -> false)
      then None
      else
        let wrapping =
          match state.wrap_mode with
          | Text_buffer_view.No_wrap -> false
          | Text_buffer_view.Char | Text_buffer_view.Word -> true
        in
        let full_width =
          match state.column_width_mode with Full -> true | Content -> false
        in
        if wrapping || full_width then
          Some (max 1 (int_of_float (Float.floor width)))
        else None

let measure_callback state ~width ~width_mode ~height:_ ~height_mode:_ =
  let constraint_width = resolve_width_constraint state width width_mode in
  let layout = compute_layout state constraint_width in
  state.cached_measure <- Some (constraint_width, layout);
  let measured_width = max 1 layout.table_width in
  let measured_width =
    match width_mode, constraint_width with
    | Measure_callback.At_most, Some width -> min width measured_width
    | _ -> measured_width
  in
  float_of_int measured_width, float_of_int (max 1 layout.table_height)

let max_layout_width state =
  let width = Renderable.width state.renderable in
  if width <= 0.0 then None
  else resolve_width_constraint state width Measure_callback.Exactly

let apply_layout_to_views state value =
  let horizontal_padding = state.cell_padding_x * 2 in
  let vertical_padding = state.cell_padding_y * 2 in
  for row_index = 0 to row_count state - 1 do
    let row = state.cells.(row_index) in
    for column = 0 to Array.length row - 1 do
      let column_width = value.column_widths.(column) in
      let row_height = value.row_heights.(row_index) in
      let content_width = max 1 (column_width - horizontal_padding) in
      let content_height = max 1 (row_height - vertical_padding) in
      let wrap_width =
        match state.wrap_mode with
        | Text_buffer_view.No_wrap -> None
        | Text_buffer_view.Char | Text_buffer_view.Word ->
            Some (Int32.of_int content_width)
      in
      ignore
        (Text_buffer_view.set_wrap_width row.(column).text_buffer_view wrap_width);
      ignore
        (Text_buffer_view.set_viewport row.(column).text_buffer_view ~x:0l ~y:0l
           ~width:(Int32.of_int content_width)
           ~height:(Int32.of_int content_height))
    done
  done

let line_start offsets index = offsets.(index) + 1

let rebuild_layout state =
  let width = max_layout_width state in
  let cached_width_matches cached_width =
    match cached_width, width with
    | None, None -> true
    | Some left, Some right -> Int.equal left right
    | None, Some _ | Some _, None -> false
  in
  let value =
    match state.cached_measure with
    | Some (cached_width, value) when cached_width_matches cached_width -> value
    | _ -> compute_layout state width
  in
  state.cached_measure <- None;
  state.layout <- value;
  apply_layout_to_views state value;
  state.layout_dirty <- false

let ensure_layout state =
  if state.layout_dirty then rebuild_layout state

type selection_mode = Single_cell | Column_locked | Grid

let cell_at state local_x local_y =
  if Int.equal (row_count state) 0 || Int.equal (column_count state) 0
     || local_x < 0 || local_y < 0
     || local_x >= state.layout.table_width
     || local_y >= state.layout.table_height
  then None
  else
    let row_index = ref (-1) in
    for index = 0 to row_count state - 1 do
      let top = line_start state.layout.row_offsets index in
      let bottom = top + state.layout.row_heights.(index) - 1 in
      if Int.equal !row_index (-1) && local_y >= top && local_y <= bottom then
        row_index := index
    done;
    let column_index = ref (-1) in
    for index = 0 to column_count state - 1 do
      let left = line_start state.layout.column_offsets index in
      let right = left + state.layout.column_widths.(index) - 1 in
      if Int.equal !column_index (-1) && local_x >= left && local_x <= right then
        column_index := index
    done;
    if !row_index < 0 || !column_index < 0 then None
    else Some (!row_index, !column_index)

let reset_cell_selections state =
  Array.iter
    (fun row ->
      Array.iter
        (fun cell -> ignore (Text_buffer_view.reset_local_selection cell.text_buffer_view))
        row)
    state.cells

let row_for_y state local_y =
  if Int.equal (row_count state) 0 then 0
  else if local_y < 0 then 0
  else
    let result = ref (row_count state - 1) in
    for index = 0 to row_count state - 1 do
      let top = line_start state.layout.row_offsets index in
      let bottom = top + state.layout.row_heights.(index) - 1 in
      if local_y <= bottom && Int.equal !result (row_count state - 1) then result := index
      else if local_y >= top && local_y <= bottom then result := index
    done;
    !result

let apply_selection_to_cells state
    (local_selection : Lib.Selection.local_bounds) =
  reset_cell_selections state;
  let same_point =
      Float.equal local_selection.Lib.Selection.anchor_x
        local_selection.Lib.Selection.focus_x
    && Float.equal local_selection.Lib.Selection.anchor_y
         local_selection.Lib.Selection.focus_y
  in
  if not same_point then begin
    let anchor_cell =
      cell_at state
        (int_of_float (Float.floor local_selection.anchor_x))
        (int_of_float (Float.floor local_selection.anchor_y))
    in
    let focus_cell =
      cell_at state
        (int_of_float (Float.floor local_selection.focus_x))
        (int_of_float (Float.floor local_selection.focus_y))
    in
    let anchor_column =
      match anchor_cell with
      | Some (_, column) -> Some column
      | None ->
          let column = ref None in
          for index = 0 to column_count state - 1 do
            let left = line_start state.layout.column_offsets index in
            let right = left + state.layout.column_widths.(index) - 1 in
            if local_selection.anchor_x >= float_of_int left
               && local_selection.anchor_x <= float_of_int right
            then column := Some index
          done;
          !column
    in
    let focus_column =
      match focus_cell with
      | Some (_, column) -> Some column
      | None ->
          let column = ref None in
          for index = 0 to column_count state - 1 do
            let left = line_start state.layout.column_offsets index in
            let right = left + state.layout.column_widths.(index) - 1 in
            if local_selection.focus_x >= float_of_int left
               && local_selection.focus_x <= float_of_int right
            then column := Some index
          done;
          !column
    in
    let mode, anchor_cell =
      match anchor_cell, focus_cell with
      | Some anchor, Some focus
        when Int.equal (fst anchor) (fst focus)
             && Int.equal (snd anchor) (snd focus) ->
          Single_cell, Some anchor
      | _ ->
          (match anchor_column, focus_column with
          | Some left, Some right when Int.equal left right ->
              Column_locked, anchor_cell
          | _ -> Grid, anchor_cell)
    in
    let anchor_y = int_of_float (Float.floor local_selection.anchor_y) in
    let focus_y = int_of_float (Float.floor local_selection.focus_y) in
    let first_row = row_for_y state (min anchor_y focus_y) in
    let last_row = row_for_y state (max anchor_y focus_y) in
    for row_index = first_row to last_row do
      let row = state.cells.(row_index) in
      for column = 0 to Array.length row - 1 do
        let is_anchor =
          match anchor_cell with
          | Some (row, anchor_column) ->
              Int.equal row row_index && Int.equal anchor_column column
          | None -> false
        in
        let selected =
          match mode with
          | Single_cell -> is_anchor
          | Column_locked ->
              (match anchor_column with
              | Some anchor_column -> Int.equal anchor_column column
              | None -> false)
          | Grid -> true
        in
        if selected then begin
          let cell_left = line_start state.layout.column_offsets column + state.cell_padding_x in
          let cell_top = line_start state.layout.row_offsets row_index + state.cell_padding_y in
          let content_width =
            max 1 (state.layout.column_widths.(column) - state.cell_padding_x * 2)
          in
          let content_height =
            max 1 (state.layout.row_heights.(row_index) - state.cell_padding_y * 2)
          in
          let alignment_offset = cell_alignment_offset state row.(column) column in
          let anchor_x =
            local_selection.anchor_x -. float_of_int cell_left
            -. float_of_int alignment_offset
          in
          let anchor_y = local_selection.anchor_y -. float_of_int cell_top in
          let focus_x =
            local_selection.focus_x -. float_of_int cell_left
            -. float_of_int alignment_offset
          in
          let focus_y = local_selection.focus_y -. float_of_int cell_top in
          let anchor_x, anchor_y, focus_x, focus_y =
            if is_anchor
               && (match mode with Single_cell -> false | Column_locked | Grid -> true)
            then
              -1.0, 0.0, float_of_int content_width, float_of_int content_height
            else anchor_x, anchor_y, focus_x, focus_y
          in
          ignore
            (Text_buffer_view.set_local_selection row.(column).text_buffer_view
               ~anchor_x:(int_of_float (Float.floor anchor_x))
               ~anchor_y:(int_of_float (Float.floor anchor_y))
               ~focus_x:(int_of_float (Float.floor focus_x))
               ~focus_y:(int_of_float (Float.floor focus_y))
               ?bg_color:state.selection_bg ?fg_color:state.selection_fg ())
        end
      done
    done
  end

let render_borders state =
  if not state.show_borders then Ok ()
  else
    let borders = resolve_border_layout state in
    let columns = column_count state in
    let horizontal =
      (if borders.top then 1 else 0)
      + (if borders.bottom then 1 else 0)
      + if borders.inner_horizontal then max 0 (row_count state - 1) else 0
    in
    if Int.equal (vertical_border_count borders columns) 0
       && Int.equal horizontal 0
    then Ok ()
    else
      Owned_buffer.draw_grid state.buffer
        ~border_chars:(Lib.Border.Private.to_native
                         (Lib.Border.characters state.border_style))
        ~border_foreground:state.border_color
        ~border_background:state.border_background_color
        ~column_offsets:(Array.map Int32.of_int state.layout.column_offsets)
        ~row_offsets:(Array.map Int32.of_int state.layout.row_offsets)
        ~draw_inner:(borders.inner_vertical || borders.inner_horizontal)
        ~draw_outer:(borders.left || borders.right || borders.top || borders.bottom)

let render_cells state =
  let result = ref (Ok ()) in
  for row_index = 0 to row_count state - 1 do
    let row = state.cells.(row_index) in
    for column = 0 to Array.length row - 1 do
      match !result with
      | Error _ -> ()
      | Ok () ->
          let x =
            line_start state.layout.column_offsets column + state.cell_padding_x
            + cell_alignment_offset state row.(column) column
          in
          let y = line_start state.layout.row_offsets row_index + state.cell_padding_y in
          result :=
            Owned_buffer.draw_text_buffer_view state.buffer
              ~view:row.(column).text_buffer_view ~x ~y
    done
  done;
  !result

let rasterize state =
  Result.bind
    (Owned_buffer.clear state.buffer ~background:state.background_color)
    (fun () ->
      if row_count state = 0 || column_count state = 0 then Ok ()
      else Result.bind (render_borders state) (fun () -> render_cells state))

let render_self state renderable buffer _delta_time =
  ensure_layout state;
  let raster_result =
    if state.raster_dirty then begin
      let result = rasterize state in
      (match result with Ok () -> state.raster_dirty <- false | Error _ -> ());
      result
    end else Ok ()
  in
  Result.bind raster_result (fun () ->
      Buffer.draw_frame_buffer buffer ~source:state.buffer
        ~x:(Int32.of_float (Float.floor (Renderable.screen_x renderable)))
        ~y:(Int32.of_float (Float.floor (Renderable.screen_y renderable))) ())

let should_start_selection state renderable ~x ~y =
  state.selectable
  && not (Renderable.is_destroyed renderable)
  && (let local_x = x - int_of_float (Float.floor (Renderable.screen_x renderable)) in
      let local_y = y - int_of_float (Float.floor (Renderable.screen_y renderable)) in
      ensure_layout state;
      Option.is_some (cell_at state local_x local_y))

let selection_changed state renderable selection =
  let local =
    Lib.Selection.convert_global_to_local selection
      ~local_x:(Renderable.screen_x renderable)
      ~local_y:(Renderable.screen_y renderable)
  in
  state.local_selection <- local;
  (match local with
  | None -> reset_cell_selections state
  | Some local when not local.is_active -> reset_cell_selections state
  | Some local ->
      ensure_layout state;
      apply_selection_to_cells state local);
  state.raster_dirty <- true;
  ignore (Renderable.request_render state.renderable)

let set_cell_defaults state cell =
  ignore (Text_buffer.set_default_fg cell.text_buffer (Some state.default_fg));
  ignore (Text_buffer.set_default_bg cell.text_buffer (Some state.default_bg));
  ignore
    (Text_buffer.set_default_attributes cell.text_buffer
       (Some (Int32.to_int state.default_attributes)))

let invalidate_layout state =
  state.layout_dirty <- true;
  state.raster_dirty <- true;
  state.cached_measure <- None;
  ignore (Renderable.Private.mark_yoga_dirty state.renderable);
  ignore (Renderable.request_render state.renderable)

let invalidate_raster state =
  state.raster_dirty <- true;
  ignore (Renderable.request_render state.renderable)

let ensure_alive (state : t) =
  if state.destroyed || Renderable.is_destroyed state.renderable then
    Error Error.Destroyed
  else Ok ()

let destroy_resources state =
  ignore (Renderable.Private.clear_measure_func state.renderable);
  close_cells state.cells;
  state.cells <- [||];
  state.destroyed <- true;
  Owned_buffer.close state.buffer

let create context ?id ?(content = []) ?(column_alignments = [])
    ?(width_method = Text_buffer.Wcwidth)
    ?(wrap_mode = Text_buffer_view.Word) ?(column_width_mode = Full)
    ?(column_fitter = Proportional) ?(cell_padding = 0) ?cell_padding_x
    ?cell_padding_y ?(column_gap = 0) ?(show_borders = true) ?(border = true)
    ?outer_border ?(selectable = true) ?selection_bg ?selection_fg
    ?(border_style = Lib.Border.Single) ?(border_color = Color.white)
    ?(border_background_color = Color.transparent)
    ?(background_color = Color.transparent) ?(fg = Color.white)
    ?(bg = Color.transparent) ?(attributes = 0l) ?width ?height () =
  let padding_x = normalize_nonnegative (Option.value cell_padding_x ~default:cell_padding) in
  let padding_y = normalize_nonnegative (Option.value cell_padding_y ~default:cell_padding) in
  if cell_padding < 0 || column_gap < 0 then Error Error.Invalid_argument
  else
    Result.bind
      (Owned_buffer.create ~width:1 ~height:1 ~respect_alpha:false ~width_method ())
      (fun buffer ->
        match Renderable.Private.create context ?id () with
        | Error error -> Owned_buffer.close buffer; Error error
        | Ok renderable ->
            let state =
              {
                renderable;
                buffer;
                width_method;
                content = [];
                column_alignments;
                cells = [||];
                wrap_mode;
                column_width_mode;
                column_fitter;
                cell_padding_x = padding_x;
                cell_padding_y = padding_y;
                column_gap = normalize_nonnegative column_gap;
                show_borders;
                border;
                outer_border = Option.value outer_border ~default:border;
                selectable;
                selection_bg;
                selection_fg;
                border_style;
                border_color;
                border_background_color;
                background_color;
                default_fg = fg;
                default_bg = bg;
                default_attributes = attributes;
                local_selection = None;
                layout = empty_layout;
                layout_dirty = true;
                raster_dirty = true;
                cached_measure = None;
                destroyed = false;
              }
            in
            let behavior =
              Renderable.Private.make_behavior
                ~render_self:(render_self state)
                ~on_resize:(fun _ ~width ~height ->
                  if width > 0 && height > 0 then begin
                    ignore (Owned_buffer.resize state.buffer ~width ~height);
                    state.layout_dirty <- true;
                    state.raster_dirty <- true
                  end)
                ~selection_changed:(selection_changed state)
                ~should_start_selection:(should_start_selection state)
                ~destroy_self:(fun _ -> destroy_resources state) ()
            in
            Renderable.Private.set_behavior renderable behavior;
            (match create_cells state content with
            | Error error ->
                Renderable.destroy renderable;
                Error error
            | Ok cells ->
                state.content <- content;
                state.cells <- cells;
                let result =
                  Result.bind
                    (Renderable.Private.set_measure_func renderable
                       (measure_callback state))
                    (fun () ->
                      Result.bind
                        (Renderable.set_flex_shrink renderable (Some 0.0))
                        (fun () ->
                          Result.bind
                            (match width with
                            | None -> Ok ()
                            | Some width -> Renderable.set_width renderable width)
                            (fun () ->
                              match height with
                              | None -> Ok ()
                              | Some height -> Renderable.set_height renderable height)))
                in
                (match result with
                | Ok () -> Ok state
                | Error error -> Renderable.destroy renderable; Error error)))

let as_renderable (state : t) = state.renderable
let content (state : t) = state.content

let column_alignments (state : t) = state.column_alignments

let set_column_alignments state value =
  Result.bind (ensure_alive state) (fun () ->
      state.column_alignments <- value;
      invalidate_raster state;
      Ok ())

let set_content (state : t) value =
  Result.bind (ensure_alive state) (fun () ->
      Result.bind (create_cells state value) (fun cells ->
          close_cells state.cells;
          state.cells <- cells;
          state.content <- value;
          invalidate_layout state;
          Ok ()))

let wrap_mode (state : t) = state.wrap_mode

let set_wrap_mode state mode =
  Result.bind (ensure_alive state) (fun () ->
      Array.iter
        (fun row ->
          Array.iter
            (fun cell -> ignore (Text_buffer_view.set_wrap_mode cell.text_buffer_view mode))
            row)
        state.cells;
      state.wrap_mode <- mode;
      invalidate_layout state;
      Ok ())

let column_width_mode (state : t) = state.column_width_mode

let set_column_width_mode state mode =
  Result.bind (ensure_alive state) (fun () ->
      state.column_width_mode <- mode;
      invalidate_layout state;
      Ok ())

let column_fitter (state : t) = state.column_fitter

let set_column_fitter state fitter =
  Result.bind (ensure_alive state) (fun () ->
      state.column_fitter <- fitter;
      invalidate_layout state;
      Ok ())

let cell_padding state =
  if state.cell_padding_x = state.cell_padding_y then state.cell_padding_x else 0

let set_cell_padding state value =
  Result.bind (ensure_alive state) (fun () ->
      if value < 0 then Error Error.Invalid_argument
      else begin
        state.cell_padding_x <- value;
        state.cell_padding_y <- value;
        invalidate_layout state;
        Ok ()
      end)

let cell_padding_x (state : t) = state.cell_padding_x
let cell_padding_y (state : t) = state.cell_padding_y

let set_cell_padding_x state value =
  Result.bind (ensure_alive state) (fun () ->
      if value < 0 then Error Error.Invalid_argument
      else begin state.cell_padding_x <- value; invalidate_layout state; Ok () end)

let set_cell_padding_y state value =
  Result.bind (ensure_alive state) (fun () ->
      if value < 0 then Error Error.Invalid_argument
      else begin state.cell_padding_y <- value; invalidate_layout state; Ok () end)

let column_gap (state : t) = state.column_gap

let set_column_gap state value =
  Result.bind (ensure_alive state) (fun () ->
      if value < 0 then Error Error.Invalid_argument
      else begin state.column_gap <- value; invalidate_layout state; Ok () end)

let show_borders (state : t) = state.show_borders
let set_show_borders state value = Result.bind (ensure_alive state) (fun () -> state.show_borders <- value; invalidate_raster state; Ok ())
let border (state : t) = state.border
let set_border state value = Result.bind (ensure_alive state) (fun () -> state.border <- value; invalidate_layout state; Ok ())
let outer_border (state : t) = state.outer_border
let set_outer_border state value = Result.bind (ensure_alive state) (fun () -> state.outer_border <- value; invalidate_layout state; Ok ())
let selectable (state : t) = state.selectable
let set_selectable state value = Result.bind (ensure_alive state) (fun () -> state.selectable <- value; Ok ())
let border_style (state : t) = state.border_style
let set_border_style state value = Result.bind (ensure_alive state) (fun () -> state.border_style <- value; invalidate_raster state; Ok ())
let border_color (state : t) = state.border_color
let set_border_color state value = Result.bind (ensure_alive state) (fun () -> state.border_color <- value; invalidate_raster state; Ok ())
let border_background_color (state : t) = state.border_background_color
let set_border_background_color state value = Result.bind (ensure_alive state) (fun () -> state.border_background_color <- value; invalidate_raster state; Ok ())
let background_color (state : t) = state.background_color
let set_background_color state value = Result.bind (ensure_alive state) (fun () -> state.background_color <- value; invalidate_raster state; Ok ())
let fg (state : t) = state.default_fg
let bg (state : t) = state.default_bg

let set_fg state value =
  Result.bind (ensure_alive state) (fun () ->
      state.default_fg <- value;
      Array.iter (fun row -> Array.iter (set_cell_defaults state) row) state.cells;
      invalidate_raster state;
      Ok ())

let set_bg state value =
  Result.bind (ensure_alive state) (fun () ->
      state.default_bg <- value;
      Array.iter (fun row -> Array.iter (set_cell_defaults state) row) state.cells;
      invalidate_raster state;
      Ok ())

let attributes (state : t) = state.default_attributes

let set_attributes state value =
  Result.bind (ensure_alive state) (fun () ->
      state.default_attributes <- value;
      Array.iter (fun row -> Array.iter (set_cell_defaults state) row) state.cells;
      invalidate_raster state;
      Ok ())

let has_selection state =
  Result.bind (ensure_alive state) (fun () ->
      let selected = ref false in
      Array.iter
        (fun row ->
          Array.iter
            (fun cell ->
              match Text_buffer_view.has_selection cell.text_buffer_view with
              | Ok value -> selected := !selected || value
              | Error _ -> ())
            row)
        state.cells;
      Ok !selected)

let selected_text state =
  Result.bind (ensure_alive state) (fun () ->
      let rows = ref [] in
      Array.iter
        (fun row ->
          let values = ref [] in
          Array.iter
            (fun cell ->
              match Text_buffer_view.has_selection cell.text_buffer_view with
              | Error _ | Ok false -> ()
              | Ok true ->
                  (match Text_buffer_view.selected_text cell.text_buffer_view with
                  | Ok value when String.length value > 0 -> values := value :: !values
                  | Ok _ | Error _ -> ()))
            row;
          match !values with
          | [] -> ()
          | _ -> rows := String.concat "\t" (List.rev !values) :: !rows)
        state.cells;
      Ok (String.concat "\n" (List.rev !rows)))

let selection state =
  Result.bind (ensure_alive state) (fun () ->
      let result = ref None in
      Array.iter
        (fun row ->
          Array.iter
            (fun cell ->
              if Option.is_none !result then
                match Text_buffer_view.selection cell.text_buffer_view with
                | Ok (Some value) -> result := Some value
                | Ok None | Error _ -> ())
            row)
        state.cells;
      Ok !result)

let destroy state = Renderable.destroy state.renderable
