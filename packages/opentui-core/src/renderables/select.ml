type option_item = {
  name : string;
  description : string;
  value : string option;
}

type action = Move_up | Move_down | Move_up_fast | Move_down_fast | Select_current
type key_binding = action Lib.Keybinding.binding
type selection_change = { index : int; option : option_item option }

type t = {
  renderable : Renderable.t;
  mutable options : option_item list;
  mutable selected_index : int;
  mutable scroll_offset : int;
  mutable show_scroll_indicator : bool;
  mutable wrap_selection : bool;
  mutable show_description : bool;
  mutable show_selection_indicator : bool;
  mutable item_spacing : int;
  mutable fast_scroll_step : int;
  mutable background_color : Color.t;
  mutable text_color : Color.t;
  mutable focused_background_color : Color.t;
  mutable focused_text_color : Color.t;
  mutable selected_background_color : Color.t;
  mutable selected_text_color : Color.t;
  mutable description_color : Color.t;
  mutable selected_description_color : Color.t;
  mutable font : Ascii_font_spec.name option;
  keymap : action Lib.Keybinding.t;
  selection_events : selection_change Event_kernel.t;
  item_events : selection_change Event_kernel.t;
  mutable destroyed : bool;
}

let color_or fallback result =
  match result with Ok value -> value | Error _ -> fallback

let selected_background_default =
  color_or Color.black (Color.rgba ~red:51 ~green:68 ~blue:85 ~alpha:255)

let selected_text_default =
  color_or Color.white (Color.rgba ~red:255 ~green:255 ~blue:0 ~alpha:255)

let description_default =
  color_or Color.white (Color.rgba ~red:136 ~green:136 ~blue:136 ~alpha:255)

let selected_description_default =
  color_or Color.white (Color.rgba ~red:204 ~green:204 ~blue:204 ~alpha:255)

let focused_background_default =
  color_or Color.black (Color.rgba ~red:26 ~green:26 ~blue:26 ~alpha:255)

let ensure_alive select =
  if select.destroyed || Renderable.is_destroyed select.renderable then
    Error Error.Destroyed
  else Ok ()

let selected_option select =
  if select.selected_index < 0 then None
  else List.nth_opt select.options select.selected_index

let change select = { index = select.selected_index; option = selected_option select }

let lines_per_item select =
  (match select.font with
  | None -> if select.show_description then 2 else 1
  | Some font ->
      (Ascii_font_spec.definition font).lines
      + if select.show_description then 1 else 0)
  + select.item_spacing

let max_visible_items select =
  let line_height = max 1 (lines_per_item select) in
  max 1
    (int_of_float (Float.floor (Renderable.height select.renderable)) / line_height)

let update_scroll_offset select =
  let maximum = max 0 (List.length select.options - max_visible_items select) in
  let half_visible = max_visible_items select / 2 in
  select.scroll_offset <-
    max 0 (min maximum (select.selected_index - half_visible))

let request select = ignore (Renderable.request_render select.renderable)

let emit_selection select =
  ignore (Event_kernel.emit select.selection_events (change select));
  request select

let set_selected_index_internal select index ~emit =
  let length = List.length select.options in
  let next =
    if Int.equal length 0 then 0 else max 0 (min (length - 1) index)
  in
  let changed = not (Int.equal next select.selected_index) in
  select.selected_index <- next;
  update_scroll_offset select;
  if changed && emit then emit_selection select;
  changed

let fill buffer ~x ~y ~width ~height ~foreground ~background =
  if width > 0 && height > 0 then
    for row = y to y + height - 1 do
      for column = x to x + width - 1 do
        ignore
          (Buffer.set_cell buffer ~x:(Int32.of_int column)
             ~y:(Int32.of_int row) ~character:32l ~foreground ~background
             ~attributes:0l)
      done
    done

let draw_text buffer ~text ~x ~y ~foreground ~background =
  ignore
    (Buffer.draw_text buffer ~text ~x:(Int32.of_int x) ~y:(Int32.of_int y)
       ~foreground ~background ~attributes:0l)

let draw_font select buffer ~text ~x ~y ~foreground ~background =
  match select.font with
  | None -> ()
  | Some font ->
      ignore
        (Ascii_font_spec.render_to_buffer buffer ~text ~x ~y
           ~colors:[ foreground ] ~background_color:background ~font ())

