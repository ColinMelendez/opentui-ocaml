type line_sign = {
  before : string option;
  before_color : Color.t option;
  after : string option;
  after_color : Color.t option;
}

type line_color =
  | Color of Color.t
  | Config of { gutter : Color.t option; content : Color.t option }

type target = {
  renderable : Renderable.t;
  line_info : unit -> (Line_info.t, Error.t) result;
  virtual_line_count : unit -> int;
  scroll_y : unit -> int;
}

type gutter_state = {
  renderable : Renderable.t;
  owner : t;
  target : target;
  mutable destroyed : bool;
}

and t = {
  renderable : Renderable.t;
  mutable target : target option;
  mutable gutter : gutter_state option;
  mutable fg : Color.t;
  mutable bg : Color.t;
  mutable min_width : int;
  mutable padding_right : int;
  mutable line_color_specs : (int * line_color) list;
  mutable line_colors_gutter : (int * Color.t) list;
  mutable line_colors_content : (int * Color.t) list;
  mutable line_signs : (int * line_sign) list;
  mutable line_number_offset : int;
  mutable hide_line_numbers : int list;
  mutable line_numbers : (int * int) list;
  mutable show_line_numbers : bool;
  mutable last_line_count : int;
  mutable destroyed : bool;
}

let target_of_text_buffer_renderable value =
  {
    renderable = Text_buffer_renderable.as_renderable value;
    line_info = (fun () ->
      Result.map Line_info.of_text_buffer_view
        (Text_buffer_renderable.line_info value));
    virtual_line_count = (fun () ->
      match Text_buffer_renderable.virtual_line_count value with
      | Ok count -> count
      | Error _ -> 0);
    scroll_y = (fun () ->
      match Text_buffer_view.viewport (Text_buffer_renderable.text_buffer_view value) with
      | Ok (_, y, _, _) -> Int32.to_int y
      | Error _ -> 0);
  }

let target_of_code value =
  {
    renderable = Code.as_renderable value;
    line_info = (fun () ->
      Result.map Line_info.of_text_buffer_view (Code.line_info value));
    virtual_line_count = (fun () ->
      match Code.virtual_line_count value with Ok count -> count | Error _ -> 0);
    scroll_y = (fun () -> Code.scroll_y value);
  }

let target_of_edit_buffer_renderable value =
  {
    renderable = Edit_buffer_renderable.as_renderable value;
    line_info = (fun () -> Ok (Line_info.of_editor_view (Edit_buffer_renderable.line_info value)));
    virtual_line_count = (fun () -> Edit_buffer_renderable.virtual_line_count value);
    scroll_y = (fun () -> Edit_buffer_renderable.scroll_y value);
  }

let target_of_textarea value =
  {
    renderable = Textarea.as_renderable value;
    line_info = (fun () -> Ok (Line_info.of_editor_view (Textarea.line_info value)));
    virtual_line_count = (fun () -> Textarea.virtual_line_count value);
    scroll_y = (fun () -> Textarea.scroll_y value);
  }

let ensure_alive (value : t) =
  if value.destroyed || Renderable.is_destroyed value.renderable then
    Error Error.Destroyed
  else Ok ()

let lookup key values =
  match List.find_opt (fun (candidate, _) -> Int.equal candidate key) values with
  | None -> None
  | Some (_, value) -> Some value

let replace key value values =
  (key, value)
  :: List.filter (fun (candidate, _) -> not (Int.equal candidate key)) values

let remove key values =
  List.filter (fun (candidate, _) -> not (Int.equal candidate key)) values

let int_mem value values =
  List.exists (fun candidate -> Int.equal candidate value) values

let same_color left right =
  let left_red, left_green, left_blue, left_alpha = Color.channels left in
  let right_red, right_green, right_blue, right_alpha = Color.channels right in
  Int.equal left_red right_red && Int.equal left_green right_green
  && Int.equal left_blue right_blue && Int.equal left_alpha right_alpha

