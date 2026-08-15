type action = Textarea.action
type key_binding = Textarea.key_binding

type t = {
  textarea : Textarea.t;
  keymap : action Lib.Keybinding.t;
  mutable min_length : int;
  mutable max_length : int;
  mutable last_committed : string;
  input_events : string Event_kernel.t;
  change_events : string Event_kernel.t;
  enter_events : string Event_kernel.t;
  mutable destroyed : bool;
}

let ensure_alive input =
  if input.destroyed || Renderable.is_destroyed (Textarea.as_renderable input.textarea)
  then Error Error.Destroyed
  else Ok ()

let remove_newlines value =
  let output = Stdlib.Buffer.create (String.length value) in
  String.iter
    (fun character ->
      if not (Char.equal character '\n' || Char.equal character '\r') then
        Stdlib.Buffer.add_char output character)
    value;
  Stdlib.Buffer.contents output

let truncate value length =
  if String.length value <= length then value else String.sub value 0 length

let emit_input input =
  match Textarea.value input.textarea with
  | Ok value -> ignore (Event_kernel.emit input.input_events value)
  | Error _ -> ()

let current_value input = Textarea.value input.textarea

let submit_bindings =
  [
    Lib.Keybinding.binding ~name:"return"
      ~action:(Edit_buffer_renderable.Submit : Textarea.action) ();
    Lib.Keybinding.binding ~name:"kpenter"
      ~action:(Edit_buffer_renderable.Submit : Textarea.action) ();
    Lib.Keybinding.binding ~name:"linefeed"
      ~action:(Edit_buffer_renderable.Submit : Textarea.action) ();
  ]

let selected_width input =
  match Edit_buffer_renderable.selection (Textarea.editor input.textarea) with
  | None -> 0
  | Some (start, finish) -> max 0 (finish - start)

let insert_sanitized input value =
  match ensure_alive input with
  | Error error -> Error error
  | Ok () ->
      let value = remove_newlines value in
      if String.length value = 0 then Ok ()
      else
        let current_length =
          match current_value input with Ok current -> String.length current | Error _ -> 0
        in
        let available = input.max_length - current_length + selected_width input in
        if available <= 0 then Ok ()
        else
          let value = truncate value available in
          Result.bind (Textarea.insert_text input.textarea value) (fun () ->
              emit_input input;
              Ok ())

let set_value input value =
  Result.bind (ensure_alive input) (fun () ->
      let value = truncate (remove_newlines value) input.max_length in
      Result.bind (current_value input) (fun previous ->
          if String.equal previous value then Ok ()
          else
            Result.bind (Textarea.set_text input.textarea value) (fun () ->
                ignore
                  (Edit_buffer_renderable.goto_buffer_end
                     (Textarea.editor input.textarea) ());
                emit_input input;
                Ok ())))

let commit_changed input value =
  if not (String.equal value input.last_committed) then begin
    input.last_committed <- value;
    ignore (Event_kernel.emit input.change_events value)
  end

let commit input =
  match current_value input with
  | Error error -> Error error
  | Ok value ->
      if String.length value < input.min_length then Error Error.Invalid_argument
      else begin
        commit_changed input value;
        Ok ()
      end

let delegate_key_press input event =
  let before = current_value input in
  let handled = Textarea.handle_key_press input.textarea event in
  if handled then begin
    match before, current_value input with
    | Ok before, Ok after when not (String.equal before after) -> emit_input input
    | _ -> ()
  end;
  handled

let submit input =
  Result.bind (ensure_alive input) (fun () ->
      Result.bind (commit input) (fun () ->
          match current_value input with
          | Error error -> Error error
          | Ok value ->
              ignore (Event_kernel.emit input.enter_events value);
              Ok ()))

