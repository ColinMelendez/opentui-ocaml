type option_item = Select.option_item
type action = Move_left | Move_right | Select_current
type key_binding = action Lib.Keybinding.binding
type selection_change = { index : int; option : option_item option }

type t = {
  renderable : Renderable.t;
  mutable options : option_item list;
  mutable selected_index : int;
  mutable scroll_offset : int;
  mutable tab_width : int;
  mutable background_color : Color.t;
  mutable text_color : Color.t;
  mutable focused_background_color : Color.t;
  mutable focused_text_color : Color.t;
  mutable selected_background_color : Color.t;
  mutable selected_text_color : Color.t;
  mutable selected_description_color : Color.t;
  mutable show_scroll_arrows : bool;
  mutable show_description : bool;
  mutable show_underline : bool;
  mutable wrap_selection : bool;
  keymap : action Lib.Keybinding.t;
  selection_events : selection_change Event_kernel.t;
  item_events : selection_change Event_kernel.t;
  mutable destroyed : bool;
}

let focused_background_default =
  match Color.rgba ~red:26 ~green:26 ~blue:26 ~alpha:255 with
  | Ok color -> color
  | Error _ -> Color.black

let ensure_alive select =
  if select.destroyed || Renderable.is_destroyed select.renderable then Error Error.Destroyed
  else Ok ()

let selected_option select =
  if select.selected_index < 0 then None else List.nth_opt select.options select.selected_index

let change select = { index = select.selected_index; option = selected_option select }

let row_count select = 1 + (if select.show_underline then 1 else 0) + (if select.show_description then 1 else 0)

let max_visible select =
  max 1 (int_of_float (Float.floor (Renderable.width select.renderable)) / max 1 select.tab_width)

let update_scroll_offset select =
  let maximum = max 0 (List.length select.options - max_visible select) in
  let half = max_visible select / 2 in
  select.scroll_offset <- max 0 (min maximum (select.selected_index - half))

let request select = ignore (Renderable.request_render select.renderable)

let set_height select =
  Renderable.set_height select.renderable (Yoga.Point (float_of_int (row_count select)))

let emit_selection select =
  ignore (Event_kernel.emit select.selection_events (change select));
  request select

let set_selected_index_internal select index ~emit =
  let length = List.length select.options in
  let next = if length = 0 then 0 else max 0 (min (length - 1) index) in
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
          (Buffer.set_cell buffer ~x:(Int32.of_int column) ~y:(Int32.of_int row)
             ~character:32l ~foreground ~background ~attributes:0l)
      done
    done

let draw_text buffer ~text ~x ~y ~foreground ~background =
  ignore
    (Buffer.draw_text buffer ~text ~x:(Int32.of_int x) ~y:(Int32.of_int y)
       ~foreground ~background ~attributes:0l)

let repeat text count =
  String.concat "" (List.init (max 0 count) (fun _ -> text))

let truncate text width =
  if width <= 0 then ""
  else if String.length text <= width then text
  else if width = 1 then "…"
  else String.sub text 0 (width - 1) ^ "…"

let render_self select renderable buffer _delta_time =
  let x = int_of_float (Float.floor (Renderable.screen_x renderable)) in
  let y = int_of_float (Float.floor (Renderable.screen_y renderable)) in
  let width = max 0 (int_of_float (Float.floor (Renderable.width renderable))) in
  let height = max 0 (int_of_float (Float.floor (Renderable.height renderable))) in
  let background = if Renderable.focused renderable then select.focused_background_color else select.background_color in
  fill buffer ~x ~y ~width ~height ~foreground:background ~background;
  let visible = max_visible select in
  let visible_options =
    select.options
    |> List.mapi (fun index option -> index, option)
    |> List.filter (fun (index, _) -> index >= select.scroll_offset && index < select.scroll_offset + visible)
  in
  List.iter
    (fun (index, option) ->
      let offset = index - select.scroll_offset in
      let tab_x = x + (offset * select.tab_width) in
      let actual_width = min select.tab_width (width - (offset * select.tab_width)) in
      if actual_width > 0 then begin
        let selected = Int.equal index select.selected_index in
        if selected then
          fill buffer ~x:tab_x ~y ~width:actual_width ~height:1
            ~foreground:select.selected_background_color
            ~background:select.selected_background_color;
        let foreground = if selected then select.selected_text_color else if Renderable.focused renderable then select.focused_text_color else select.text_color in
        draw_text buffer ~text:(truncate option.Select.name (actual_width - 2))
          ~x:(tab_x + 1) ~y ~foreground ~background;
        if selected && select.show_underline && height > 1 then
          draw_text buffer ~text:(repeat "▬" actual_width) ~x:tab_x
            ~y:(y + 1) ~foreground:select.selected_text_color
            ~background:select.selected_background_color
      end)
    visible_options;
  if select.show_description && height > 1 + (if select.show_underline then 1 else 0) then begin
    match selected_option select with
    | None -> ()
    | Some option ->
        draw_text buffer ~text:(truncate option.Select.description (width - 2))
          ~x:(x + 1)
          ~y:(y + 1 + if select.show_underline then 1 else 0)
          ~foreground:select.selected_description_color ~background
  end;
  if select.show_scroll_arrows && width > 1 && List.length select.options > visible then begin
    if select.scroll_offset > 0 then draw_text buffer ~text:"‹" ~x ~y ~foreground:Color.white ~background;
    if select.scroll_offset + visible < List.length select.options then
      draw_text buffer ~text:"›" ~x:(x + width - 1) ~y ~foreground:Color.white ~background
  end;
  Ok ()

