type t = {
  frame : Frame_buffer.t;
  renderable : Renderable.t;
  buffer : Owned_buffer.t;
  mutable text : string;
  mutable font : Ascii_font_spec.name;
  mutable colors : Color.t list;
  mutable background_color : Color.t;
  mutable selection_bg : Color.t option;
  mutable selection_fg : Color.t option;
  mutable selectable : bool;
  mutable local_selection : Lib.Selection.local_bounds option;
  mutable selection : (int * int) option;
  mutable destroyed : bool;
}

let ensure_alive font =
  if font.destroyed then Error Error.Destroyed else Ok ()

let codepoint_slice text start_index end_index =
  let points = Lib.Text_metrics.scan Lib.Text_metrics.Unicode text in
  let count = Array.length points in
  let start_index = max 0 (min start_index count) in
  let end_index = max start_index (min end_index count) in
  if Int.equal start_index end_index then ""
  else
    let start_byte = points.(start_index).byte_start in
    let end_byte =
      if Int.equal end_index count then String.length text
      else points.(end_index).byte_start
    in
    String.sub text start_byte (end_byte - start_byte)

let selection_for_bounds font bounds =
  let height = (Ascii_font_spec.definition font.font).lines in
  let text_length =
    Array.length (Lib.Text_metrics.scan Lib.Text_metrics.Unicode font.text)
  in
  let start_y = int_of_float (Float.floor bounds.Lib.Selection.anchor_y) in
  let end_y = int_of_float (Float.floor bounds.Lib.Selection.focus_y) in
  if height - 1 < start_y || end_y < 0 || start_y > height - 1 then None
  else
    let start_index =
      if start_y >= 0 && start_y <= height - 1 && bounds.anchor_x > 0.0 then
        Ascii_font_spec.coordinate_to_character_index
          ~font:font.font
          (int_of_float (Float.floor bounds.anchor_x)) font.text
      else 0
    in
    let end_index =
      if end_y >= 0 && end_y <= height - 1 then
        if bounds.focus_x >= 0.0 then
          Ascii_font_spec.coordinate_to_character_index
            ~font:font.font
            (int_of_float (Float.floor bounds.focus_x)) font.text
        else 0
      else text_length
    in
    if start_index < end_index && start_index >= 0 && end_index <= text_length
    then Some (start_index, end_index)
    else None

let update_selection font bounds =
  font.local_selection <- bounds;
  font.selection <- Option.bind bounds (selection_for_bounds font)

let render_selection font (start_index, end_index) =
  match font.selection_bg, font.selection_fg with
  | None, None -> Ok ()
  | _ ->
      let positions =
        Ascii_font_spec.character_positions ~font:font.font font.text
      in
      if start_index >= Array.length positions || end_index >= Array.length positions
      then Ok ()
      else
        let start_x = positions.(start_index) in
        let end_x = positions.(end_index) in
        let selected_text = codepoint_slice font.text start_index end_index in
        let background = Option.value font.selection_bg ~default:font.background_color in
        let selected_color =
          match font.selection_fg, font.colors with
          | Some color, _ -> color
          | None, color :: _ -> color
          | None, [] -> Color.white
        in
        let selected_colors = [ selected_color ] in
        let fill_result =
          match font.selection_bg with
          | None -> Ok ()
          | Some color ->
              Owned_buffer.fill_rect font.buffer ~x:start_x ~y:0
                ~width:(max 0 (end_x - start_x))
                ~height:(Ascii_font_spec.definition font.font).lines
                ~background:color
        in
        Result.bind fill_result (fun () ->
            if Int.equal (String.length selected_text) 0 then Ok ()
            else
              Result.map
                (fun _ -> ())
                (Ascii_font_spec.render_to_frame_buffer font.buffer
                   ~text:selected_text ~x:start_x ~y:0 ~colors:selected_colors
                   ~background_color:background ~font:font.font ()))

let rasterize font =
  Result.bind
    (Owned_buffer.clear font.buffer ~background:font.background_color)
    (fun () ->
      Result.bind
        (Ascii_font_spec.render_to_frame_buffer font.buffer ~text:font.text
           ~colors:font.colors ~background_color:font.background_color
           ~font:font.font ())
        (fun _ ->
          match font.selection with
          | None -> Ok ()
          | Some selection -> render_selection font selection))

let render_self font renderable buffer _delta_time =
  Buffer.draw_frame_buffer buffer ~source:font.buffer
    ~x:(Int32.of_float (Float.floor (Renderable.screen_x renderable)))
    ~y:(Int32.of_float (Float.floor (Renderable.screen_y renderable))) ()

let on_resize font ~width ~height =
  if width > 0 && height > 0 then begin
    ignore (Owned_buffer.resize font.buffer ~width ~height);
    ignore (rasterize font);
  end

let selected_text_for_selection font =
  match font.selection with
  | None -> Ok ""
  | Some (start_index, end_index) -> Ok (codepoint_slice font.text start_index end_index)

