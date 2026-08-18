type action =
  | Move_left
  | Move_right
  | Move_up
  | Move_down
  | Select_left
  | Select_right
  | Select_up
  | Select_down
  | Line_home
  | Line_end
  | Select_line_home
  | Select_line_end
  | Visual_line_home
  | Visual_line_end
  | Select_visual_line_home
  | Select_visual_line_end
  | Buffer_home
  | Buffer_end
  | Select_buffer_home
  | Select_buffer_end
  | Delete_line
  | Delete_to_line_end
  | Delete_to_line_start
  | Backspace
  | Delete
  | Newline
  | Undo
  | Redo
  | Word_forward
  | Word_backward
  | Select_word_forward
  | Select_word_backward
  | Delete_word_forward
  | Delete_word_backward
  | Select_all
  | Submit

type key_binding = action Lib.Keybinding.binding
type capture = Escape | Navigate | Submit | Tab

type traits = {
  capture : capture list;
  suspend : bool;
  status : string option;
}

type cursor_style = Block | Underline | Bar

type cursor_change = { line : int; visual_column : int }

let default_text_color = Color.white
let default_background_color = Color.transparent
let default_cursor_color = Color.white

let default_selection_bg () =
  match Color.rgba ~red:60 ~green:90 ~blue:140 ~alpha:255 with
  | Ok color -> color
  | Error _ -> Color.transparent

let default_bindings =
  [
    Lib.Keybinding.binding ~name:"left" ~action:Move_left ();
    Lib.Keybinding.binding ~name:"right" ~action:Move_right ();
    Lib.Keybinding.binding ~name:"up" ~action:Move_up ();
    Lib.Keybinding.binding ~name:"down" ~action:Move_down ();
    Lib.Keybinding.binding ~name:"left" ~shift:true ~action:Select_left ();
    Lib.Keybinding.binding ~name:"right" ~shift:true ~action:Select_right ();
    Lib.Keybinding.binding ~name:"up" ~shift:true ~action:Select_up ();
    Lib.Keybinding.binding ~name:"down" ~shift:true ~action:Select_down ();
    Lib.Keybinding.binding ~name:"home" ~action:Buffer_home ();
    Lib.Keybinding.binding ~name:"end" ~action:Buffer_end ();
    Lib.Keybinding.binding ~name:"home" ~shift:true ~action:Select_buffer_home ();
    Lib.Keybinding.binding ~name:"end" ~shift:true ~action:Select_buffer_end ();
    Lib.Keybinding.binding ~name:"a" ~ctrl:true ~action:Line_home ();
    Lib.Keybinding.binding ~name:"e" ~ctrl:true ~action:Line_end ();
    Lib.Keybinding.binding ~name:"a" ~ctrl:true ~shift:true
      ~action:Select_line_home ();
    Lib.Keybinding.binding ~name:"e" ~ctrl:true ~shift:true
      ~action:Select_line_end ();
    Lib.Keybinding.binding ~name:"a" ~meta:true ~action:Visual_line_home ();
    Lib.Keybinding.binding ~name:"e" ~meta:true ~action:Visual_line_end ();
    Lib.Keybinding.binding ~name:"a" ~meta:true ~shift:true
      ~action:Select_visual_line_home ();
    Lib.Keybinding.binding ~name:"e" ~meta:true ~shift:true
      ~action:Select_visual_line_end ();
    Lib.Keybinding.binding ~name:"f" ~ctrl:true ~action:Move_right ();
    Lib.Keybinding.binding ~name:"b" ~ctrl:true ~action:Move_left ();
    Lib.Keybinding.binding ~name:"w" ~ctrl:true ~action:Delete_word_backward ();
    Lib.Keybinding.binding ~name:"backspace" ~ctrl:true
      ~action:Delete_word_backward ();
    Lib.Keybinding.binding ~name:"d" ~meta:true ~action:Delete_word_forward ();
    Lib.Keybinding.binding ~name:"delete" ~meta:true ~action:Delete_word_forward ();
    Lib.Keybinding.binding ~name:"delete" ~ctrl:true ~action:Delete_word_forward ();
    Lib.Keybinding.binding ~name:"d" ~ctrl:true ~shift:true ~action:Delete_line ();
    Lib.Keybinding.binding ~name:"k" ~ctrl:true ~action:Delete_to_line_end ();
    Lib.Keybinding.binding ~name:"u" ~ctrl:true ~action:Delete_to_line_start ();
    Lib.Keybinding.binding ~name:"backspace" ~action:Backspace ();
    Lib.Keybinding.binding ~name:"backspace" ~shift:true ~action:Backspace ();
    Lib.Keybinding.binding ~name:"d" ~ctrl:true ~action:Delete ();
    Lib.Keybinding.binding ~name:"delete" ~action:Delete ();
    Lib.Keybinding.binding ~name:"delete" ~shift:true ~action:Delete ();
    Lib.Keybinding.binding ~name:"return" ~action:Newline ();
    Lib.Keybinding.binding ~name:"kpenter" ~action:Newline ();
    Lib.Keybinding.binding ~name:"linefeed" ~action:Newline ();
    Lib.Keybinding.binding ~name:"return" ~meta:true ~action:(Submit : action) ();
    Lib.Keybinding.binding ~name:"kpenter" ~meta:true ~action:(Submit : action) ();
    Lib.Keybinding.binding ~name:"-" ~ctrl:true ~action:Undo ();
    Lib.Keybinding.binding ~name:"." ~ctrl:true ~action:Redo ();
    Lib.Keybinding.binding ~name:"f" ~meta:true ~action:Word_forward ();
    Lib.Keybinding.binding ~name:"b" ~meta:true ~action:Word_backward ();
    Lib.Keybinding.binding ~name:"right" ~meta:true ~action:Word_forward ();
    Lib.Keybinding.binding ~name:"left" ~meta:true ~action:Word_backward ();
    Lib.Keybinding.binding ~name:"right" ~ctrl:true ~action:Word_forward ();
    Lib.Keybinding.binding ~name:"left" ~ctrl:true ~action:Word_backward ();
    Lib.Keybinding.binding ~name:"f" ~meta:true ~shift:true
      ~action:Select_word_forward ();
    Lib.Keybinding.binding ~name:"b" ~meta:true ~shift:true
      ~action:Select_word_backward ();
    Lib.Keybinding.binding ~name:"right" ~meta:true ~shift:true
      ~action:Select_word_forward ();
    Lib.Keybinding.binding ~name:"left" ~meta:true ~shift:true
      ~action:Select_word_backward ();
    Lib.Keybinding.binding ~name:"backspace" ~meta:true
      ~action:Delete_word_backward ();
    Lib.Keybinding.binding ~name:"a" ~super:true ~action:Select_all ();
  ]