let darken color =
  let red, green, blue, alpha = Color.channels color in
  match
    Color.rgba ~red:(red * 4 / 5) ~green:(green * 4 / 5)
      ~blue:(blue * 4 / 5) ~alpha
  with
  | Ok color -> color
  | Error _ -> color

let sign_width text =
  Lib.Text_metrics.display_width Lib.Text_metrics.Wcwidth text

let maximum_sign_width (state : t) before =
  List.fold_left
    (fun maximum (_, sign) ->
      let text = if before then sign.before else sign.after in
      match text with
      | None -> maximum
      | Some text -> max maximum (sign_width text))
    0 state.line_signs

let number_width (state : t) =
  let line_count =
    match state.target with
    | None -> 0
    | Some target -> max 0 (target.virtual_line_count ())
  in
  let maximum =
    List.fold_left
      (fun value (_, number) -> max value number)
      (line_count + state.line_number_offset) state.line_numbers
  in
  String.length (string_of_int (max 0 maximum))

let gutter_width (state : t) =
  let before = maximum_sign_width state true in
  let after = maximum_sign_width state false in
  max state.min_width (number_width state + state.padding_right + 1)
  + before + after

let line_color state line content =
  lookup line
    (if content then state.line_colors_content else state.line_colors_gutter)

let apply_line_color state line color =
  match color with
  | Color color ->
      state.line_colors_gutter <- replace line color state.line_colors_gutter;
      state.line_colors_content <-
        replace line (darken color) state.line_colors_content
  | Config { gutter; content } ->
      state.line_colors_gutter <- remove line state.line_colors_gutter;
      state.line_colors_content <- remove line state.line_colors_content;
      (match gutter with
      | None -> ()
      | Some color ->
          state.line_colors_gutter <-
            replace line color state.line_colors_gutter;
          (match content with
          | Some _ -> ()
          | None ->
              state.line_colors_content <-
                replace line (darken color) state.line_colors_content));
      (match content with
      | None -> ()
      | Some color ->
          state.line_colors_content <-
            replace line color state.line_colors_content)

let draw_text buffer text x y foreground background =
  if String.length text > 0 then
    ignore
      (Buffer.draw_text buffer ~text ~x:(Int32.of_int x) ~y:(Int32.of_int y)
         ~foreground ~background ~attributes:0l)

let render_gutter state _renderable buffer _delta_time =
  let x = int_of_float (Float.floor (Renderable.screen_x state.renderable)) in
  let y = int_of_float (Float.floor (Renderable.screen_y state.renderable)) in
  let width = max 0 (int_of_float (Float.floor (Renderable.width state.renderable))) in
  let height = max 0 (int_of_float (Float.floor (Renderable.height state.renderable))) in
  let fill_color = state.owner.bg in
  if width > 0 && height > 0 then
    ignore
      (Buffer.fill_rect buffer ~x:(Int32.of_int x) ~y:(Int32.of_int y)
         ~width:(Int32.of_int width) ~height:(Int32.of_int height)
         ~background:fill_color);
  match state.target.line_info () with
  | Error _ -> Ok ()
  | Ok info ->
      let start_line = max 0 (state.target.scroll_y ()) in
      let before_width = maximum_sign_width state.owner true in
      let after_width = maximum_sign_width state.owner false in
      let last_source = ref (if start_line > 0 then
          if start_line - 1 < Array.length info.line_sources then info.line_sources.(start_line - 1) else -1
        else -1) in
      for row = 0 to height - 1 do
        let visual_line = start_line + row in
        if visual_line < Array.length info.line_sources then begin
          let logical_line = info.line_sources.(visual_line) in
          let background =
            Option.value (line_color state.owner logical_line false) ~default:state.owner.bg
          in
          if not (same_color background fill_color) then
            ignore
              (Buffer.fill_rect buffer ~x:(Int32.of_int x)
                 ~y:(Int32.of_int (y + row)) ~width:(Int32.of_int width)
                 ~height:1l ~background);
          if not (Int.equal logical_line !last_source) then begin
            let sign = lookup logical_line state.owner.line_signs in
            let current_x = ref x in
            (match sign with
            | Some sign ->
                (match sign.before with
                | None -> current_x := !current_x + before_width
                | Some text ->
                    current_x := !current_x + (before_width - sign_width text);
                    draw_text buffer text !current_x (y + row)
                      (Option.value sign.before_color ~default:state.owner.fg)
                      background;
                    current_x := !current_x + sign_width text)
            | None -> current_x := !current_x + before_width);
            let custom_number = lookup logical_line state.owner.line_numbers in
            let number =
              Option.value custom_number
                ~default:(logical_line + 1 + state.owner.line_number_offset)
            in
            if not (int_mem logical_line state.owner.hide_line_numbers) then begin
              let text = string_of_int number in
              let end_x = x + width - after_width - state.owner.padding_right in
              draw_text buffer text (end_x - String.length text) (y + row)
                state.owner.fg background
            end;
            (match sign with
            | Some sign ->
                (match sign.after with
                | None -> ()
                | Some text ->
                    let after_x = x + width - state.owner.padding_right - after_width in
                    draw_text buffer text after_x (y + row)
                      (Option.value sign.after_color ~default:state.owner.fg)
                      background)
            | None -> ())
          end;
          last_source := logical_line
        end
      done;
      Ok ()