let truncate text width =
  if width <= 0 then ""
  else if String.length text <= width then text
  else if Int.equal width 1 then "…"
  else String.sub text 0 (width - 1) ^ "…"

let render_scroll_indicator select buffer ~x ~y ~width ~height ~background =
  let visible = max_visible_items select in
  let option_count = List.length select.options in
  if select.show_scroll_indicator && option_count > visible && width > 0 then begin
    let denominator = max 1 (option_count - visible) in
    let track_height = max 1 (height - 2) in
    let indicator_y =
      y + 1
        + int_of_float
            (Float.floor
               (float_of_int select.scroll_offset
               *. float_of_int track_height /. float_of_int denominator))
    in
    draw_text buffer ~text:"█" ~x:(x + width - 1) ~y:indicator_y
      ~foreground:description_default ~background
  end

let render_self select renderable buffer _delta_time =
  let x = int_of_float (Float.floor (Renderable.screen_x renderable)) in
  let y = int_of_float (Float.floor (Renderable.screen_y renderable)) in
  let width = max 0 (int_of_float (Float.floor (Renderable.width renderable))) in
  let height = max 0 (int_of_float (Float.floor (Renderable.height renderable))) in
  let background =
    if Renderable.focused renderable then select.focused_background_color
    else select.background_color
  in
  fill buffer ~x ~y ~width ~height ~foreground:background ~background;
  let visible = max_visible_items select in
  let item_height = max 1 (lines_per_item select) in
  let visible_options =
    select.options
    |> List.mapi (fun index option -> index, option)
    |> List.filter (fun (index, _) ->
           index >= select.scroll_offset
           && index < select.scroll_offset + visible)
  in
  List.iter
    (fun (index, option) ->
      let offset = index - select.scroll_offset in
      let item_y = y + (offset * item_height) in
      if item_y < y + height then begin
        let selected = Int.equal index select.selected_index in
        let content_height =
          min (height - (item_y - y))
            (max 1 (item_height - select.item_spacing))
        in
        if selected then
          fill buffer ~x ~y:item_y ~width ~height:content_height
            ~foreground:select.selected_background_color
            ~background:select.selected_background_color;
        let indicator =
          if select.show_selection_indicator then
            if selected then "▶ " else "  "
          else ""
        in
        let indicator_width = if select.show_selection_indicator then 2 else 0 in
        let foreground =
          if selected then select.selected_text_color
          else if Renderable.focused renderable then select.focused_text_color
          else select.text_color
        in
        let item_background =
          if selected then select.selected_background_color else background
        in
        (match select.font with
        | None ->
            draw_text buffer
              ~text:(indicator ^ truncate option.name (width - 1 - indicator_width))
              ~x:(x + 1) ~y:item_y ~foreground ~background:item_background
        | Some _font ->
            if indicator_width > 0 then
              draw_text buffer ~text:indicator ~x:(x + 1) ~y:item_y ~foreground
                ~background:item_background;
            draw_font select buffer ~text:option.name
              ~x:(x + 1 + indicator_width) ~y:item_y ~foreground
              ~background:item_background);
        if select.show_description && content_height > lines_per_item select - select.item_spacing - 1 then
          let description_color =
            if selected then select.selected_description_color
            else select.description_color
          in
          draw_text buffer
            ~text:(truncate option.description (width - 1 - indicator_width))
            ~x:(x + 1 + indicator_width)
            ~y:(item_y + (match select.font with None -> 1 | Some font -> (Ascii_font_spec.definition font).lines))
            ~foreground:description_color
            ~background:item_background
      end)
    visible_options;
  render_scroll_indicator select buffer ~x ~y ~width ~height ~background;
  Ok ()

let default_bindings =
  [
    Lib.Keybinding.binding ~name:"up" ~action:Move_up ();
    Lib.Keybinding.binding ~name:"k" ~action:Move_up ();
    Lib.Keybinding.binding ~name:"down" ~action:Move_down ();
    Lib.Keybinding.binding ~name:"j" ~action:Move_down ();
    Lib.Keybinding.binding ~name:"up" ~shift:true ~action:Move_up_fast ();
    Lib.Keybinding.binding ~name:"down" ~shift:true ~action:Move_down_fast ();
    Lib.Keybinding.binding ~name:"return" ~action:Select_current ();
    Lib.Keybinding.binding ~name:"linefeed" ~action:Select_current ();
  ]