type t = {
  renderable : Renderable.t;
  text_renderable : Text_buffer_renderable.t;
  cursor_renderable : Renderable.t;
  edit_buffer : Edit_buffer.t;
  editor_view : Editor_view.t;
  mutable selectable : bool;
  mutable show_cursor : bool;
  mutable text_color : Color.t;
  mutable background_color : Color.t;
  mutable selection_bg : Color.t option;
  mutable selection_fg : Color.t option;
  mutable cursor_color : Color.t;
  mutable cursor_style : cursor_style;
  mutable scroll_margin : float;
  mutable scroll_speed : float;
  mutable traits : traits;
  keymap : action Lib.Keybinding.t;
  cursor_events : cursor_change Event_kernel.t;
  content_events : unit Event_kernel.t;
  submit_events : unit Event_kernel.t;
  traits_events : traits Event_kernel.t;
  mutable last_viewport : Editor_view.viewport;
  mutable destroyed : bool;
}

let ensure_alive editor =
  if editor.destroyed || Renderable.is_destroyed editor.renderable then
    Error Error.Destroyed
  else Ok ()

let request_render editor = Renderable.request_render editor.renderable

let width_method_metrics = function
  | Edit_buffer.Wcwidth -> Lib.Text_metrics.Wcwidth
  | Edit_buffer.Unicode -> Lib.Text_metrics.Unicode

let text_width editor =
  Result.map
    (Lib.Text_metrics.display_width (width_method_metrics
       (Edit_buffer.width_method editor.edit_buffer)))
    (Edit_buffer.text editor.edit_buffer)

let cursor_offset editor =
  Result.map (fun cursor -> cursor.Edit_buffer.offset)
    (Edit_buffer.cursor editor.edit_buffer)

let selection_range editor = Editor_view.selection editor.editor_view
let selected_range editor = Editor_view.selected_range editor.editor_view

let viewport_equal (left : Editor_view.viewport) (right : Editor_view.viewport) =
  Int.equal left.offset_x right.offset_x
  && Int.equal left.offset_y right.offset_y
  && Int.equal left.width right.width
  && Int.equal left.height right.height

let sync_native_selection editor =
  match selection_range editor with
  | None -> ignore (Text_buffer_renderable.reset_selection editor.text_renderable)
  | Some (start, end_) ->
      ignore
        (Text_buffer_renderable.set_selection editor.text_renderable ~start
           ~end_ ?bg_color:editor.selection_bg ?fg_color:editor.selection_fg ())

let sync_text editor =
  match Edit_buffer.text editor.edit_buffer with
  | Error _ -> ()
  | Ok text ->
      ignore (Text_buffer_renderable.set_text editor.text_renderable text);
      ignore (Renderable.Private.mark_yoga_dirty editor.renderable)

let sync_viewport editor =
  let viewport = Editor_view.viewport editor.editor_view in
  if
    not (viewport_equal viewport editor.last_viewport)
  then begin
    ignore
      (Text_buffer_renderable.set_viewport editor.text_renderable
         ~x:viewport.offset_x ~y:viewport.offset_y ~width:viewport.width
         ~height:viewport.height);
    editor.last_viewport <- viewport
  end

let set_cursor_display editor visible =
  let display = if visible then Yoga.Display_flex else Yoga.Display_none in
  ignore (Renderable.set_display editor.cursor_renderable display)

let update_cursor editor =
  match Editor_view.absolute_visual_cursor editor.editor_view with
  | Error _ -> set_cursor_display editor false
  | Ok visual ->
      let viewport = Editor_view.viewport editor.editor_view in
      let x = visual.col - viewport.offset_x in
      let y = visual.row - viewport.offset_y in
      if
        editor.show_cursor && Renderable.focused editor.renderable && x >= 0
        && y >= 0 && x < viewport.width && y < viewport.height
      then begin
        ignore
          (Renderable.set_position editor.cursor_renderable ~edge:Yoga.Left
             (Yoga.Point (float_of_int x)));
        ignore
          (Renderable.set_position editor.cursor_renderable ~edge:Yoga.Top
             (Yoga.Point (float_of_int y)));
        set_cursor_display editor true
      end else set_cursor_display editor false