let render_content_background (state : t) _renderable buffer _delta_time =
  match state.target with
  | None -> Ok ()
  | Some target ->
      (match target.line_info () with
      | Error _ -> Ok ()
      | Ok info ->
          let gutter_width =
            match state.gutter with
            | None -> 0
            | Some gutter when Renderable.visible gutter.renderable ->
                int_of_float (Float.floor (Renderable.width gutter.renderable))
            | Some _ -> 0
          in
          let x = int_of_float (Float.floor (Renderable.screen_x state.renderable)) + gutter_width in
          let y = int_of_float (Float.floor (Renderable.screen_y state.renderable)) in
          let width =
            max 0
              (int_of_float (Float.floor (Renderable.width state.renderable))
              - gutter_width)
          in
          let height = max 0 (int_of_float (Float.floor (Renderable.height state.renderable))) in
          let start_line = max 0 (target.scroll_y ()) in
          for row = 0 to height - 1 do
            let visual_line = start_line + row in
            if visual_line < Array.length info.line_sources then
              match line_color state info.line_sources.(visual_line) true with
              | None -> ()
              | Some color ->
                  ignore
                    (Buffer.fill_rect buffer ~x:(Int32.of_int x)
                       ~y:(Int32.of_int (y + row)) ~width:(Int32.of_int width)
                       ~height:1l ~background:color)
          done;
          Ok ())

let configure_gutter (state : gutter_state) =
  let callback ~width:_ ~width_mode:_ ~height:_ ~height_mode:_ =
    float_of_int (gutter_width state.owner),
    float_of_int (state.target.virtual_line_count ())
  in
  Result.bind
    (Renderable.Private.set_measure_func state.renderable callback)
    (fun () -> Renderable.set_flex_shrink state.renderable (Some 0.0))

let make_gutter (owner : t) target =
  match Renderable.Private.create (Renderable.context owner.renderable) () with
  | Error error -> Error error
  | Ok renderable ->
      let state = { renderable; owner; target; destroyed = false } in
      let behavior =
        Renderable.Private.make_behavior
          ~render_self:(render_gutter state)
          ~destroy_self:(fun _ ->
            if not state.destroyed then begin
              state.destroyed <- true;
              ignore (Renderable.Private.clear_measure_func state.renderable)
            end)
          ()
      in
      Renderable.Private.set_behavior renderable behavior;
      (match configure_gutter state with
      | Ok () -> Ok state
      | Error error -> Renderable.destroy renderable; Error error)