let move_up select ?(steps = 1) () =
  Result.bind (ensure_alive select) (fun () ->
      let steps = max 1 steps in
      let next = select.selected_index - steps in
      if next < 0 && select.wrap_selection && List.length select.options > 0 then
        ignore
          (set_selected_index_internal select (List.length select.options - 1)
             ~emit:true)
      else ignore (set_selected_index_internal select next ~emit:true);
      Ok ())

let move_down select ?(steps = 1) () =
  Result.bind (ensure_alive select) (fun () ->
      let length = List.length select.options in
      let steps = max 1 steps in
      let next = select.selected_index + steps in
      if next >= length && select.wrap_selection && length > 0 then
        ignore (set_selected_index_internal select 0 ~emit:true)
      else ignore (set_selected_index_internal select next ~emit:true);
      Ok ())

let select_current select =
  Result.bind (ensure_alive select) (fun () ->
      match selected_option select with
      | None -> Ok ()
      | Some _ ->
          ignore (Event_kernel.emit select.item_events (change select));
          Ok ())

let handle_key_press select event =
  match Lib.Keybinding.action select.keymap event with
  | None -> false
  | Some Move_up ->
      Lib.Key_handler.prevent_default event;
      ignore (move_up select ());
      true
  | Some Move_down ->
      Lib.Key_handler.prevent_default event;
      ignore (move_down select ());
      true
  | Some Move_up_fast ->
      Lib.Key_handler.prevent_default event;
      ignore (move_up select ~steps:select.fast_scroll_step ());
      true
  | Some Move_down_fast ->
      Lib.Key_handler.prevent_default event;
      ignore (move_down select ~steps:select.fast_scroll_step ());
      true
  | Some Select_current ->
      Lib.Key_handler.prevent_default event;
      ignore (select_current select);
      true

let create context ?id ?(options = []) ?(selected_index = 0)
    ?(background_color = Color.transparent) ?(text_color = Color.white)
    ?(focused_background_color = focused_background_default)
    ?(focused_text_color = Color.white)
    ?(selected_background_color = selected_background_default)
    ?(selected_text_color = selected_text_default)
    ?(description_color = description_default)
    ?(selected_description_color = selected_description_default)
    ?font
    ?(show_scroll_indicator = false) ?(wrap_selection = false)
    ?(show_description = true) ?(show_selection_indicator = true)
    ?(item_spacing = 0) ?(fast_scroll_step = 5) ?(key_bindings = []) ?width
    ?height () =
  if item_spacing < 0 || fast_scroll_step < 1 then Error Error.Invalid_argument
  else
    match Renderable.Private.create context ?id () with
    | Error error -> Error error
    | Ok renderable ->
        let selected_index =
          if List.length options = 0 then 0
          else max 0 (min (List.length options - 1) selected_index)
        in
        let select =
          {
            renderable;
            options;
            selected_index;
            scroll_offset = 0;
            show_scroll_indicator;
            wrap_selection;
            show_description;
            show_selection_indicator;
            item_spacing;
            fast_scroll_step;
            background_color;
            text_color;
            focused_background_color;
            focused_text_color;
            selected_background_color;
            selected_text_color;
            description_color;
            selected_description_color;
            font;
            keymap = Lib.Keybinding.create (key_bindings @ default_bindings);
            selection_events = Event_kernel.create ();
            item_events = Event_kernel.create ();
            destroyed = false;
          }
        in
        let behavior =
          Renderable.Private.make_behavior
            ~render_self:(render_self select)
            ~key_press:(fun _ event -> ignore (handle_key_press select event))
            ~destroy_self:(fun _ ->
              select.destroyed <- true;
              Event_kernel.clear select.selection_events;
              Event_kernel.clear select.item_events)
            ()
        in
        Renderable.Private.set_behavior renderable behavior;
        let result = Renderable.set_focusable renderable true in
        let result =
          Result.bind result (fun () ->
              match width with
              | None -> Ok ()
              | Some value -> Renderable.set_width renderable value)
        in
        let result =
          Result.bind result (fun () ->
              match height with
              | None -> Ok ()
              | Some value -> Renderable.set_height renderable value)
        in
        match result with
        | Error error ->
            Renderable.destroy renderable;
            Error error
        | Ok () ->
            update_scroll_offset select;
            Ok select