let ensure_cursor_visible editor =
  match Editor_view.absolute_visual_cursor editor.editor_view with
  | Error _ -> ()
  | Ok visual ->
      let viewport = Editor_view.viewport editor.editor_view in
      let margin = max 0 (int_of_float (Float.floor (float_of_int viewport.height *. editor.scroll_margin))) in
      let maximum = max 0 (Editor_view.total_virtual_line_count editor.editor_view - viewport.height) in
      let next_y =
        if visual.row < viewport.offset_y + margin then
          max 0 (min maximum (visual.row - margin))
        else if visual.row >= viewport.offset_y + viewport.height - margin then
          max 0 (min maximum (visual.row - viewport.height + 1 + margin))
        else viewport.offset_y
      in
      if not (Int.equal next_y viewport.offset_y) then
        Editor_view.set_viewport editor.editor_view ~x:viewport.offset_x ~y:next_y
          ~width:viewport.width ~height:viewport.height ()

let emit_cursor_change editor =
  match Edit_buffer.cursor editor.edit_buffer with
  | Error _ -> ()
  | Ok cursor ->
      ignore
        (Event_kernel.emit editor.cursor_events
           { line = cursor.row; visual_column = cursor.col })

let after_edit editor =
  ensure_cursor_visible editor;
  sync_viewport editor;
  sync_native_selection editor;
  emit_cursor_change editor;
  ignore (request_render editor)

let set_keyboard_selection_before editor select =
  if not editor.selectable then ()
  else if select then
    match selected_range editor, cursor_offset editor with
    | None, Ok offset ->
        Editor_view.set_selection editor.editor_view ~start:offset ~end_:offset
    | Some _, _ -> ()
    | None, Error _ -> ()
  else begin
    Editor_view.reset_selection editor.editor_view;
    Editor_view.reset_local_selection editor.editor_view;
    ignore (Text_buffer_renderable.reset_selection editor.text_renderable)
  end

let set_keyboard_selection_after editor select =
  if select then
    match cursor_offset editor with
    | Ok offset -> Editor_view.update_selection editor.editor_view ~end_:offset
    | Error _ -> ()
  else ()

let run_movement editor ~select movement =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () ->
      (match selected_range editor, select, cursor_offset editor with
      | Some (start, end_), false, Ok offset
        when not (Int.equal start end_) ->
          let target = if offset <= start then start else end_ in
          Result.bind (Edit_buffer.set_cursor_by_offset editor.edit_buffer target)
            (fun () ->
              Editor_view.reset_selection editor.editor_view;
              Editor_view.reset_local_selection editor.editor_view;
              ignore (Text_buffer_renderable.reset_selection editor.text_renderable);
              ignore
                (Text_buffer_renderable.reset_local_selection
                   editor.text_renderable);
              after_edit editor;
              Ok ())
      | _ ->
          set_keyboard_selection_before editor select;
          Result.bind (movement ()) (fun () ->
              set_keyboard_selection_after editor select;
              after_edit editor;
              Ok ()))

let run_edit editor operation =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () ->
      let had_selection = Option.is_some (selected_range editor) in
      let operation_result =
        if had_selection then
          Result.bind (Editor_view.delete_selected_text editor.editor_view)
            (fun () -> operation ())
        else operation ()
      in
      Result.bind operation_result (fun () ->
          if had_selection then Editor_view.reset_selection editor.editor_view;
          after_edit editor;
          Ok ())

let undo_impl editor =
  Result.bind (ensure_alive editor) (fun () ->
      Editor_view.reset_selection editor.editor_view;
      Result.bind (Edit_buffer.undo editor.edit_buffer) (fun value ->
          after_edit editor;
          Ok value))

let redo_impl editor =
  Result.bind (ensure_alive editor) (fun () ->
      Editor_view.reset_selection editor.editor_view;
      Result.bind (Edit_buffer.redo editor.edit_buffer) (fun value ->
          after_edit editor;
          Ok value))

