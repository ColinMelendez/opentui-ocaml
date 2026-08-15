type wrap_mode = No_wrap | Char | Word

type measure = {
  line_count : int32;
  width_cols_max : int32;
}

type line_info = {
  line_start_cols : int array;
  line_width_cols : int array;
  line_width_cols_max : int;
  line_sources : int array;
  line_wraps : int array;
}

type selection = {
  start : int;
  end_ : int;
  bg_color : Color.t option;
  fg_color : Color.t option;
}

type local_selection = {
  anchor_x : int;
  anchor_y : int;
  focus_x : int;
  focus_y : int;
  bg_color : Color.t option;
  fg_color : Color.t option;
}

type t = Text_buffer_view_internal.t

let map_error error =
  match error with
  | Opentui_raw.Error.Closed -> Error.Closed
  | error -> Error.Native (Native.Error.Native error)

let map_result result =
  match result with
  | Ok value -> Ok value
  | Error error -> Result.Error (map_error error)

let raw_wrap_mode = function
  | No_wrap -> Opentui_raw.Text_buffer_view.No_wrap
  | Char -> Opentui_raw.Text_buffer_view.Char
  | Word -> Opentui_raw.Text_buffer_view.Word

let create (buffer : Text_buffer.t) =
  match
    Opentui_raw.Text_buffer_view.create
      (Text_buffer_internal.raw (buffer : Text_buffer_internal.t))
  with
  | Error error -> Result.Error (map_error error)
  | Ok view -> Ok (Text_buffer_view_internal.of_raw view (buffer : Text_buffer_internal.t))

let raw view = Text_buffer_view_internal.raw view

let set_wrap_width view width =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer_view.set_wrap_width (raw view) width))
    (fun () ->
      Text_buffer_view_internal.set_wrap_width view width;
      Ok ())

let set_wrap_mode view mode =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer_view.set_wrap_mode (raw view)
          (raw_wrap_mode mode)))
    (fun () ->
      let internal_mode =
        match mode with
        | No_wrap -> Text_buffer_view_internal.No_wrap
        | Char -> Text_buffer_view_internal.Char
        | Word -> Text_buffer_view_internal.Word
      in
      Text_buffer_view_internal.set_wrap_mode view internal_mode;
      Ok ())

let set_first_line_offset view offset =
  Result.bind
    (map_result
       (Opentui_raw.Text_buffer_view.set_first_line_offset (raw view) offset))
    (fun () ->
      Text_buffer_view_internal.set_first_line_offset view offset;
      Ok ())

let measure_for_dimensions view ~width ~height =
  match
    Opentui_raw.Text_buffer_view.measure_for_dimensions (raw view) ~width ~height
  with
  | Error error -> Result.Error (map_error error)
  | Ok measure ->
      Ok
        {
          line_count = measure.line_count;
          width_cols_max = measure.width_cols_max;
        }

let close view =
  Result.bind (map_result (Opentui_raw.Text_buffer_view.close (raw view))) (fun () ->
      Text_buffer_view_internal.mark_closed view;
      Ok ())

let ensure_open view =
  if Text_buffer_view_internal.is_open view then Ok () else Error Error.Closed

let internal_selection (value : selection) : Text_buffer_view_internal.selection =
  {
    start = value.start;
    end_ = value.end_;
    bg_color = value.bg_color;
    fg_color = value.fg_color;
  }

let internal_local_selection (value : local_selection) : Text_buffer_view_internal.local_selection =
  {
    anchor_x = value.anchor_x;
    anchor_y = value.anchor_y;
    focus_x = value.focus_x;
    focus_y = value.focus_y;
    bg_color = value.bg_color;
    fg_color = value.fg_color;
  }

let normalize_range start finish =
  if start <= finish then start, finish else finish, start

let raw_color = Option.map Color.Private.to_raw

let fits_int32 value =
  Int64.compare (Int64.of_int value) (Int64.of_int32 Int32.min_int) >= 0
  && Int64.compare (Int64.of_int value) (Int64.of_int32 Int32.max_int) <= 0

let set_selection view ~start ~end_ ?bg_color ?fg_color () =
  Result.bind (ensure_open view) (fun () ->
      if start < 0 || end_ < 0 then Error Error.Invalid_argument
      else
        let start, end_ = normalize_range start end_ in
        let value = { start; end_; bg_color; fg_color } in
        let raw_bg_color = raw_color bg_color in
        let raw_fg_color = raw_color fg_color in
        Result.bind
          (map_result
             (Opentui_raw.Text_buffer_view.set_selection (raw view) ~start
                ~end_ ?bg_color:raw_bg_color ?fg_color:raw_fg_color ()))
          (fun () ->
            Text_buffer_view_internal.set_selection view
              (Some (internal_selection value));
            Ok ()))