let as_renderable select = select.renderable
let options select = select.options

let set_options select options =
  Result.bind (ensure_alive select) (fun () ->
      select.options <- options;
      ignore (set_selected_index_internal select select.selected_index ~emit:false);
      update_scroll_offset select;
      request select;
      Ok ())

let selected_index select = select.selected_index
let set_selected_index select index =
  Result.bind (ensure_alive select) (fun () ->
      if index < 0 || index >= List.length select.options then
        Error Error.Invalid_argument
      else begin
        ignore (set_selected_index_internal select index ~emit:true);
        Ok ()
      end)

let selected_option = selected_option

let background_color select = select.background_color
let set_background_color select value =
  Result.bind (ensure_alive select) (fun () ->
      select.background_color <- value;
      request select;
      Ok ())

let text_color select = select.text_color
let set_text_color select value =
  Result.bind (ensure_alive select) (fun () ->
      select.text_color <- value;
      request select;
      Ok ())

let focused_background_color select = select.focused_background_color
let set_focused_background_color select value =
  Result.bind (ensure_alive select) (fun () ->
      select.focused_background_color <- value;
      request select;
      Ok ())

let focused_text_color select = select.focused_text_color
let set_focused_text_color select value =
  Result.bind (ensure_alive select) (fun () ->
      select.focused_text_color <- value;
      request select;
      Ok ())

let selected_background_color select = select.selected_background_color
let set_selected_background_color select value =
  Result.bind (ensure_alive select) (fun () ->
      select.selected_background_color <- value;
      request select;
      Ok ())

let selected_text_color select = select.selected_text_color
let set_selected_text_color select value =
  Result.bind (ensure_alive select) (fun () ->
      select.selected_text_color <- value;
      request select;
      Ok ())

let description_color select = select.description_color
let set_description_color select value =
  Result.bind (ensure_alive select) (fun () ->
      select.description_color <- value;
      request select;
      Ok ())

let selected_description_color select = select.selected_description_color
let set_selected_description_color select value =
  Result.bind (ensure_alive select) (fun () ->
      select.selected_description_color <- value;
      request select;
      Ok ())

let font select = select.font

let set_font select value =
  Result.bind (ensure_alive select) (fun () ->
      select.font <- value;
      update_scroll_offset select;
      request select;
      Ok ())

let move_up = move_up
let move_down = move_down
let select_current = select_current
let show_scroll_indicator select = select.show_scroll_indicator

let set_show_scroll_indicator select value =
  Result.bind (ensure_alive select) (fun () ->
      select.show_scroll_indicator <- value;
      request select;
      Ok ())

let wrap_selection select = select.wrap_selection
let set_wrap_selection select value = select.wrap_selection <- value
let show_description select = select.show_description

let set_show_description select value =
  Result.bind (ensure_alive select) (fun () ->
      select.show_description <- value;
      update_scroll_offset select;
      request select;
      Ok ())

let show_selection_indicator select = select.show_selection_indicator

let set_show_selection_indicator select value =
  Result.bind (ensure_alive select) (fun () ->
      select.show_selection_indicator <- value;
      request select;
      Ok ())

let item_spacing select = select.item_spacing

let set_item_spacing select value =
  Result.bind (ensure_alive select) (fun () ->
      if value < 0 then Error Error.Invalid_argument
      else begin
        select.item_spacing <- value;
        update_scroll_offset select;
        request select;
        Ok ()
      end)

let fast_scroll_step select = select.fast_scroll_step

let set_fast_scroll_step select value =
  Result.bind (ensure_alive select) (fun () ->
      if value < 1 then Error Error.Invalid_argument
      else begin
        select.fast_scroll_step <- value;
        Ok ()
      end)

let set_key_bindings select bindings =
  Lib.Keybinding.set_bindings select.keymap (bindings @ default_bindings)

let on_selection_changed select callback =
  Event_kernel.on select.selection_events callback

let on_item_selected select callback = Event_kernel.on select.item_events callback
let destroy select = if not select.destroyed then Renderable.destroy select.renderable
