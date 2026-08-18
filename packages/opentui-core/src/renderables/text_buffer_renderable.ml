type t = {
  renderable : Renderable.t;
  text_buffer : Text_buffer.t;
  text_buffer_view : Text_buffer_view.t;
  native_measure : Native_measure.t;
  default_syntax_style : Syntax_style.t;
  mutable wrap_mode : Text_buffer_view.wrap_mode;
  selectable : bool;
  scrollable : bool;
  mutable scroll_x : int;
  mutable scroll_y : int;
  mutable last_local_selection : Lib.Selection.local_bounds option;
  mutable lifecycle_pass : (unit -> unit) option;
}

let close_resources text_buffer_renderable =
  ignore
    (Text_buffer.set_syntax_style text_buffer_renderable.text_buffer None);
  ignore (Native_measure.close text_buffer_renderable.native_measure);
  ignore (Text_buffer_view.close text_buffer_renderable.text_buffer_view);
  ignore (Text_buffer.close text_buffer_renderable.text_buffer);
  Syntax_style.destroy text_buffer_renderable.default_syntax_style

let cleanup_creation renderable text_buffer text_buffer_view native_measure
    syntax_style =
  ignore (Text_buffer.set_syntax_style text_buffer None);
  ignore (Native_measure.close native_measure);
  ignore (Text_buffer_view.close text_buffer_view);
  ignore (Text_buffer.close text_buffer);
  Syntax_style.destroy syntax_style;
  Renderable.destroy renderable

let mark_measure_dirty text_buffer_renderable =
  Renderable.Private.mark_yoga_dirty text_buffer_renderable.renderable

let update_native_viewport text_buffer_renderable ~x ~y ~width ~height =
  match
    Text_buffer_view.set_viewport text_buffer_renderable.text_buffer_view
      ~x:(Int32.of_int x) ~y:(Int32.of_int y) ~width:(Int32.of_int width)
      ~height:(Int32.of_int height)
  with
  | Ok () ->
      text_buffer_renderable.scroll_x <- x;
      text_buffer_renderable.scroll_y <- y;
      Ok ()
  | Error error -> Error error

let handle_scroll text_buffer_renderable event =
  match Renderable.mouse_scroll event with
  | None -> ()
  | Some scroll ->
      (match Text_buffer_view.viewport text_buffer_renderable.text_buffer_view with
      | Error _ -> ()
      | Ok (_, _, width, height) ->
          let current_x = text_buffer_renderable.scroll_x in
          let current_y = text_buffer_renderable.scroll_y in
          let delta = max 1 scroll.Lib.Mouse_decoder.delta in
          let next_x, next_y =
            match scroll.direction with
            | Lib.Mouse_decoder.Scroll_up -> current_x, max 0 (current_y - delta)
            | Lib.Mouse_decoder.Scroll_down ->
                let maximum =
                  match
                    Text_buffer_view.virtual_line_count
                      text_buffer_renderable.text_buffer_view
                  with
                  | Ok count -> max 0 (count - Int32.to_int height)
                  | Error _ -> 0
                in
                current_x, min maximum (current_y + delta)
            | Lib.Mouse_decoder.Scroll_left ->
                if
                  match text_buffer_renderable.wrap_mode with
                  | Text_buffer_view.No_wrap -> true
                  | Text_buffer_view.Char | Text_buffer_view.Word -> false
                then
                  max 0 (current_x - delta), current_y
                else current_x, current_y
            | Lib.Mouse_decoder.Scroll_right ->
                if
                  match text_buffer_renderable.wrap_mode with
                  | Text_buffer_view.No_wrap -> true
                  | Text_buffer_view.Char | Text_buffer_view.Word -> false
                then
                  let maximum =
                    match
                      Text_buffer_view.line_info
                        text_buffer_renderable.text_buffer_view
                    with
                    | Ok info -> max 0 (info.line_width_cols_max - Int32.to_int width)
                    | Error _ -> 0
                  in
                  min maximum (current_x + delta), current_y
                else current_x, current_y
          in
          if not (Int.equal current_x next_x && Int.equal current_y next_y) then begin
            ignore
              (update_native_viewport text_buffer_renderable ~x:next_x ~y:next_y
                 ~width:(Int32.to_int width) ~height:(Int32.to_int height));
            ignore (Renderable.request_render text_buffer_renderable.renderable);
            Renderable.mouse_prevent_default event
          end)