let update_selection view ~end_ ?bg_color ?fg_color () =
  Result.bind (ensure_open view) (fun () ->
      if end_ < 0 then Error Error.Invalid_argument
      else
        match Text_buffer_view_internal.selection view with
        | None -> Error Error.Invalid_argument
        | Some previous ->
            let bg_color =
              match bg_color with None -> previous.bg_color | Some color -> Some color
            in
            let fg_color =
              match fg_color with None -> previous.fg_color | Some color -> Some color
            in
            let start, finish = normalize_range previous.start end_ in
            let raw_bg_color = raw_color bg_color in
            let raw_fg_color = raw_color fg_color in
            Result.bind
              (map_result
                 (Opentui_raw.Text_buffer_view.update_selection (raw view)
                    ~end_:finish ?bg_color:raw_bg_color
                    ?fg_color:raw_fg_color ()))
              (fun () ->
                Text_buffer_view_internal.set_selection view
                  (Some { start; end_ = finish; bg_color; fg_color });
                Ok ()))

let reset_selection view =
  Result.bind (ensure_open view) (fun () ->
      Result.bind (map_result (Opentui_raw.Text_buffer_view.reset_selection (raw view)))
        (fun () ->
          Text_buffer_view_internal.set_selection view None;
          Ok ()))

let selection view =
  Result.bind (ensure_open view) (fun () ->
      Result.bind (map_result (Opentui_raw.Text_buffer_view.selection (raw view)))
        (fun native_selection ->
          match native_selection with
          | None ->
              Text_buffer_view_internal.set_selection view None;
              Ok None
          | Some native_selection ->
              let previous = Text_buffer_view_internal.selection view in
              let bg_color, fg_color =
                match previous with
                | None -> None, None
                | Some previous -> previous.bg_color, previous.fg_color
              in
              let value =
                {
                  start = native_selection.start;
                  end_ = native_selection.end_;
                  bg_color;
                  fg_color;
                }
              in
              Text_buffer_view_internal.set_selection view
                (Some (internal_selection value));
              Ok (Some value)))

let has_selection view = Result.map Option.is_some (selection view)

let set_local_selection view ~anchor_x ~anchor_y ~focus_x ~focus_y ?bg_color ?fg_color () =
  Result.bind (ensure_open view) (fun () ->
      if not (fits_int32 anchor_x && fits_int32 anchor_y && fits_int32 focus_x
              && fits_int32 focus_y)
      then Error Error.Invalid_argument
      else
        let value =
          { anchor_x; anchor_y; focus_x; focus_y; bg_color; fg_color }
        in
        Result.bind
          (map_result
             (Opentui_raw.Text_buffer_view.set_local_selection (raw view) ~anchor_x
                ~anchor_y ~focus_x ~focus_y ?bg_color:(raw_color bg_color)
                ?fg_color:(raw_color fg_color) ()))
          (fun changed ->
            Text_buffer_view_internal.set_local_selection view
              (Some (internal_local_selection value));
            Ok changed))

let update_local_selection view ~anchor_x ~anchor_y ~focus_x ~focus_y ?bg_color ?fg_color () =
  Result.bind (ensure_open view) (fun () ->
      if not (fits_int32 anchor_x && fits_int32 anchor_y && fits_int32 focus_x
              && fits_int32 focus_y)
      then Error Error.Invalid_argument
      else
        let value =
          { anchor_x; anchor_y; focus_x; focus_y; bg_color; fg_color }
        in
        Result.bind
          (map_result
             (Opentui_raw.Text_buffer_view.update_local_selection (raw view)
                ~anchor_x ~anchor_y ~focus_x ~focus_y
                ?bg_color:(raw_color bg_color) ?fg_color:(raw_color fg_color) ()))
          (fun changed ->
            Text_buffer_view_internal.set_local_selection view
              (Some (internal_local_selection value));
            Ok changed))

let reset_local_selection view =
  Result.bind (ensure_open view) (fun () ->
      Result.bind
        (map_result
           (Opentui_raw.Text_buffer_view.reset_local_selection (raw view)))
        (fun () ->
          Text_buffer_view_internal.set_local_selection view None;
          Ok ()))

let plain_text view =
  Result.bind (ensure_open view) (fun () ->
      Text_buffer.text (Text_buffer_view_internal.buffer view))