let handle_key_press input event =
  match Lib.Key_handler.key event with
  | Lib.Key_decoder.Named Lib.Key_decoder.Return
  | Lib.Key_decoder.Named Lib.Key_decoder.Linefeed ->
      if String.length (Result.value (current_value input) ~default:"")
         < input.min_length
      then false
      else begin
        Lib.Key_handler.prevent_default event;
        ignore (submit input);
        true
      end
  | Lib.Key_decoder.Character bytes ->
      let modifiers = Lib.Key_handler.key_modifiers event in
      if modifiers.ctrl || modifiers.meta
         || Option.is_some (Lib.Keybinding.action input.keymap event)
      then delegate_key_press input event
      else begin
        Lib.Key_handler.prevent_default event;
        ignore (insert_sanitized input (Bytes.to_string bytes));
        true
      end
  | Lib.Key_decoder.Named Lib.Key_decoder.Space ->
      let modifiers = Lib.Key_handler.key_modifiers event in
      if modifiers.ctrl || modifiers.meta
         || Option.is_some (Lib.Keybinding.action input.keymap event)
      then delegate_key_press input event
      else begin
        Lib.Key_handler.prevent_default event;
        ignore (insert_sanitized input " ");
        true
      end
  | Lib.Key_decoder.Named _ ->
      delegate_key_press input event

let handle_paste input event =
  Lib.Key_handler.paste_prevent_default event;
  let value =
    Lib.Paste.strip_ansi (Lib.Paste.decode (Lib.Key_handler.paste_raw event))
  in
  ignore (insert_sanitized input value)

let create context ?id ?(value = "") ?placeholder ?placeholder_color
    ?background_color ?text_color ?focused_background_color ?focused_text_color
    ?selection_bg ?selection_fg ?(min_length = 0) ?(max_length = 1000)
    ?(focusable = true) ?cursor_color ?cursor_style ?(key_bindings = [])
    ?on_input ?on_change ?on_enter () =
  if min_length < 0 || max_length < 0 || min_length > max_length then
    Error Error.Invalid_argument
  else
    let initial_value = truncate (remove_newlines value) max_length in
    let input_owner = ref None in
    match
      Textarea.create context ?id ~initial_value ?placeholder ?placeholder_color
        ?background_color ?text_color ?focused_background_color
        ?focused_text_color ?selection_bg ?selection_fg
        ~wrap_mode:Text_buffer_view.No_wrap ~show_cursor:true ?cursor_color
        ?cursor_style ~focusable ~height:(Yoga.Point 1.0)
        ~key_bindings:(key_bindings @ submit_bindings)
        ~on_submit:(fun () ->
          Option.iter (fun input -> ignore (submit input)) !input_owner)
        ()
    with
    | Error error -> Error error
    | Ok textarea ->
        let input =
          {
            textarea;
            keymap = Lib.Keybinding.create (key_bindings @ submit_bindings);
            min_length;
            max_length;
            last_committed = initial_value;
            input_events = Event_kernel.create ();
            change_events = Event_kernel.create ();
            enter_events = Event_kernel.create ();
            destroyed = false;
          }
        in
        ignore
          (Renderable.on_focused (Textarea.as_renderable textarea) (fun () ->
               match current_value input with
               | Ok value -> input.last_committed <- value
               | Error _ -> ()));
        ignore
          (Renderable.on_blurred (Textarea.as_renderable textarea) (fun () ->
               match current_value input with
               | Ok value -> commit_changed input value
               | Error _ -> ()));
        Option.iter
          (fun callback -> ignore (Event_kernel.on input.input_events callback))
          on_input;
        Option.iter
          (fun callback -> ignore (Event_kernel.on input.change_events callback))
          on_change;
        Option.iter
          (fun callback -> ignore (Event_kernel.on input.enter_events callback))
          on_enter;
        let result =
          Renderable.set_on_key_down (Textarea.as_renderable textarea)
            (Some (fun event -> ignore (handle_key_press input event)))
        in
        let result =
          Result.bind result (fun () ->
              Renderable.set_on_paste (Textarea.as_renderable textarea)
                (Some (fun event -> handle_paste input event)))
        in
        (match result with
        | Error error ->
            Textarea.destroy textarea;
            Error error
        | Ok () ->
            input_owner := Some input;
            (match Edit_buffer_renderable.goto_buffer_end
                     (Textarea.editor textarea) () with
            | Error error ->
                Textarea.destroy textarea;
                Error error
            | Ok () -> Ok input))

