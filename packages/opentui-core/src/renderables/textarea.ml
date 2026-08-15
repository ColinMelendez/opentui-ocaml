type action = Edit_buffer_renderable.action
type key_binding = Edit_buffer_renderable.key_binding
type cursor_style = Edit_buffer_renderable.cursor_style

type t = {
  editor : Edit_buffer_renderable.t;
  mutable placeholder : string option;
  mutable placeholder_color : Color.t;
  mutable background_color : Color.t;
  mutable text_color : Color.t;
  mutable focused_background_color : Color.t;
  mutable focused_text_color : Color.t;
  submit_events : unit Event_kernel.t;
  mutable destroyed : bool;
}

let gray =
  match Color.rgba ~red:102 ~green:102 ~blue:102 ~alpha:255 with
  | Ok color -> color
  | Error _ -> Color.white

let default_text_color = Color.white
let default_background_color = Color.transparent

let ensure_alive textarea =
  if textarea.destroyed || Renderable.is_destroyed (Edit_buffer_renderable.as_renderable textarea.editor)
  then Error Error.Destroyed
  else Ok ()

let effective_colors textarea =
  if Renderable.focused (Edit_buffer_renderable.as_renderable textarea.editor) then
    textarea.focused_text_color, textarea.focused_background_color
  else textarea.text_color, textarea.background_color

let refresh_placeholder textarea =
  match Edit_buffer_renderable.text textarea.editor with
  | Error _ -> ()
  | Ok text ->
      let child = Edit_buffer_renderable.text_renderable textarea.editor in
      if String.length text = 0 then begin
        (match textarea.placeholder with
        | None ->
            ignore (Text_buffer_renderable.set_text child "")
        | Some placeholder ->
            ignore (Text_buffer_renderable.set_text child placeholder));
        ignore (Text_buffer_renderable.set_default_fg child (Some textarea.placeholder_color))
      end else begin
        ignore (Text_buffer_renderable.set_text child text);
        let foreground, background = effective_colors textarea in
        ignore (Text_buffer_renderable.set_default_fg child (Some foreground));
        ignore (Text_buffer_renderable.set_default_bg child (Some background))
      end

let update_colors textarea =
  let foreground, background = effective_colors textarea in
  ignore (Edit_buffer_renderable.set_text_color textarea.editor foreground);
  ignore (Edit_buffer_renderable.set_background_color textarea.editor background);
  refresh_placeholder textarea

let create context ?id ?initial_value ?placeholder ?(placeholder_color = gray)
    ?(background_color = default_background_color) ?(text_color = default_text_color)
    ?focused_background_color ?focused_text_color ?selection_bg ?selection_fg
    ?(wrap_mode = Text_buffer_view.Word) ?(selectable = true) ?(attributes = 0)
    ?(scroll_margin = 0.2) ?(scroll_speed = 16.0) ?(show_cursor = true)
    ?(cursor_color = default_text_color) ?(cursor_style = Edit_buffer_renderable.Block)
    ?tab_indicator ?tab_indicator_color ?(focusable = true) ?width ?height
    ?(key_bindings = []) ?on_submit () =
  let focused_background_color =
    Option.value focused_background_color ~default:background_color
  in
  let focused_text_color = Option.value focused_text_color ~default:text_color in
  match
    Edit_buffer_renderable.create context ?id ?initial_text:initial_value
      ~text_color ~background_color ?selection_bg ?selection_fg ~wrap_mode
      ~selectable ~attributes ~scroll_margin ~scroll_speed ~show_cursor
      ~cursor_color ~cursor_style ?tab_indicator ?tab_indicator_color ~focusable
      ?width ?height ~key_bindings ()
  with
  | Error error -> Error error
  | Ok editor ->
      let textarea =
        {
          editor;
          placeholder;
          placeholder_color;
          background_color;
          text_color;
          focused_background_color;
          focused_text_color;
          submit_events = Event_kernel.create ();
          destroyed = false;
        }
      in
      ignore
        (Edit_buffer_renderable.on_content_change editor (fun () ->
             refresh_placeholder textarea));
      ignore
        (Edit_buffer_renderable.on_submit_action editor (fun () ->
             ignore (Event_kernel.emit textarea.submit_events ())));
      ignore
        (Renderable.on_focused (Edit_buffer_renderable.as_renderable editor)
           (fun () -> update_colors textarea));
      ignore
        (Renderable.on_blurred (Edit_buffer_renderable.as_renderable editor)
           (fun () -> update_colors textarea));
      update_colors textarea;
      Option.iter
        (fun callback -> ignore (Event_kernel.on textarea.submit_events callback))
        on_submit;
      Ok textarea