let rec action editor action =
  match action with
  | Move_left -> run_movement editor ~select:false (fun () -> Edit_buffer.move_cursor_left editor.edit_buffer)
  | Move_right -> run_movement editor ~select:false (fun () -> Edit_buffer.move_cursor_right editor.edit_buffer)
  | Move_up -> run_movement editor ~select:false (fun () -> Editor_view.move_up_visual editor.editor_view)
  | Move_down -> run_movement editor ~select:false (fun () -> Editor_view.move_down_visual editor.editor_view)
  | Select_left -> run_movement editor ~select:true (fun () -> Edit_buffer.move_cursor_left editor.edit_buffer)
  | Select_right -> run_movement editor ~select:true (fun () -> Edit_buffer.move_cursor_right editor.edit_buffer)
  | Select_up -> run_movement editor ~select:true (fun () -> Editor_view.move_up_visual editor.editor_view)
  | Select_down -> run_movement editor ~select:true (fun () -> Editor_view.move_down_visual editor.editor_view)
  | Line_home | Select_line_home ->
      run_movement editor ~select:(match action with Select_line_home -> true | _ -> false)
        (fun () ->
          Result.bind (Edit_buffer.cursor editor.edit_buffer) (fun cursor ->
              Edit_buffer.set_cursor editor.edit_buffer ~line:cursor.row ~col:0))
  | Line_end | Select_line_end ->
      run_movement editor ~select:(match action with Select_line_end -> true | _ -> false)
        (fun () ->
          Result.bind (Edit_buffer.eol editor.edit_buffer) (fun cursor ->
              Edit_buffer.set_cursor_by_offset editor.edit_buffer cursor.offset))
  | Visual_line_home | Select_visual_line_home ->
      run_movement editor ~select:(match action with Select_visual_line_home -> true | _ -> false)
        (fun () ->
          Result.bind (Editor_view.visual_sol editor.editor_view) (fun cursor ->
              Edit_buffer.set_cursor_by_offset editor.edit_buffer cursor.offset))
  | Visual_line_end | Select_visual_line_end ->
      run_movement editor ~select:(match action with Select_visual_line_end -> true | _ -> false)
        (fun () ->
          Result.bind (Editor_view.visual_eol editor.editor_view) (fun cursor ->
              Edit_buffer.set_cursor_by_offset editor.edit_buffer cursor.offset))
  | Buffer_home | Select_buffer_home ->
      run_movement editor ~select:(match action with Select_buffer_home -> true | _ -> false)
        (fun () -> Edit_buffer.set_cursor_by_offset editor.edit_buffer 0)
  | Buffer_end | Select_buffer_end ->
      run_movement editor ~select:(match action with Select_buffer_end -> true | _ -> false)
        (fun () ->
          Result.bind (text_width editor) (fun width ->
              Edit_buffer.set_cursor_by_offset editor.edit_buffer width))
  | Delete_line -> run_edit editor (fun () -> Edit_buffer.delete_line editor.edit_buffer)
  | Delete_to_line_end ->
      run_edit editor (fun () ->
          Result.bind (Edit_buffer.cursor editor.edit_buffer) (fun cursor ->
              Result.bind (Edit_buffer.eol editor.edit_buffer) (fun finish ->
                  Edit_buffer.delete_range editor.edit_buffer ~start_row:cursor.row
                    ~start_col:cursor.col ~end_row:finish.row ~end_col:finish.col)))
  | Delete_to_line_start ->
      run_edit editor (fun () ->
          Result.bind (Edit_buffer.cursor editor.edit_buffer) (fun cursor ->
              if cursor.col > 0 then
                Edit_buffer.delete_range editor.edit_buffer ~start_row:cursor.row
                  ~start_col:0 ~end_row:cursor.row ~end_col:cursor.col
              else if cursor.row > 0 then Edit_buffer.delete_char_backward editor.edit_buffer
              else Ok ()))
  | Backspace -> run_edit editor (fun () -> Edit_buffer.delete_char_backward editor.edit_buffer)
  | Delete -> run_edit editor (fun () -> Edit_buffer.delete_char editor.edit_buffer)
  | Newline -> run_edit editor (fun () -> Edit_buffer.new_line editor.edit_buffer)
  | Undo ->
      Result.bind (undo_impl editor) (fun _ -> Ok ())
  | Redo ->
      Result.bind (redo_impl editor) (fun _ -> Ok ())
  | Word_forward | Select_word_forward ->
      run_movement editor ~select:(match action with Select_word_forward -> true | _ -> false)
        (fun () ->
          Result.bind (Edit_buffer.next_word_boundary editor.edit_buffer) (fun cursor ->
              Edit_buffer.set_cursor_by_offset editor.edit_buffer cursor.offset))
  | Word_backward | Select_word_backward ->
      run_movement editor ~select:(match action with Select_word_backward -> true | _ -> false)
        (fun () ->
          Result.bind (Edit_buffer.previous_word_boundary editor.edit_buffer) (fun cursor ->
              Edit_buffer.set_cursor_by_offset editor.edit_buffer cursor.offset))
  | Delete_word_forward ->
      run_edit editor (fun () ->
          Result.bind (Edit_buffer.cursor editor.edit_buffer) (fun current ->
              Result.bind (Edit_buffer.next_word_boundary editor.edit_buffer) (fun finish ->
                  Edit_buffer.delete_range editor.edit_buffer ~start_row:current.row
                    ~start_col:current.col ~end_row:finish.row ~end_col:finish.col)))
  | Delete_word_backward ->
      run_edit editor (fun () ->
          Result.bind (Edit_buffer.cursor editor.edit_buffer) (fun current ->
              Result.bind (Edit_buffer.previous_word_boundary editor.edit_buffer) (fun start ->
                  Edit_buffer.delete_range editor.edit_buffer ~start_row:start.row
                    ~start_col:start.col ~end_row:current.row ~end_col:current.col)))
  | Select_all -> select_all editor
  | Submit ->
      ignore (Event_kernel.emit editor.submit_events ());
      Ok ()

and select_all editor =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () ->
      Result.bind (text_width editor) (fun width ->
          Editor_view.reset_local_selection editor.editor_view;
          Editor_view.set_selection editor.editor_view ~start:0 ~end_:width;
          after_edit editor;
          Ok ())