let install_behavior text_buffer_renderable =
  let on_resize _ ~width ~height =
    let wrap_width =
      match text_buffer_renderable.wrap_mode, width with
      | Text_buffer_view.No_wrap, _ | _, 0 -> None
      | _, width -> Some (Int32.of_int width)
    in
    ignore
      (Text_buffer_view.set_wrap_width
         text_buffer_renderable.text_buffer_view wrap_width);
    ignore
      (Text_buffer_view.set_viewport_size
         text_buffer_renderable.text_buffer_view ~width:(Int32.of_int width)
         ~height:(Int32.of_int height));
    ignore
      (update_native_viewport text_buffer_renderable ~x:text_buffer_renderable.scroll_x
         ~y:text_buffer_renderable.scroll_y ~width ~height);
    ignore (Renderable.Private.mark_yoga_dirty text_buffer_renderable.renderable)
  in
  let lifecycle_pass =
    Option.map
      (fun callback _ -> callback ())
      text_buffer_renderable.lifecycle_pass
  in
  let render_self renderable buffer _delta_time =
    Buffer.draw_text_buffer buffer
      ~view:text_buffer_renderable.text_buffer_view
      ~x:(Int32.of_float
            (Renderable.screen_x renderable))
      ~y:(Int32.of_float
            (Renderable.screen_y renderable))
  in
  let selection_changed renderable selection =
    match
      Lib.Selection.convert_global_to_local selection
        ~local_x:(Renderable.screen_x renderable)
        ~local_y:(Renderable.screen_y renderable)
    with
    | None ->
        text_buffer_renderable.last_local_selection <- None;
        ignore
          (Text_buffer_view.reset_local_selection
             text_buffer_renderable.text_buffer_view)
    | Some local when not local.is_active ->
        text_buffer_renderable.last_local_selection <- None;
        ignore (Text_buffer_view.reset_local_selection text_buffer_renderable.text_buffer_view)
    | Some local ->
        text_buffer_renderable.last_local_selection <- Some local;
        let anchor_x = int_of_float (Float.floor local.anchor_x) in
        let anchor_y = int_of_float (Float.floor local.anchor_y) in
        let focus_x = int_of_float (Float.floor local.focus_x) in
        let focus_y = int_of_float (Float.floor local.focus_y) in
        (match selection with
        | Some value when Lib.Selection.is_start value ->
            ignore
              (Text_buffer_view.set_local_selection
                 text_buffer_renderable.text_buffer_view ~anchor_x ~anchor_y
                 ~focus_x ~focus_y ())
        | Some _ ->
            ignore
              (Text_buffer_view.update_local_selection
                 text_buffer_renderable.text_buffer_view ~anchor_x ~anchor_y
                 ~focus_x ~focus_y ())
        | None ->
            ignore
              (Text_buffer_view.reset_local_selection
                 text_buffer_renderable.text_buffer_view))
  in
  let should_start_selection renderable ~x ~y =
    text_buffer_renderable.selectable
    && x >= int_of_float (Float.floor (Renderable.screen_x renderable))
    && y >= int_of_float (Float.floor (Renderable.screen_y renderable))
    && x < int_of_float (Float.ceil (Renderable.screen_x renderable +. Renderable.width renderable))
    && y < int_of_float (Float.ceil (Renderable.screen_y renderable +. Renderable.height renderable))
  in
  let behavior =
    Renderable.Private.make_behavior ~on_resize ?lifecycle_pass
      ~render_self
      ~mouse_event:(fun _ event ->
        match Renderable.mouse_kind event with
        | Renderable.Scroll when text_buffer_renderable.scrollable ->
            handle_scroll text_buffer_renderable event
        | _ -> ())
      ~selection_changed ~should_start_selection
      ~destroy_self:(fun _ -> close_resources text_buffer_renderable) ()
  in
  Renderable.Private.set_behavior text_buffer_renderable.renderable behavior