let as_renderable input = Textarea.as_renderable input.textarea
let textarea input = input.textarea
let value input = Textarea.value input.textarea
let text = value
let set_text = set_value

let clear input = set_value input ""
let insert_text = insert_sanitized
let insert_char = insert_sanitized
let new_line input =
  Result.bind (ensure_alive input) (fun () -> Ok ())

let edit_and_emit input operation =
  Result.bind (ensure_alive input) (fun () ->
      Result.bind (operation ()) (fun () ->
          emit_input input;
          Ok ()))

let delete_char input =
  edit_and_emit input (fun () -> Textarea.delete_char input.textarea)

let delete_char_backward input =
  edit_and_emit input (fun () -> Textarea.delete_char_backward input.textarea)

let delete_line input = edit_and_emit input (fun () -> Textarea.delete_line input.textarea)
let delete_to_line_start input =
  edit_and_emit input (fun () -> Textarea.delete_to_line_start input.textarea)
let delete_to_line_end input =
  edit_and_emit input (fun () -> Textarea.delete_to_line_end input.textarea)
let delete_word_forward input =
  edit_and_emit input (fun () -> Textarea.delete_word_forward input.textarea)
let delete_word_backward input =
  edit_and_emit input (fun () -> Textarea.delete_word_backward input.textarea)

let undo input =
  Result.bind (ensure_alive input) (fun () ->
      Result.bind (Textarea.undo input.textarea) (fun value ->
          emit_input input;
          Ok value))

let redo input =
  Result.bind (ensure_alive input) (fun () ->
      Result.bind (Textarea.redo input.textarea) (fun value ->
          emit_input input;
          Ok value))

let delete_selection input =
  Result.bind (ensure_alive input) (fun () ->
      Result.bind (Textarea.delete_selection input.textarea) (fun deleted ->
          if deleted then emit_input input;
          Ok deleted))

let selected_text input = Textarea.selected_text input.textarea
let has_selection input = Textarea.has_selection input.textarea
let selection input = Textarea.selection input.textarea
let set_selection input ~start ~end_ =
  Textarea.set_selection input.textarea ~start ~end_
let set_selection_inclusive input ~start ~end_ =
  Textarea.set_selection_inclusive input.textarea ~start ~end_
let clear_selection input = Textarea.clear_selection input.textarea
let move_cursor_left input ?select () = Textarea.move_cursor_left input.textarea ?select ()
let move_cursor_right input ?select () = Textarea.move_cursor_right input.textarea ?select ()
let move_cursor_up input ?select () = Textarea.move_cursor_up input.textarea ?select ()
let move_cursor_down input ?select () = Textarea.move_cursor_down input.textarea ?select ()
let move_word_forward input ?select () = Textarea.move_word_forward input.textarea ?select ()
let move_word_backward input ?select () = Textarea.move_word_backward input.textarea ?select ()
let goto_line_home input ?select () = Textarea.goto_line_home input.textarea ?select ()
let goto_line_end input ?select () = Textarea.goto_line_end input.textarea ?select ()
let goto_visual_line_home input ?select () = Textarea.goto_visual_line_home input.textarea ?select ()
let goto_visual_line_end input ?select () = Textarea.goto_visual_line_end input.textarea ?select ()
let goto_buffer_home input ?select () = Textarea.goto_buffer_home input.textarea ?select ()
let goto_buffer_end input ?select () = Textarea.goto_buffer_end input.textarea ?select ()
let goto_line_start input = Textarea.goto_line_start input.textarea
let goto_line_text_end input = Textarea.goto_line_text_end input.textarea
let goto_line input line = Textarea.goto_line input.textarea line
let cursor input = Textarea.cursor input.textarea
let visual_cursor input = Textarea.visual_cursor input.textarea
let set_cursor input ~line ~col = Textarea.set_cursor input.textarea ~line ~col
let set_cursor_by_offset input offset = Textarea.set_cursor_by_offset input.textarea offset
let select_all input = Textarea.select_all input.textarea
let line_count input = Textarea.line_count input.textarea
let line_info input = Textarea.line_info input.textarea
let logical_line_info input = Textarea.logical_line_info input.textarea
let virtual_line_count input = Textarea.virtual_line_count input.textarea
let scroll_y input = Textarea.scroll_y input.textarea
let viewport input = Textarea.viewport input.textarea
let set_viewport input ~x ~y ~width ~height =
  Textarea.set_viewport input.textarea ~x ~y ~width ~height