let handle_mouse select event =
  match Renderable.mouse_kind event with
  | Renderable.Down ->
      let local_x = Renderable.mouse_x event - int_of_float (Float.floor (Renderable.screen_x select.renderable)) in
      let index = select.scroll_offset + (local_x / max 1 select.tab_width) in
      if local_x >= 0 && index >= 0 && index < List.length select.options then begin
        Renderable.mouse_prevent_default event;
        ignore (set_selected_index_internal select index ~emit:true)
      end
  | Renderable.Scroll ->
      Option.iter
        (fun scroll ->
          match scroll.Lib.Mouse_decoder.direction with
          | Lib.Mouse_decoder.Scroll_left | Lib.Mouse_decoder.Scroll_up -> ignore (set_selected_index_internal select (select.selected_index - 1) ~emit:true)
          | Lib.Mouse_decoder.Scroll_right | Lib.Mouse_decoder.Scroll_down -> ignore (set_selected_index_internal select (select.selected_index + 1) ~emit:true))
        (Renderable.mouse_scroll event)
  | Renderable.Up | Renderable.Move | Renderable.Drag | Renderable.Drag_end
  | Renderable.Drop | Renderable.Over | Renderable.Out -> ()

let default_bindings =
  [
    Lib.Keybinding.binding ~name:"left" ~action:Move_left ();
    Lib.Keybinding.binding ~name:"[" ~action:Move_left ();
    Lib.Keybinding.binding ~name:"right" ~action:Move_right ();
    Lib.Keybinding.binding ~name:"]" ~action:Move_right ();
    Lib.Keybinding.binding ~name:"return" ~action:Select_current ();
    Lib.Keybinding.binding ~name:"linefeed" ~action:Select_current ();
  ]

let move_left select =
  Result.bind (ensure_alive select) (fun () ->
      if List.length select.options = 0 then Ok ()
      else if select.selected_index = 0 && select.wrap_selection then begin
        ignore (set_selected_index_internal select (List.length select.options - 1) ~emit:true);
        Ok ()
      end else begin
        ignore (set_selected_index_internal select (select.selected_index - 1) ~emit:true);
        Ok ()
      end)

let move_right select =
  Result.bind (ensure_alive select) (fun () ->
      let length = List.length select.options in
      if length = 0 then Ok ()
      else if select.selected_index = length - 1 && select.wrap_selection then begin
        ignore (set_selected_index_internal select 0 ~emit:true);
        Ok ()
      end else begin
        ignore (set_selected_index_internal select (select.selected_index + 1) ~emit:true);
        Ok ()
      end)

let select_current select =
  Result.bind (ensure_alive select) (fun () ->
      match selected_option select with None -> Ok () | Some _ -> ignore (Event_kernel.emit select.item_events (change select)); Ok ())

let handle_key_press select event =
  match Lib.Keybinding.action select.keymap event with
  | None -> false
  | Some Move_left -> Lib.Key_handler.prevent_default event; ignore (move_left select); true
  | Some Move_right -> Lib.Key_handler.prevent_default event; ignore (move_right select); true
  | Some Select_current -> Lib.Key_handler.prevent_default event; ignore (select_current select); true