let ensure_alive text_buffer_renderable =
  if Renderable.is_destroyed text_buffer_renderable.renderable then
    Error Error.Destroyed
  else Ok ()

let set_wrap_width_for_dimensions text_buffer_renderable width =
  let width =
    match text_buffer_renderable.wrap_mode, width with
    | Text_buffer_view.No_wrap, _ | _, 0 -> None
    | _, width -> Some (Int32.of_int width)
  in
  Text_buffer_view.set_wrap_width text_buffer_renderable.text_buffer_view width

let create context ?id ?(width_method = Text_buffer.Wcwidth)
    ?(wrap_mode = Text_buffer_view.Word) ?(selectable = true)
    ?(scrollable = true) () =
  match Renderable.Private.create context ?id () with
  | Error error -> Error error
  | Ok renderable ->
      (match Text_buffer.create width_method with
      | Error error ->
          Renderable.destroy renderable;
          Error error
      | Ok text_buffer ->
          let default_syntax_style = Syntax_style.create () in
          (match
             Text_buffer.set_syntax_style text_buffer
               (Some default_syntax_style)
           with
          | Error error ->
              Syntax_style.destroy default_syntax_style;
              ignore (Text_buffer.close text_buffer);
              Renderable.destroy renderable;
              Error error
          | Ok () ->
              (match Text_buffer_view.create text_buffer with
              | Error error ->
                  ignore (Text_buffer.set_syntax_style text_buffer None);
                  Syntax_style.destroy default_syntax_style;
                  ignore (Text_buffer.close text_buffer);
                  Renderable.destroy renderable;
                  Error error
              | Ok text_buffer_view ->
                  (match
                     Text_buffer_view.set_wrap_mode text_buffer_view wrap_mode
                   with
                  | Error error ->
                      ignore (Text_buffer_view.close text_buffer_view);
                      ignore (Text_buffer.set_syntax_style text_buffer None);
                      Syntax_style.destroy default_syntax_style;
                      ignore (Text_buffer.close text_buffer);
                      Renderable.destroy renderable;
                      Error error
                  | Ok () ->
                      (match Native_measure.create () with
                      | Error error ->
                          ignore (Text_buffer_view.close text_buffer_view);
                          ignore (Text_buffer.set_syntax_style text_buffer None);
                          Syntax_style.destroy default_syntax_style;
                          ignore (Text_buffer.close text_buffer);
                          Renderable.destroy renderable;
                          Error error
                      | Ok native_measure ->
                          (match
                             Renderable.Private.with_yoga_node renderable
                               (fun node ->
                                 Native_measure.attach_yoga_node native_measure node)
                           with
                          | Error error ->
                              cleanup_creation renderable text_buffer
                                text_buffer_view native_measure
                                default_syntax_style;
                              Error error
                          | Ok () ->
                              (match
                                 Native_measure.set_measure_target native_measure
                                   text_buffer_view
                               with
                              | Error error ->
                                  cleanup_creation renderable text_buffer
                                    text_buffer_view native_measure
                                    default_syntax_style;
                                  Error error
                              | Ok () ->
                                  let text_buffer_renderable =
                                    {
                                      renderable;
                                      text_buffer;
                                      text_buffer_view;
                                      native_measure;
                                      default_syntax_style;
                                      wrap_mode;
                                      selectable;
                                      scrollable;
                                      scroll_x = 0;
                                      scroll_y = 0;
                                      last_local_selection = None;
                                      lifecycle_pass = None;
                                    }
                                  in
                                  install_behavior text_buffer_renderable;
                                  (match Render_context.width context with
                                  | Error error ->
                                      Renderable.destroy renderable;
                                      Error error
                                  | Ok width ->
                                      (match
                                         set_wrap_width_for_dimensions
                                           text_buffer_renderable (Int32.to_int width)
                                       with
                                      | Error error ->
                                          Renderable.destroy renderable;
                                          Error error
                                      | Ok () -> Ok text_buffer_renderable)))))))))

let as_renderable text_buffer_renderable = text_buffer_renderable.renderable
let text_buffer text_buffer_renderable = text_buffer_renderable.text_buffer