let show_cursor input = Textarea.show_cursor input.textarea
let set_show_cursor input value = Textarea.set_show_cursor input.textarea value
let cursor_style input = Textarea.cursor_style input.textarea
let set_cursor_style input value = Textarea.set_cursor_style input.textarea value
let cursor_color input = Textarea.cursor_color input.textarea
let set_cursor_color input value = Textarea.set_cursor_color input.textarea value
let selection_bg input = Textarea.selection_bg input.textarea
let set_selection_bg input value = Textarea.set_selection_bg input.textarea value
let selection_fg input = Textarea.selection_fg input.textarea
let set_selection_fg input value = Textarea.set_selection_fg input.textarea value
let wrap_mode input = Textarea.wrap_mode input.textarea
let set_wrap_mode input value = Textarea.set_wrap_mode input.textarea value
let scroll_margin input = Textarea.scroll_margin input.textarea
let set_scroll_margin input value = Textarea.set_scroll_margin input.textarea value
let scroll_speed input = Textarea.scroll_speed input.textarea
let set_scroll_speed input value = Textarea.set_scroll_speed input.textarea value
let set_key_bindings input bindings =
  Textarea.set_key_bindings input.textarea (bindings @ submit_bindings);
  Lib.Keybinding.set_bindings input.keymap (bindings @ submit_bindings)
let min_length input = input.min_length
let max_length input = input.max_length

let set_min_length input value =
  Result.bind (ensure_alive input) (fun () ->
      if value < 0 || value > input.max_length then Error Error.Invalid_argument
      else (input.min_length <- value; Ok ()))

let set_max_length input value =
  Result.bind (ensure_alive input) (fun () ->
      if value < input.min_length || value < 0 then Error Error.Invalid_argument
      else begin
        input.max_length <- value;
        match current_value input with
        | Error error -> Error error
        | Ok current when String.length current <= value -> Ok ()
        | Ok current -> set_value input (String.sub current 0 value)
      end)

let focused input = Textarea.focused input.textarea

let focus input =
  match ensure_alive input with
  | Error error -> Error error
  | Ok () ->
      (match Textarea.focus input.textarea with
      | Error error -> Error error
      | Ok () ->
          Result.bind (current_value input) (fun value ->
              input.last_committed <- value;
              Ok ()))

let blur input =
  Result.bind (ensure_alive input) (fun () ->
      Result.bind (current_value input) (fun value ->
          commit_changed input value;
          Textarea.blur input.textarea))

let on_input input callback = Event_kernel.on input.input_events callback
let on_change input callback = Event_kernel.on input.change_events callback
let on_enter input callback = Event_kernel.on input.enter_events callback

let destroy input =
  if not input.destroyed then begin
    input.destroyed <- true;
    Event_kernel.clear input.input_events;
    Event_kernel.clear input.change_events;
    Event_kernel.clear input.enter_events;
    Textarea.destroy input.textarea
  end