let sync_pointer_selection editor selection =
  match Lib.Selection.convert_global_to_local selection
          ~local_x:(Renderable.screen_x editor.renderable)
          ~local_y:(Renderable.screen_y editor.renderable) with
  | None ->
      Editor_view.reset_selection editor.editor_view;
      Editor_view.reset_local_selection editor.editor_view;
      ignore (Text_buffer_renderable.reset_local_selection editor.text_renderable)
  | Some local ->
      let anchor_x = int_of_float (Float.floor local.anchor_x) in
      let anchor_y = int_of_float (Float.floor local.anchor_y) in
      let focus_x = int_of_float (Float.floor local.focus_x) in
      let focus_y = int_of_float (Float.floor local.focus_y) in
      let changed =
        if Option.is_some (Editor_view.selection editor.editor_view) then
          Editor_view.update_local_selection editor.editor_view
            ~anchor_x ~anchor_y ~focus_x ~focus_y
        else
          Editor_view.set_local_selection editor.editor_view
            ~anchor_x ~anchor_y ~focus_x ~focus_y
      in
      ignore changed;
      ignore
        (Text_buffer_renderable.set_local_selection editor.text_renderable
           ~anchor_x ~anchor_y ~focus_x ~focus_y
           ?bg_color:editor.selection_bg ?fg_color:editor.selection_fg ())

let handle_scroll editor scroll =
  let viewport = Editor_view.viewport editor.editor_view in
  let delta = max 1 scroll.Lib.Mouse_decoder.delta in
  let x, y = viewport.offset_x, viewport.offset_y in
  let x, y =
    match scroll.direction with
    | Lib.Mouse_decoder.Scroll_up -> x, max 0 (y - delta)
    | Scroll_down -> x, min (max 0 (Editor_view.total_virtual_line_count editor.editor_view - viewport.height)) (y + delta)
    | Scroll_left -> max 0 (x - delta), y
    | Scroll_right -> x + delta, y
  in
  Editor_view.set_viewport editor.editor_view ~x ~y ~width:viewport.width
    ~height:viewport.height ();
  sync_viewport editor;
  ignore (request_render editor)

let insert_text_impl editor value =
  run_edit editor (fun () -> Edit_buffer.insert_text editor.edit_buffer value)

let handle_key_press editor event =
  if editor.traits.suspend then false
  else
    match Lib.Keybinding.action editor.keymap event with
    | Some action_value ->
        Lib.Key_handler.prevent_default event;
        ignore (action editor action_value);
        true
    | None ->
        (match Lib.Key_handler.key event with
        | Lib.Key_decoder.Named Lib.Key_decoder.Space ->
            let modifiers = Lib.Key_handler.key_modifiers event in
            if modifiers.ctrl || modifiers.meta then false
            else begin
              Lib.Key_handler.prevent_default event;
              ignore (insert_text_impl editor " ");
              true
            end
        | Lib.Key_decoder.Character bytes ->
            let modifiers = Lib.Key_handler.key_modifiers event in
            if modifiers.ctrl || modifiers.meta then false
            else
              let value = Bytes.to_string bytes in
              if String.length value = 0 || Char.code (String.get value 0) < 32 then false
              else begin
                Lib.Key_handler.prevent_default event;
                ignore (insert_text_impl editor value);
                true
              end
        | Lib.Key_decoder.Named _ -> false)

let handle_paste editor event =
  Lib.Key_handler.paste_prevent_default event;
  let value =
    Lib.Paste.strip_ansi
      (Lib.Paste.decode (Lib.Key_handler.paste_raw event))
  in
  if String.length value > 0 then ignore (insert_text_impl editor value)

let update_cursor_render editor _ delta_time =
  ignore delta_time;
  ensure_cursor_visible editor;
  sync_viewport editor;
  update_cursor editor