let text_buffer_view text_buffer_renderable =
  text_buffer_renderable.text_buffer_view

let set_text text_buffer_renderable text =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.set_text text_buffer_renderable.text_buffer text)
        (fun () -> mark_measure_dirty text_buffer_renderable))

let append text_buffer_renderable text =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.append text_buffer_renderable.text_buffer text)
        (fun () -> mark_measure_dirty text_buffer_renderable))

let clear text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.clear text_buffer_renderable.text_buffer)
        (fun () -> mark_measure_dirty text_buffer_renderable))

let set_styled_text text_buffer_renderable styled_text =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.set_styled_text text_buffer_renderable.text_buffer styled_text)
        (fun () -> mark_measure_dirty text_buffer_renderable))

let text text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer.text text_buffer_renderable.text_buffer)

let styled_text text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer.styled_text text_buffer_renderable.text_buffer)

let set_default_fg text_buffer_renderable value =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.set_default_fg text_buffer_renderable.text_buffer value)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let default_fg text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer.default_fg text_buffer_renderable.text_buffer)

let set_default_bg text_buffer_renderable value =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.set_default_bg text_buffer_renderable.text_buffer value)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let default_bg text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer.default_bg text_buffer_renderable.text_buffer)

let set_default_attributes text_buffer_renderable value =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.set_default_attributes text_buffer_renderable.text_buffer value)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let default_attributes text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer.default_attributes text_buffer_renderable.text_buffer)

let reset_defaults text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.reset_defaults text_buffer_renderable.text_buffer)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let set_syntax_style text_buffer_renderable value =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.set_syntax_style text_buffer_renderable.text_buffer value)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let syntax_style text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer.syntax_style text_buffer_renderable.text_buffer)

let set_tab_width text_buffer_renderable value =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer.set_tab_width text_buffer_renderable.text_buffer value)
        (fun () -> mark_measure_dirty text_buffer_renderable))

let tab_width text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer.tab_width text_buffer_renderable.text_buffer)

let set_selection text_buffer_renderable ~start ~end_ ?bg_color ?fg_color () =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.set_selection
           text_buffer_renderable.text_buffer_view ~start ~end_ ?bg_color
           ?fg_color ())
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let update_selection text_buffer_renderable ~end_ ?bg_color ?fg_color () =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.update_selection
           text_buffer_renderable.text_buffer_view ~end_ ?bg_color ?fg_color
           ())
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let reset_selection text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.reset_selection text_buffer_renderable.text_buffer_view)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let selected_text text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer_view.selected_text text_buffer_renderable.text_buffer_view)

let set_local_selection text_buffer_renderable ~anchor_x ~anchor_y ~focus_x
    ~focus_y ?bg_color ?fg_color () =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.set_local_selection
           text_buffer_renderable.text_buffer_view ~anchor_x ~anchor_y ~focus_x
           ~focus_y ?bg_color ?fg_color ())
        (fun changed ->
          ignore (Renderable.request_render text_buffer_renderable.renderable);
          Ok changed))

let update_local_selection text_buffer_renderable ~anchor_x ~anchor_y ~focus_x
    ~focus_y ?bg_color ?fg_color () =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.update_local_selection
           text_buffer_renderable.text_buffer_view ~anchor_x ~anchor_y ~focus_x
           ~focus_y ?bg_color ?fg_color ())
        (fun changed ->
          ignore (Renderable.request_render text_buffer_renderable.renderable);
          Ok changed))

let reset_local_selection text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.reset_local_selection
           text_buffer_renderable.text_buffer_view)
        (fun () ->
          ignore (Renderable.request_render text_buffer_renderable.renderable);
          Ok ()))