let install_target state target =
  match make_gutter state target with
  | Error error -> Error error
  | Ok gutter ->
      let attach_gutter =
        Renderable.Private.attach ~parent:state.renderable
          ~child:gutter.renderable ~index:0
      in
      (match attach_gutter with
      | Error error -> Renderable.destroy gutter.renderable; Error error
      | Ok _ ->
          (match
             Renderable.Private.attach ~parent:state.renderable
               ~child:target.renderable ~index:1
           with
          | Error error ->
              ignore (Renderable.Private.detach ~parent:state.renderable
                        ~child:gutter.renderable);
              Renderable.destroy gutter.renderable;
              Error error
          | Ok _ ->
              state.target <- Some target;
              state.gutter <- Some gutter;
              state.last_line_count <- target.virtual_line_count ();
              ignore (Renderable.set_visible gutter.renderable state.show_line_numbers);
              ignore (Renderable.request_render state.renderable);
              Ok ()))

let remove_target (state : t) =
  Option.iter
    (fun (target : target) ->
      ignore
        (Renderable.Private.detach ~parent:state.renderable
           ~child:target.renderable))
    state.target;
  Option.iter
    (fun (gutter : gutter_state) ->
      ignore (Renderable.Private.detach ~parent:state.renderable ~child:gutter.renderable);
      Renderable.destroy gutter.renderable)
    state.gutter;
  state.target <- None;
  state.gutter <- None;
  state.last_line_count <- 0