let create context ?id ?(text = "") ?(font = Ascii_font_spec.Tiny)
    ?(colors = [ Color.white ]) ?(background_color = Color.transparent)
    ?selection_bg ?selection_fg ?(selectable = true) () =
  let measurement = Ascii_font_spec.measure_text ~font text in
  let width = max 1 measurement.width in
  let height = max 1 measurement.height in
  Result.bind
    (Frame_buffer.create context ?id ~width ~height ~respect_alpha:true ())
    (fun frame ->
      let renderable = Frame_buffer.as_renderable frame in
      let value =
        {
          frame;
          renderable;
          buffer = Frame_buffer.frame_buffer frame;
          text;
          font;
          colors = (if List.is_empty colors then [ Color.white ] else colors);
          background_color;
          selection_bg;
          selection_fg;
          selectable;
          local_selection = None;
          selection = None;
          destroyed = false;
        }
      in
      let behavior =
        Renderable.Private.make_behavior
          ~render_self:(render_self value)
          ~on_resize:(fun _renderable ~width ~height ->
            on_resize value ~width ~height)
          ~should_start_selection:(fun _renderable ~x ~y ->
            if not value.selectable then false
            else
              let local_x =
                float_of_int x -. Renderable.screen_x value.renderable
              in
              let local_y =
                float_of_int y -. Renderable.screen_y value.renderable
              in
              local_x >= 0.0
              && local_y >= 0.0
              && local_x < Renderable.width value.renderable
              && local_y < Renderable.height value.renderable)
          ~selection_changed:(fun _renderable selection ->
            let bounds =
              Lib.Selection.convert_global_to_local selection
                ~local_x:(Renderable.screen_x value.renderable)
                ~local_y:(Renderable.screen_y value.renderable)
            in
            update_selection value bounds;
            ignore (rasterize value);
            ignore (Renderable.request_render value.renderable))
          ~selected_text:(fun _renderable -> selected_text_for_selection value)
          ~destroy_self:(fun _renderable ->
            if not value.destroyed then begin
              value.destroyed <- true;
              Owned_buffer.close value.buffer
            end)
          ()
      in
      Renderable.Private.set_behavior renderable behavior;
      let setup_result =
        Result.bind (Renderable.set_flex_shrink renderable (Some 0.0)) (fun () ->
            rasterize value)
      in
      match setup_result with
      | Ok () -> Ok value
      | Error error ->
          Renderable.destroy renderable;
          Error error)

let as_renderable font = font.renderable
let frame_buffer font = font.buffer
let text font = font.text

let update_dimensions font new_text new_font =
  let measurement = Ascii_font_spec.measure_text ~font:new_font new_text in
  Frame_buffer.resize font.frame ~width:(max 1 measurement.width)
    ~height:(max 1 measurement.height)

let set_text font value =
  Result.bind (ensure_alive font) (fun () ->
      let previous = font.text in
      font.text <- value;
      (match update_dimensions font value font.font with
      | Error error ->
          font.text <- previous;
          Error error
      | Ok () ->
          update_selection font font.local_selection;
          Result.bind (rasterize font) (fun () ->
              ignore (Renderable.request_render font.renderable);
              Ok ())))

let font font = font.font

let set_font value new_font =
  Result.bind (ensure_alive value) (fun () ->
      let previous = value.font in
      value.font <- new_font;
      match update_dimensions value value.text new_font with
      | Error error ->
          value.font <- previous;
          Error error
      | Ok () ->
          update_selection value value.local_selection;
          Result.bind (rasterize value) (fun () ->
              ignore (Renderable.request_render value.renderable);
              Ok ()))

let colors font = font.colors

let set_colors font value =
  Result.bind (ensure_alive font) (fun () ->
      font.colors <- (if List.is_empty value then [ Color.white ] else value);
      Result.bind (rasterize font) (fun () ->
          ignore (Renderable.request_render font.renderable);
          Ok ()))

let background_color font = font.background_color

let set_background_color font value =
  Result.bind (ensure_alive font) (fun () ->
      font.background_color <- value;
      Result.bind (rasterize font) (fun () ->
          ignore (Renderable.request_render font.renderable);
          Ok ()))

let selection_bg font = font.selection_bg

let set_selection_bg font value =
  Result.bind (ensure_alive font) (fun () ->
      font.selection_bg <- value;
      Result.bind (rasterize font) (fun () ->
          ignore (Renderable.request_render font.renderable);
          Ok ()))

let selection_fg font = font.selection_fg

let set_selection_fg font value =
  Result.bind (ensure_alive font) (fun () ->
      font.selection_fg <- value;
      Result.bind (rasterize font) (fun () ->
          ignore (Renderable.request_render font.renderable);
          Ok ()))

let selectable font = font.selectable

let set_selectable font value =
  Result.bind (ensure_alive font) (fun () ->
      font.selectable <- value;
      Ok ())

let selected_text font =
  match selected_text_for_selection font with
  | Ok value -> value
  | Error _ -> ""

let has_selection font = Option.is_some font.selection
let destroy font = Renderable.destroy font.renderable