let create context ?id ?(width_method = Edit_buffer.Unicode)
    ?(wrap_mode = Text_buffer_view.Word) ?initial_text
    ?(text_color = default_text_color) ?(background_color = default_background_color)
    ?selection_bg ?selection_fg ?(selectable = true) ?(attributes = 0)
    ?(scroll_margin = 0.2) ?(scroll_speed = 16.0) ?(show_cursor = true)
    ?(cursor_color = default_cursor_color) ?(cursor_style = Block)
    ?tab_indicator ?tab_indicator_color ?(focusable = true) ?width ?height
    ?(key_bindings = []) () =
  match Renderable.Private.create context ?id () with
  | Error error -> Error error
  | Ok renderable ->
      let text_width_method =
        match width_method with
        | Edit_buffer.Wcwidth -> Text_buffer.Wcwidth
        | Edit_buffer.Unicode -> Text_buffer.Unicode
      in
      (match
         Text_buffer_renderable.create context ~width_method:text_width_method
           ~wrap_mode ~selectable:false ~scrollable:false ()
       with
      | Error error ->
          Renderable.destroy renderable;
          Error error
      | Ok text_renderable ->
          (match Renderable.Private.create context () with
          | Error error ->
              Text_buffer_renderable.destroy text_renderable;
              Renderable.destroy renderable;
              Error error
          | Ok cursor_renderable ->
              let edit_buffer = Edit_buffer.create width_method in
              let editor_view =
                Editor_view.create edit_buffer ~viewport_width:0 ~viewport_height:0
              in
              let initial_viewport = Editor_view.viewport editor_view in
              let editor =
                {
                  renderable;
                  text_renderable;
                  cursor_renderable;
                  edit_buffer;
                  editor_view;
                  selectable;
                  show_cursor;
                  text_color;
                  background_color;
                  selection_bg;
                  selection_fg;
                  cursor_color;
                  cursor_style;
                  scroll_margin = max 0.0 scroll_margin;
                  scroll_speed = max 0.0 scroll_speed;
                  traits = { capture = []; suspend = false; status = None };
                  keymap = Lib.Keybinding.create (key_bindings @ default_bindings);
                  cursor_events = Event_kernel.create ();
                  content_events = Event_kernel.create ();
                  submit_events = Event_kernel.create ();
                  traits_events = Event_kernel.create ();
                  last_viewport = initial_viewport;
                  destroyed = false;
                }
              in
              let cleanup () =
                if not editor.destroyed then begin
                  editor.destroyed <- true;
                  Editor_view.destroy editor.editor_view;
                  Edit_buffer.destroy editor.edit_buffer;
                  Event_kernel.clear editor.cursor_events;
                  Event_kernel.clear editor.content_events;
                  Event_kernel.clear editor.submit_events;
                  Event_kernel.clear editor.traits_events
                end
              in
              let on_change _ =
                sync_text editor;
                ignore (Event_kernel.emit editor.content_events ());
                after_edit editor
              in
              ignore (Edit_buffer.on_change edit_buffer on_change);
              let cursor_behavior =
                Renderable.Private.make_behavior
                  ~render_self:(fun cursor buffer _delta ->
                    let foreground = editor.cursor_color in
                    let character =
                      match editor.cursor_style with
                      | Block -> 0x2588
                      | Underline -> Char.code '_'
                      | Bar -> 0x258e
                    in
                    Buffer.set_cell buffer
                      ~x:(Int32.of_float (Renderable.screen_x cursor))
                      ~y:(Int32.of_float (Renderable.screen_y cursor))
                      ~character:(Int32.of_int character) ~foreground
                      ~background:editor.background_color ~attributes:0l)
                  ~destroy_self:(fun _ -> ()) ()
              in
              Renderable.Private.set_behavior cursor_renderable cursor_behavior;
              let behavior =
                Renderable.Private.make_behavior
                  ~on_update:(update_cursor_render editor)
                  ~on_resize:(fun _ ~width ~height ->
                    Editor_view.set_viewport_size editor.editor_view ~width ~height;
                    sync_viewport editor)
                  ~key_press:(fun _ event -> ignore (handle_key_press editor event))
                  ~paste:(fun _ event -> handle_paste editor event)
                  ~mouse_event:(fun _ event ->
                    match Renderable.mouse_kind event with
                    | Renderable.Scroll ->
                        Option.iter (handle_scroll editor) (Renderable.mouse_scroll event)
                    | _ -> ())
                  ~selection_changed:(fun _ selection ->
                    sync_pointer_selection editor selection;
                    ignore (request_render editor))
                  ~selected_text:(fun _ ->
                    Result.bind (ensure_alive editor) (fun () ->
                        Editor_view.selected_text editor.editor_view))
                  ~should_start_selection:(fun _ ~x ~y ->
                    editor.selectable
                    && x >= int_of_float (Renderable.screen_x renderable)
                    && y >= int_of_float (Renderable.screen_y renderable)
                    && x < int_of_float (Renderable.screen_x renderable +. Renderable.width renderable)
                    && y < int_of_float (Renderable.screen_y renderable +. Renderable.height renderable))
                  ~destroy_self:(fun _ ->
                    Text_buffer_renderable.destroy editor.text_renderable;
                    Renderable.destroy editor.cursor_renderable;
                    cleanup ())
                  ()
              in
              Renderable.Private.set_behavior renderable behavior;
              let style_result =
                let result = Renderable.set_focusable renderable focusable in
                let result =
                  Result.bind result (fun () ->
                      Renderable.set_flex_direction renderable Yoga.Flex_column)
                in
                let result =
                  Result.bind result (fun () ->
                      Renderable.set_width (Text_buffer_renderable.as_renderable text_renderable)
                        (Yoga.Percent 100.0))
                in
                let result =
                  Result.bind result (fun () ->
                      Renderable.set_flex_grow (Text_buffer_renderable.as_renderable text_renderable) (Some 1.0))
                in
                let result =
                  Result.bind result (fun () ->
                      Renderable.set_position_type cursor_renderable
                        Yoga.Position_absolute)
                in
                let result =
                  Result.bind result (fun () ->
                      Renderable.set_width cursor_renderable (Yoga.Point 1.0))
                in
                let result =
                  Result.bind result (fun () ->
                      Renderable.set_height cursor_renderable (Yoga.Point 1.0))
                in
                let result =
                  match width with
                  | None -> result
                  | Some value -> Result.bind result (fun () -> Renderable.set_width renderable value)
                in
                match height with
                | None -> result
                | Some value -> Result.bind result (fun () -> Renderable.set_height renderable value)
              in
              (match style_result with
              | Error error ->
                  Renderable.destroy_recursively renderable;
                  cleanup ();
                  Error error
              | Ok () ->
                  (match
                     Renderable.Private.attach ~parent:renderable
                       ~child:(Text_buffer_renderable.as_renderable text_renderable)
                       ~index:0
                   with
                  | Error error ->
                      Renderable.destroy_recursively renderable;
                      cleanup ();
                      Error error
                  | Ok _ ->
                      (match
                         Renderable.Private.attach ~parent:renderable
                           ~child:cursor_renderable ~index:1
                       with
                      | Error error ->
                          Renderable.destroy_recursively renderable;
                          cleanup ();
                          Error error
                      | Ok _ ->
                          ignore (Text_buffer_renderable.set_default_fg text_renderable (Some text_color));
                          ignore (Text_buffer_renderable.set_default_bg text_renderable (Some background_color));
                          ignore (Text_buffer_renderable.set_default_attributes text_renderable (Some attributes));
                          (match initial_text with
                          | None -> ()
                          | Some value -> ignore (Edit_buffer.set_text edit_buffer value));
                          sync_text editor;
                          ignore
                            (match tab_indicator with
                            | None -> Ok ()
                            | Some value -> Text_buffer_renderable.set_tab_indicator text_renderable value);
                          ignore
                            (match tab_indicator_color with
                            | None -> Ok ()
                            | Some value -> Text_buffer_renderable.set_tab_indicator_color text_renderable value);
                          Ok editor)))))