let create context ?id ?target
    ?(fg =
      match Color.rgba ~red:136 ~green:136 ~blue:136 ~alpha:255 with
      | Ok color -> color
      | Error _ -> Color.white)
    ?(bg = Color.transparent)
    ?(min_width = 3) ?(padding_right = 1) ?(line_colors = [])
    ?(line_signs = []) ?(line_number_offset = 0) ?(hide_line_numbers = [])
    ?(line_numbers = []) ?(show_line_numbers = true) () =
  if min_width < 0 || padding_right < 0 then Error Error.Invalid_argument
  else
    Result.bind (Renderable.Private.create context ?id ()) (fun renderable ->
        let state =
          {
            renderable;
            target = None;
            gutter = None;
            fg;
            bg;
            min_width;
            padding_right;
            line_color_specs = line_colors;
            line_colors_gutter = [];
            line_colors_content = [];
            line_signs;
            line_number_offset;
            hide_line_numbers;
            line_numbers;
            show_line_numbers;
            last_line_count = 0;
            destroyed = false;
          }
        in
        List.iter (fun (line, color) -> apply_line_color state line color)
          line_colors;
        let behavior =
          Renderable.Private.make_behavior
            ~render_self:(render_content_background state)
            ~lifecycle_pass:(fun _ ->
              match state.target with
              | None -> ()
              | Some target ->
                  let count = target.virtual_line_count () in
                  if not (Int.equal count state.last_line_count) then begin
                    state.last_line_count <- count;
                    Option.iter
                      (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
                      state.gutter;
                    ignore (Renderable.request_render state.renderable)
                  end)
            ~destroy_self:(fun _ ->
              state.destroyed <- true;
              remove_target state)
            ()
        in
        Renderable.Private.set_behavior renderable behavior;
        let result =
          Result.bind
            (Renderable.set_flex_direction renderable Yoga.Flex_row)
            (fun () -> Renderable.set_height renderable Yoga.Auto)
        in
        match result with
        | Error error -> Renderable.destroy renderable; Error error
        | Ok () ->
            (match target with
            | None -> Ok state
            | Some target ->
                (match install_target state target with
                | Ok () -> Ok state
                | Error error -> Renderable.destroy renderable; Error error)))

let as_renderable (value : t) = value.renderable
let target (value : t) = value.target
let gutter (value : t) = Option.map (fun value -> value.renderable) value.gutter

let set_target (value : t) next =
  Result.bind (ensure_alive value) (fun () ->
      remove_target value;
      match next with
      | None -> Ok ()
      | Some target -> install_target value target)

let clear_target (value : t) = set_target value None

let show_line_numbers value = value.show_line_numbers

let set_show_line_numbers value next =
  Result.bind (ensure_alive value) (fun () ->
      value.show_line_numbers <- next;
      Option.iter
        (fun gutter -> ignore (Renderable.set_visible gutter.renderable next))
        value.gutter;
      Renderable.request_render value.renderable)

let fg value = value.fg
let set_fg value color =
  Result.bind (ensure_alive value) (fun () ->
      value.fg <- color;
      Renderable.request_render value.renderable)

let bg value = value.bg
let set_bg value color =
  Result.bind (ensure_alive value) (fun () ->
      value.bg <- color;
      Renderable.request_render value.renderable)

let set_line_color value line color =
  Result.bind (ensure_alive value) (fun () ->
      value.line_color_specs <- replace line color value.line_color_specs;
      apply_line_color value line color;
      Renderable.request_render value.renderable)

let clear_line_color value line =
  Result.bind (ensure_alive value) (fun () ->
      value.line_color_specs <- remove line value.line_color_specs;
      value.line_colors_gutter <- remove line value.line_colors_gutter;
      value.line_colors_content <- remove line value.line_colors_content;
      Renderable.request_render value.renderable)

let clear_all_line_colors value =
  Result.bind (ensure_alive value) (fun () ->
      value.line_color_specs <- [];
      value.line_colors_gutter <- [];
      value.line_colors_content <- [];
      Renderable.request_render value.renderable)

let line_colors value = value.line_color_specs

let set_line_colors value colors =
  Result.bind (ensure_alive value) (fun () ->
      value.line_color_specs <- colors;
      value.line_colors_gutter <- [];
      value.line_colors_content <- [];
      List.iter (fun (line, color) -> apply_line_color value line color) colors;
      Renderable.request_render value.renderable)

let set_line_sign value line sign =
  Result.bind (ensure_alive value) (fun () ->
      value.line_signs <- replace line sign value.line_signs;
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let line_signs value = value.line_signs

let set_line_signs value signs =
  Result.bind (ensure_alive value) (fun () ->
      value.line_signs <- signs;
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let clear_line_sign value line =
  Result.bind (ensure_alive value) (fun () ->
      value.line_signs <- remove line value.line_signs;
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let clear_all_line_signs value =
  Result.bind (ensure_alive value) (fun () ->
      value.line_signs <- [];
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let set_line_number value line number =
  Result.bind (ensure_alive value) (fun () ->
      value.line_numbers <- replace line number value.line_numbers;
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let line_numbers value = value.line_numbers

let set_line_numbers value numbers =
  Result.bind (ensure_alive value) (fun () ->
      value.line_numbers <- numbers;
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let clear_line_number value line =
  Result.bind (ensure_alive value) (fun () ->
      value.line_numbers <- remove line value.line_numbers;
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let set_line_number_offset value offset =
  Result.bind (ensure_alive value) (fun () ->
      value.line_number_offset <- offset;
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let line_number_offset value = value.line_number_offset

let set_hide_line_numbers value lines =
  Result.bind (ensure_alive value) (fun () ->
      value.hide_line_numbers <- lines;
      Renderable.request_render value.renderable)

let hide_line_numbers value = value.hide_line_numbers

let remeasure value =
  Result.bind (ensure_alive value) (fun () ->
      Option.iter
        (fun gutter -> ignore (Renderable.Private.mark_yoga_dirty gutter.renderable))
        value.gutter;
      Renderable.request_render value.renderable)

let highlight_lines value ~start_line ~end_line color =
  Result.bind (ensure_alive value) (fun () ->
      if end_line < start_line then Ok ()
      else begin
        for line = start_line to end_line do
          value.line_color_specs <- replace line color value.line_color_specs;
          apply_line_color value line color
        done;
        Renderable.request_render value.renderable
      end)

let clear_highlight_lines value ~start_line ~end_line =
  Result.bind (ensure_alive value) (fun () ->
      if end_line < start_line then Ok ()
      else begin
        for line = start_line to end_line do
          value.line_color_specs <- remove line value.line_color_specs;
          value.line_colors_gutter <- remove line value.line_colors_gutter;
          value.line_colors_content <- remove line value.line_colors_content
        done;
        Renderable.request_render value.renderable
      end)

let destroy (value : t) = Renderable.destroy_recursively value.renderable