let as_renderable textarea = Edit_buffer_renderable.as_renderable textarea.editor
let editor textarea = textarea.editor
let text textarea = Edit_buffer_renderable.text textarea.editor
let value textarea = text textarea
let set_text textarea value =
  Result.bind (ensure_alive textarea) (fun () ->
      Result.bind (Edit_buffer_renderable.set_text textarea.editor value) (fun () ->
          refresh_placeholder textarea;
          Ok ()))
let replace_text textarea value = Edit_buffer_renderable.replace_text textarea.editor value
let clear textarea = Edit_buffer_renderable.clear textarea.editor
let insert_text textarea value = Edit_buffer_renderable.insert_text textarea.editor value
let insert_char textarea value = Edit_buffer_renderable.insert_char textarea.editor value
let new_line textarea = Edit_buffer_renderable.new_line textarea.editor
let delete_char textarea = Edit_buffer_renderable.delete_char textarea.editor
let delete_char_backward textarea = Edit_buffer_renderable.delete_char_backward textarea.editor
let delete_line textarea = Edit_buffer_renderable.delete_line textarea.editor
let delete_to_line_start textarea = Edit_buffer_renderable.delete_to_line_start textarea.editor
let delete_to_line_end textarea = Edit_buffer_renderable.delete_to_line_end textarea.editor
let delete_word_forward textarea = Edit_buffer_renderable.delete_word_forward textarea.editor
let delete_word_backward textarea = Edit_buffer_renderable.delete_word_backward textarea.editor
let undo textarea = Edit_buffer_renderable.undo textarea.editor
let redo textarea = Edit_buffer_renderable.redo textarea.editor
let delete_selection textarea = Edit_buffer_renderable.delete_selection textarea.editor
let selected_text textarea = Edit_buffer_renderable.selected_text textarea.editor
let has_selection textarea = Edit_buffer_renderable.has_selection textarea.editor
let selection textarea = Edit_buffer_renderable.selection textarea.editor
let set_selection textarea ~start ~end_ = Edit_buffer_renderable.set_selection textarea.editor ~start ~end_
let set_selection_inclusive textarea ~start ~end_ =
  Edit_buffer_renderable.set_selection_inclusive textarea.editor ~start ~end_
let clear_selection textarea = Edit_buffer_renderable.clear_selection textarea.editor
let move_cursor_left textarea ?select () = Edit_buffer_renderable.move_cursor_left textarea.editor ?select ()
let move_cursor_right textarea ?select () = Edit_buffer_renderable.move_cursor_right textarea.editor ?select ()
let move_cursor_up textarea ?select () = Edit_buffer_renderable.move_cursor_up textarea.editor ?select ()
let move_cursor_down textarea ?select () = Edit_buffer_renderable.move_cursor_down textarea.editor ?select ()
let move_word_forward textarea ?select () = Edit_buffer_renderable.move_word_forward textarea.editor ?select ()
let move_word_backward textarea ?select () = Edit_buffer_renderable.move_word_backward textarea.editor ?select ()
let goto_line_home textarea ?select () = Edit_buffer_renderable.goto_line_home textarea.editor ?select ()
let goto_line_end textarea ?select () = Edit_buffer_renderable.goto_line_end textarea.editor ?select ()
let goto_visual_line_home textarea ?select () = Edit_buffer_renderable.goto_visual_line_home textarea.editor ?select ()
let goto_visual_line_end textarea ?select () = Edit_buffer_renderable.goto_visual_line_end textarea.editor ?select ()
let goto_buffer_home textarea ?select () = Edit_buffer_renderable.goto_buffer_home textarea.editor ?select ()
let goto_buffer_end textarea ?select () = Edit_buffer_renderable.goto_buffer_end textarea.editor ?select ()
let goto_line_start textarea = Edit_buffer_renderable.goto_line_start textarea.editor
let goto_line_text_end textarea = Edit_buffer_renderable.goto_line_text_end textarea.editor
let goto_line textarea line = Edit_buffer_renderable.goto_line textarea.editor line
let cursor textarea = Edit_buffer_renderable.cursor textarea.editor
let visual_cursor textarea = Edit_buffer_renderable.visual_cursor textarea.editor
let set_cursor textarea ~line ~col = Edit_buffer_renderable.set_cursor textarea.editor ~line ~col
let set_cursor_by_offset textarea offset =
  Edit_buffer_renderable.set_cursor_by_offset textarea.editor offset
let select_all textarea = Edit_buffer_renderable.select_all textarea.editor
let line_count textarea = Edit_buffer_renderable.line_count textarea.editor
let line_info textarea = Edit_buffer_renderable.line_info textarea.editor
let logical_line_info textarea = Edit_buffer_renderable.logical_line_info textarea.editor
let virtual_line_count textarea = Edit_buffer_renderable.virtual_line_count textarea.editor
let scroll_y textarea = Edit_buffer_renderable.scroll_y textarea.editor
let viewport textarea = Edit_buffer_renderable.viewport textarea.editor
let set_viewport textarea ~x ~y ~width ~height =
  Edit_buffer_renderable.set_viewport textarea.editor ~x ~y ~width ~height