let create context ?id ?(options = []) ?(tab_width = 20)
    ?(background_color = Color.transparent) ?(text_color = Color.white)
    ?(focused_background_color = focused_background_default) ?(focused_text_color = Color.white)
    ?(selected_background_color = Color.rgba ~red:51 ~green:68 ~blue:85 ~alpha:255 |> Result.get_ok)
    ?(selected_text_color = Color.rgba ~red:255 ~green:255 ~blue:0 ~alpha:255 |> Result.get_ok)
    ?(selected_description_color = Color.rgba ~red:204 ~green:204 ~blue:204 ~alpha:255 |> Result.get_ok)
    ?(show_scroll_arrows = true) ?(show_description = true)
    ?(show_underline = true) ?(wrap_selection = false) ?(key_bindings = [])
    ?width () =
  if tab_width < 1 then Error Error.Invalid_argument
  else
    match Renderable.Private.create context ?id () with
    | Error error -> Error error
    | Ok renderable ->
        let select =
          {
            renderable;
            options;
            selected_index = 0;
            scroll_offset = 0;
            tab_width;
            background_color;
            text_color;
            focused_background_color;
            focused_text_color;
            selected_background_color;
            selected_text_color;
            selected_description_color;
            show_scroll_arrows;
            show_description;
            show_underline;
            wrap_selection;
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
            ~mouse_event:(fun _ event -> handle_mouse select event)
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
        let result = Result.bind result (fun () -> set_height select) in
        match result with
        | Error error -> Renderable.destroy renderable; Error error
        | Ok () -> Ok select

let as_renderable select = select.renderable
let options select = select.options
let set_options select options = Result.bind (ensure_alive select) (fun () -> select.options <- options; ignore (set_selected_index_internal select select.selected_index ~emit:false); request select; Ok ())
let selected_index select = select.selected_index
let set_selected_index select index = Result.bind (ensure_alive select) (fun () -> if index < 0 || index >= List.length select.options then Error Error.Invalid_argument else (ignore (set_selected_index_internal select index ~emit:true); Ok ()))
let selected_option = selected_option
let move_left = move_left
let move_right = move_right
let select_current = select_current
let tab_width select = select.tab_width
let set_tab_width select value = Result.bind (ensure_alive select) (fun () -> if value < 1 then Error Error.Invalid_argument else (select.tab_width <- value; update_scroll_offset select; request select; Ok ()))
let background_color select = select.background_color
let set_background_color select value = Result.bind (ensure_alive select) (fun () -> select.background_color <- value; request select; Ok ())
let text_color select = select.text_color
let set_text_color select value = Result.bind (ensure_alive select) (fun () -> select.text_color <- value; request select; Ok ())
let focused_background_color select = select.focused_background_color
let set_focused_background_color select value = Result.bind (ensure_alive select) (fun () -> select.focused_background_color <- value; request select; Ok ())
let focused_text_color select = select.focused_text_color
let set_focused_text_color select value = Result.bind (ensure_alive select) (fun () -> select.focused_text_color <- value; request select; Ok ())
let selected_background_color select = select.selected_background_color
let set_selected_background_color select value = Result.bind (ensure_alive select) (fun () -> select.selected_background_color <- value; request select; Ok ())
let selected_text_color select = select.selected_text_color
let set_selected_text_color select value = Result.bind (ensure_alive select) (fun () -> select.selected_text_color <- value; request select; Ok ())
let selected_description_color select = select.selected_description_color
let set_selected_description_color select value = Result.bind (ensure_alive select) (fun () -> select.selected_description_color <- value; request select; Ok ())
let show_scroll_arrows select = select.show_scroll_arrows
let set_show_scroll_arrows select value = Result.bind (ensure_alive select) (fun () -> select.show_scroll_arrows <- value; request select; Ok ())
let show_description select = select.show_description
let set_show_description select value = Result.bind (ensure_alive select) (fun () -> select.show_description <- value; ignore (set_height select); update_scroll_offset select; request select; Ok ())
let show_underline select = select.show_underline
let set_show_underline select value = Result.bind (ensure_alive select) (fun () -> select.show_underline <- value; ignore (set_height select); request select; Ok ())
let wrap_selection select = select.wrap_selection
let set_wrap_selection select value = select.wrap_selection <- value
let set_key_bindings select bindings = Lib.Keybinding.set_bindings select.keymap (bindings @ default_bindings)
let on_selection_changed select callback = Event_kernel.on select.selection_events callback
let on_item_selected select callback = Event_kernel.on select.item_events callback
let destroy select = if not select.destroyed then Renderable.destroy select.renderable