let set_tab_indicator text_buffer_renderable indicator =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.set_tab_indicator
           text_buffer_renderable.text_buffer_view indicator)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let set_tab_indicator_color text_buffer_renderable color =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.set_tab_indicator_color
           text_buffer_renderable.text_buffer_view color)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let set_truncate text_buffer_renderable value =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Result.bind
        (Text_buffer_view.set_truncate text_buffer_renderable.text_buffer_view value)
        (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let wrap_mode text_buffer_renderable = text_buffer_renderable.wrap_mode

let scroll_x text_buffer_renderable = text_buffer_renderable.scroll_x
let scroll_y text_buffer_renderable = text_buffer_renderable.scroll_y

let set_first_line_offset text_buffer_renderable offset =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      if offset < 0 then Error Error.Invalid_argument
      else
        Result.bind
          (Text_buffer_view.set_first_line_offset
             text_buffer_renderable.text_buffer_view (Int32.of_int offset))
          (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let set_viewport_size text_buffer_renderable ~width ~height =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      if width < 0 || height < 0 then Error Error.Invalid_argument
      else
        Result.bind
          (Text_buffer_view.set_viewport_size
             text_buffer_renderable.text_buffer_view ~width:(Int32.of_int width)
             ~height:(Int32.of_int height))
          (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let set_viewport text_buffer_renderable ~x ~y ~width ~height =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      if x < 0 || y < 0 || width < 0 || height < 0 then Error Error.Invalid_argument
      else
        Result.bind
          (update_native_viewport text_buffer_renderable ~x ~y ~width ~height)
          (fun () -> Renderable.request_render text_buffer_renderable.renderable))

let set_scroll text_buffer_renderable ~x ~y =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      match Text_buffer_view.viewport text_buffer_renderable.text_buffer_view with
      | Error error -> Error error
      | Ok (_, _, width, height) ->
          set_viewport text_buffer_renderable ~x ~y ~width:(Int32.to_int width)
            ~height:(Int32.to_int height))

let line_info text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer_view.logical_line_info text_buffer_renderable.text_buffer_view)

let logical_line_info text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer_view.logical_line_info text_buffer_renderable.text_buffer_view)

let virtual_line_count text_buffer_renderable =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer_view.virtual_line_count text_buffer_renderable.text_buffer_view)

let equal_wrap_mode left right =
  match left, right with
  | Text_buffer_view.No_wrap, Text_buffer_view.No_wrap
  | Text_buffer_view.Char, Text_buffer_view.Char
  | Text_buffer_view.Word, Text_buffer_view.Word -> true
  | Text_buffer_view.No_wrap, (Text_buffer_view.Char | Text_buffer_view.Word)
  | Text_buffer_view.Char, (Text_buffer_view.No_wrap | Text_buffer_view.Word)
  | Text_buffer_view.Word, (Text_buffer_view.No_wrap | Text_buffer_view.Char) ->
      false

let set_wrap_mode text_buffer_renderable wrap_mode =
  match ensure_alive text_buffer_renderable with
  | Error error -> Error error
  | Ok () when equal_wrap_mode text_buffer_renderable.wrap_mode wrap_mode ->
      Ok ()
  | Ok () ->
    let previous = text_buffer_renderable.wrap_mode in
    match
      Text_buffer_view.set_wrap_mode text_buffer_renderable.text_buffer_view
        wrap_mode
    with
    | Error error -> Error error
    | Ok () ->
        text_buffer_renderable.wrap_mode <- wrap_mode;
        (match
           set_wrap_width_for_dimensions text_buffer_renderable
             (max 0
                (int_of_float
                   (Float.floor
                      (Renderable.width text_buffer_renderable.renderable))))
         with
        | Error error ->
            text_buffer_renderable.wrap_mode <- previous;
            ignore
              (Text_buffer_view.set_wrap_mode
                 text_buffer_renderable.text_buffer_view previous);
            Error error
        | Ok () -> mark_measure_dirty text_buffer_renderable)

let measure_for_dimensions text_buffer_renderable ~width ~height =
  Result.bind (ensure_alive text_buffer_renderable) (fun () ->
      Text_buffer_view.measure_for_dimensions
        text_buffer_renderable.text_buffer_view ~width ~height)

let destroy text_buffer_renderable =
  Renderable.destroy text_buffer_renderable.renderable

module Private = struct
  let set_lifecycle_pass text_buffer_renderable lifecycle_pass =
    text_buffer_renderable.lifecycle_pass <- lifecycle_pass;
    install_behavior text_buffer_renderable
end