let as_renderable editor = editor.renderable
let text_renderable editor = editor.text_renderable
let edit_buffer editor = editor.edit_buffer
let editor_view editor = editor.editor_view

let text editor = Result.bind (ensure_alive editor) (fun () -> Edit_buffer.text editor.edit_buffer)

let set_text editor value =
  Result.bind (ensure_alive editor) (fun () -> Edit_buffer.set_text editor.edit_buffer value)

let replace_text editor value =
  Result.bind (ensure_alive editor) (fun () -> Edit_buffer.replace_text editor.edit_buffer value)

let clear editor = run_edit editor (fun () -> Edit_buffer.clear editor.edit_buffer)
let insert_text editor value = insert_text_impl editor value
let insert_char editor value = insert_text_impl editor value
let new_line editor = run_edit editor (fun () -> Edit_buffer.new_line editor.edit_buffer)
let delete_char editor = run_edit editor (fun () -> Edit_buffer.delete_char editor.edit_buffer)
let delete_char_backward editor = run_edit editor (fun () -> Edit_buffer.delete_char_backward editor.edit_buffer)
let delete_line editor = run_edit editor (fun () -> Edit_buffer.delete_line editor.edit_buffer)

let delete_to_line_start editor = action editor Delete_to_line_start
let delete_to_line_end editor = action editor Delete_to_line_end
let delete_word_forward editor = action editor Delete_word_forward
let delete_word_backward editor = action editor Delete_word_backward
let undo editor = undo_impl editor
let redo editor = redo_impl editor

let move_cursor_left editor ?(select = false) () = action editor (if select then Select_left else Move_left)
let move_cursor_right editor ?(select = false) () = action editor (if select then Select_right else Move_right)
let move_cursor_up editor ?(select = false) () = action editor (if select then Select_up else Move_up)
let move_cursor_down editor ?(select = false) () = action editor (if select then Select_down else Move_down)
let move_word_forward editor ?(select = false) () = action editor (if select then Select_word_forward else Word_forward)
let move_word_backward editor ?(select = false) () = action editor (if select then Select_word_backward else Word_backward)
let goto_line_home editor ?(select = false) () = action editor (if select then Select_line_home else Line_home)
let goto_line_end editor ?(select = false) () = action editor (if select then Select_line_end else Line_end)
let goto_visual_line_home editor ?(select = false) () = action editor (if select then Select_visual_line_home else Visual_line_home)
let goto_visual_line_end editor ?(select = false) () = action editor (if select then Select_visual_line_end else Visual_line_end)
let goto_buffer_home editor ?(select = false) () = action editor (if select then Select_buffer_home else Buffer_home)
let goto_buffer_end editor ?(select = false) () = action editor (if select then Select_buffer_end else Buffer_end)
let goto_line_start editor =
  Result.bind (ensure_alive editor) (fun () ->
      Result.bind (Edit_buffer.cursor editor.edit_buffer) (fun cursor ->
          Result.bind
            (Edit_buffer.set_cursor editor.edit_buffer ~line:cursor.row ~col:0)
            (fun () ->
              after_edit editor;
              Ok ())))

let goto_line_text_end editor =
  Result.bind (ensure_alive editor) (fun () ->
      Result.bind (Edit_buffer.eol editor.edit_buffer) (fun cursor ->
          Result.bind
            (Edit_buffer.set_cursor_by_offset editor.edit_buffer cursor.offset)
            (fun () ->
              after_edit editor;
              Ok ())))

let goto_line editor line =
  Result.bind (ensure_alive editor) (fun () ->
      Result.bind (Edit_buffer.goto_line editor.edit_buffer line) (fun () ->
          after_edit editor;
          Ok ()))

let cursor editor =
  Result.bind (ensure_alive editor) (fun () -> Edit_buffer.cursor editor.edit_buffer)

let visual_cursor editor =
  Result.bind (ensure_alive editor) (fun () -> Editor_view.visual_cursor editor.editor_view)

let set_cursor editor ~line ~col =
  Result.bind (ensure_alive editor) (fun () ->
      Result.bind (Edit_buffer.set_cursor editor.edit_buffer ~line ~col) (fun () ->
          after_edit editor;
          Ok ()))

let set_cursor_by_offset editor offset =
  Result.bind (ensure_alive editor) (fun () ->
      Result.bind (Edit_buffer.set_cursor_by_offset editor.edit_buffer offset) (fun () ->
          after_edit editor;
          Ok ()))

let select_all editor = action editor Select_all