let placeholder textarea = textarea.placeholder

let set_placeholder textarea value =
  Result.bind (ensure_alive textarea) (fun () ->
      textarea.placeholder <- value;
      refresh_placeholder textarea;
      Renderable.request_render (as_renderable textarea))

let placeholder_color textarea = textarea.placeholder_color

let set_placeholder_color textarea value =
  Result.bind (ensure_alive textarea) (fun () ->
      textarea.placeholder_color <- value;
      refresh_placeholder textarea;
      Renderable.request_render (as_renderable textarea))

let background_color textarea = textarea.background_color

let set_background_color textarea value =
  Result.bind (ensure_alive textarea) (fun () ->
      textarea.background_color <- value;
      update_colors textarea;
      Renderable.request_render (as_renderable textarea))

let text_color textarea = textarea.text_color

let set_text_color textarea value =
  Result.bind (ensure_alive textarea) (fun () ->
      textarea.text_color <- value;
      update_colors textarea;
      Renderable.request_render (as_renderable textarea))

let focused_background_color textarea = textarea.focused_background_color

let set_focused_background_color textarea value =
  Result.bind (ensure_alive textarea) (fun () ->
      textarea.focused_background_color <- value;
      update_colors textarea;
      Renderable.request_render (as_renderable textarea))

let focused_text_color textarea = textarea.focused_text_color

let set_focused_text_color textarea value =
  Result.bind (ensure_alive textarea) (fun () ->
      textarea.focused_text_color <- value;
      update_colors textarea;
      Renderable.request_render (as_renderable textarea))

let focused textarea = Renderable.focused (as_renderable textarea)
let focus textarea = Renderable.focus (as_renderable textarea)
let blur textarea = Renderable.blur (as_renderable textarea)
let selectable textarea = Edit_buffer_renderable.selectable textarea.editor
let set_selectable textarea value = Edit_buffer_renderable.set_selectable textarea.editor value
let show_cursor textarea = Edit_buffer_renderable.show_cursor textarea.editor
let set_show_cursor textarea value = Edit_buffer_renderable.set_show_cursor textarea.editor value
let cursor_style textarea = Edit_buffer_renderable.cursor_style textarea.editor
let set_cursor_style textarea value = Edit_buffer_renderable.set_cursor_style textarea.editor value
let cursor_color textarea = Edit_buffer_renderable.cursor_color textarea.editor
let set_cursor_color textarea value = Edit_buffer_renderable.set_cursor_color textarea.editor value
let selection_bg textarea = Edit_buffer_renderable.selection_bg textarea.editor
let set_selection_bg textarea value = Edit_buffer_renderable.set_selection_bg textarea.editor value
let selection_fg textarea = Edit_buffer_renderable.selection_fg textarea.editor
let set_selection_fg textarea value = Edit_buffer_renderable.set_selection_fg textarea.editor value
let wrap_mode textarea = Edit_buffer_renderable.wrap_mode textarea.editor
let set_wrap_mode textarea value = Edit_buffer_renderable.set_wrap_mode textarea.editor value
let scroll_margin textarea = Edit_buffer_renderable.scroll_margin textarea.editor
let set_scroll_margin textarea value = Edit_buffer_renderable.set_scroll_margin textarea.editor value
let scroll_speed textarea = Edit_buffer_renderable.scroll_speed textarea.editor
let set_scroll_speed textarea value = Edit_buffer_renderable.set_scroll_speed textarea.editor value
let set_key_bindings textarea bindings = Edit_buffer_renderable.set_key_bindings textarea.editor bindings
let set_traits textarea traits = Edit_buffer_renderable.set_traits textarea.editor traits
let traits textarea = Edit_buffer_renderable.traits textarea.editor
let on_submit textarea callback = Event_kernel.on textarea.submit_events callback
let on_content_change textarea callback = Edit_buffer_renderable.on_content_change textarea.editor callback
let on_cursor_change textarea callback = Edit_buffer_renderable.on_cursor_change textarea.editor callback

let submit textarea =
  Result.bind (ensure_alive textarea) (fun () ->
      ignore (Event_kernel.emit textarea.submit_events ());
      Ok ())

let handle_key_press textarea event = Edit_buffer_renderable.handle_key_press textarea.editor event
let handle_paste textarea event = Edit_buffer_renderable.handle_paste textarea.editor event

let destroy textarea =
  if not textarea.destroyed then begin
    textarea.destroyed <- true;
    Event_kernel.clear textarea.submit_events;
    Edit_buffer_renderable.destroy textarea.editor
  end