let set_viewport_size view ~width ~height =
  Result.bind (ensure_open view) (fun () ->
      if width < 0l || height < 0l then Error Error.Invalid_argument
      else
        let x, y, current_width, current_height =
          Text_buffer_view_internal.viewport view
        in
        ignore current_width;
        ignore current_height;
        Result.bind
          (map_result
             (Opentui_raw.Text_buffer_view.set_viewport_size (raw view) ~width
                ~height))
          (fun () ->
            Text_buffer_view_internal.set_viewport view ~x ~y ~width ~height;
            Ok ()))

let set_viewport view ~x ~y ~width ~height =
  Result.bind (ensure_open view) (fun () ->
      if x < 0l || y < 0l || width < 0l || height < 0l then Error Error.Invalid_argument
      else begin
        Result.bind
          (map_result
             (Opentui_raw.Text_buffer_view.set_viewport (raw view) ~x ~y ~width
                ~height))
          (fun () ->
            Text_buffer_view_internal.set_viewport view ~x ~y ~width ~height;
            Ok ())
      end)

let viewport view = Result.bind (ensure_open view) (fun () -> Ok (Text_buffer_view_internal.viewport view))

let line_info view =
  Result.bind (ensure_open view) (fun () ->
      match Opentui_raw.Text_buffer_view.line_info (raw view) with
      | Error error -> Error (map_error error)
      | Ok native ->
          Ok
            {
              line_start_cols = Array.map Int32.to_int native.line_start_cols;
              line_width_cols = Array.map Int32.to_int native.line_width_cols;
              line_width_cols_max = Int32.to_int native.line_width_cols_max;
              line_sources = Array.map Int32.to_int native.line_sources;
              line_wraps = Array.map Int32.to_int native.line_wraps;
            })

let logical_line_info view =
  Result.bind (ensure_open view) (fun () ->
      match Opentui_raw.Text_buffer_view.logical_line_info (raw view) with
      | Error error -> Error (map_error error)
      | Ok native ->
          Ok
            {
              line_start_cols = Array.map Int32.to_int native.line_start_cols;
              line_width_cols = Array.map Int32.to_int native.line_width_cols;
              line_width_cols_max = Int32.to_int native.line_width_cols_max;
              line_sources = Array.map Int32.to_int native.line_sources;
              line_wraps = Array.map Int32.to_int native.line_wraps;
            })

let selected_text view =
  Result.bind (ensure_open view) (fun () ->
      let buffer = Text_buffer_view_internal.buffer view in
      Result.bind (Text_buffer.byte_size buffer) (fun byte_size ->
          map_result
            (Opentui_raw.Text_buffer_view.selected_text (raw view)
               ~capacity:(Int32.to_int byte_size))))

let virtual_line_count view =
  Result.bind (ensure_open view) (fun () ->
      map_result (Opentui_raw.Text_buffer_view.virtual_line_count (raw view)))

let set_tab_indicator view indicator =
  Result.bind (ensure_open view) (fun () ->
      let codepoints = Lib.Text_metrics.scan Lib.Text_metrics.Unicode indicator in
      let codepoint =
        if Array.length codepoints = 0 then 0l
        else Int32.of_int codepoints.(0).code
      in
      Result.bind
        (map_result
           (Opentui_raw.Text_buffer_view.set_tab_indicator (raw view) codepoint))
        (fun () ->
          Text_buffer_view_internal.set_tab_indicator view indicator;
          Ok ()))

let tab_indicator view = Result.bind (ensure_open view) (fun () -> Ok (Text_buffer_view_internal.tab_indicator view))

let set_tab_indicator_color view color =
  Result.bind (ensure_open view) (fun () ->
      Result.bind
        (map_result
           (Opentui_raw.Text_buffer_view.set_tab_indicator_color (raw view)
              (Color.Private.to_raw color)))
        (fun () ->
          Text_buffer_view_internal.set_tab_indicator_color view (Some color);
          Ok ()))

let tab_indicator_color view =
  Result.bind (ensure_open view) (fun () -> Ok (Text_buffer_view_internal.tab_indicator_color view))

let set_truncate view value =
  Result.bind (ensure_open view) (fun () ->
      Result.bind
        (map_result (Opentui_raw.Text_buffer_view.set_truncate (raw view) value))
        (fun () ->
          Text_buffer_view_internal.set_truncate view value;
          Ok ()))

let truncate view = Result.bind (ensure_open view) (fun () -> Ok (Text_buffer_view_internal.truncate view))