let set_selection editor ~start ~end_ =
  Result.bind (ensure_alive editor) (fun () ->
      if start < 0 || end_ < 0 then Error Error.Invalid_argument
      else begin
        Editor_view.reset_local_selection editor.editor_view;
        Editor_view.set_selection editor.editor_view ~start ~end_;
        sync_native_selection editor;
        request_render editor
      end)

let set_selection_inclusive editor ~start ~end_ =
  let left = Int.min start end_ in
  let right = Int.max start end_ in
  set_selection editor ~start:left ~end_:(right + 1)

let clear_selection editor =
  Result.bind (ensure_alive editor) (fun () ->
      let had = Editor_view.has_selection editor.editor_view in
      Editor_view.reset_selection editor.editor_view;
      Editor_view.reset_local_selection editor.editor_view;
      ignore (Text_buffer_renderable.reset_selection editor.text_renderable);
      ignore (Text_buffer_renderable.reset_local_selection editor.text_renderable);
      Result.map (fun () -> had) (request_render editor))

let delete_selection editor =
  Result.bind (ensure_alive editor) (fun () ->
      if not (Option.is_some (selected_range editor)) then Ok false
      else
        Result.bind (Editor_view.delete_selected_text editor.editor_view) (fun () ->
            Editor_view.reset_selection editor.editor_view;
            after_edit editor;
            Ok true))

let selection editor = Editor_view.selected_range editor.editor_view
let has_selection editor = Editor_view.has_selection editor.editor_view
let selected_text editor = Result.bind (ensure_alive editor) (fun () -> Editor_view.selected_text editor.editor_view)
let line_count editor = Edit_buffer.line_count editor.edit_buffer
let line_info editor = Editor_view.line_info editor.editor_view
let logical_line_info editor = Editor_view.logical_line_info editor.editor_view
let virtual_line_count editor = Editor_view.virtual_line_count editor.editor_view
let scroll_y editor = (Editor_view.viewport editor.editor_view).offset_y

let set_viewport editor ~x ~y ~width ~height =
  Editor_view.set_viewport editor.editor_view ~x ~y ~width ~height ();
  sync_viewport editor;
  ignore (request_render editor)

let viewport editor = Editor_view.viewport editor.editor_view
let selectable editor = editor.selectable

let set_selectable editor value =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () -> editor.selectable <- value; Ok ()

let show_cursor editor = editor.show_cursor

let set_show_cursor editor value =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () -> editor.show_cursor <- value; update_cursor editor; request_render editor

let cursor_style editor = editor.cursor_style

let set_cursor_style editor value =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () -> editor.cursor_style <- value; request_render editor

let cursor_color editor = editor.cursor_color

let set_cursor_color editor value =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () -> editor.cursor_color <- value; request_render editor

let text_color editor = editor.text_color

let set_text_color editor value =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () ->
      editor.text_color <- value;
      Text_buffer_renderable.set_default_fg editor.text_renderable (Some value)

let background_color editor = editor.background_color

let set_background_color editor value =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () ->
      editor.background_color <- value;
      Text_buffer_renderable.set_default_bg editor.text_renderable (Some value)

let selection_bg editor = editor.selection_bg

let set_selection_bg editor value =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () -> editor.selection_bg <- value; sync_native_selection editor; request_render editor

let selection_fg editor = editor.selection_fg

let set_selection_fg editor value =
  match ensure_alive editor with
  | Error error -> Error error
  | Ok () -> editor.selection_fg <- value; sync_native_selection editor; request_render editor

let set_wrap_mode editor mode =
  Result.bind (ensure_alive editor) (fun () ->
      Editor_view.set_wrap_mode editor.editor_view
        (match mode with
        | Text_buffer_view.No_wrap -> Editor_view.No_wrap
        | Char -> Editor_view.Char
        | Word -> Editor_view.Word);
      Text_buffer_renderable.set_wrap_mode editor.text_renderable mode)

let wrap_mode editor = Text_buffer_renderable.wrap_mode editor.text_renderable
let set_scroll_margin editor value = editor.scroll_margin <- max 0.0 value
let scroll_margin editor = editor.scroll_margin
let set_scroll_speed editor value = editor.scroll_speed <- max 0.0 value
let scroll_speed editor = editor.scroll_speed
let traits editor = editor.traits

let equal_traits left right =
  Bool.equal left.suspend right.suspend
  && Option.equal String.equal left.status right.status
  && List.length left.capture = List.length right.capture
  && List.for_all2
       (fun left_capture right_capture ->
         match left_capture, right_capture with
         | Escape, Escape | Navigate, Navigate | Submit, Submit | Tab, Tab -> true
         | Escape, _ | Navigate, _ | Submit, _ | Tab, _ -> false)
       left.capture right.capture

let set_traits editor value =
  if not (equal_traits editor.traits value) then begin
    editor.traits <- value;
    ignore (Event_kernel.emit editor.traits_events value)
  end

let set_key_bindings editor bindings = Lib.Keybinding.set_bindings editor.keymap (bindings @ default_bindings)
let on_cursor_change editor callback = Event_kernel.on editor.cursor_events callback
let on_content_change editor callback = Event_kernel.on editor.content_events callback
let on_submit_action editor callback = Event_kernel.on editor.submit_events callback
let on_traits_change editor callback = Event_kernel.on editor.traits_events callback

let destroy editor =
  if not editor.destroyed then Renderable.destroy_recursively editor.renderable
