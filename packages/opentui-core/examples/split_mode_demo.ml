(* Port of vendor/opentui/packages/examples/src/split-mode-demo.ts.

   This example deliberately exercises the split-footer ownership boundary:
   live UI stays in the footer, while each message is rendered through the
   normal retained tree into a scrollback snapshot and committed by the
   renderer. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Box = O.Renderables.Box
module Text = O.Renderables.Text
module Textarea = O.Renderables.Textarea
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler
module Keybinding = O.Lib.Keybinding
module Modes = O.Lib.Render_geometry
module Util = Opentui_examples_lib.Util

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let ignore_ok result = ignore (expect_ok result)
let color = Util.color_of_hex

let add_child children renderable =
  ignore_ok (O.Layout_children.add children renderable)

let add_box_child children box = add_child children (Box.as_renderable box)
let add_text_child children text = add_child children (Text.as_renderable text)

let set_width renderable value = ignore_ok (O.Renderable.set_width renderable value)
let set_height renderable value = ignore_ok (O.Renderable.set_height renderable value)

let set_min_height renderable value =
  ignore_ok (O.Renderable.set_min_height renderable (O.Yoga.Point value))

let set_flex_grow renderable value =
  ignore_ok (O.Renderable.set_flex_grow renderable (Some value))

let set_flex_shrink renderable value =
  ignore_ok (O.Renderable.set_flex_shrink renderable (Some value))

let set_flex_direction renderable value =
  ignore_ok (O.Renderable.set_flex_direction renderable value)

let set_justify_content renderable value =
  ignore_ok (O.Renderable.set_justify_content renderable value)

let set_align_items renderable value =
  ignore_ok (O.Renderable.set_align_items renderable value)

let set_position_absolute renderable ~left ~top =
  ignore_ok
    (O.Renderable.set_position_type renderable O.Yoga.Position_absolute);
  ignore_ok
    (O.Renderable.set_position renderable ~edge:O.Yoga.Left
       (O.Yoga.Point left));
  ignore_ok
    (O.Renderable.set_position renderable ~edge:O.Yoga.Top
       (O.Yoga.Point top))

let set_text text content = ignore_ok (Text.set_content text content)

let make_text context ~id ~foreground ?(attributes = 0) content =
  expect_ok
    (Text.create context ~id
       ~content:(S.create [ S.chunk ~fg:foreground ~attributes content ]) ())

type role = User | Assistant | System | Stream

type palette = {
  app_background : O.Color.t;
  shell_background : O.Color.t;
  shell_border : O.Color.t;
  title : O.Color.t;
  mode : O.Color.t;
  status : O.Color.t;
  help : O.Color.t;
  composer_background : O.Color.t;
  composer_border : O.Color.t;
  placeholder : O.Color.t;
  input : O.Color.t;
  focused_input : O.Color.t;
  cursor : O.Color.t;
  control : O.Color.t;
  message : O.Color.t;
  user_border : O.Color.t;
  assistant_border : O.Color.t;
  system_border : O.Color.t;
  stream_border : O.Color.t;
  stream_text : O.Color.t;
}

let dark_palette =
  {
    app_background = color "#0A1222";
    shell_background = color "#0F1F39";
    shell_border = color "#4C6D94";
    title = color "#F6FAFF";
    mode = color "#A7D4FF";
    status = color "#D5E7FA";
    help = color "#C3D9F0";
    composer_background = color "#112642";
    composer_border = color "#6A89AD";
    placeholder = color "#5F7FA0";
    input = color "#E7F2FF";
    focused_input = color "#FFFFFF";
    cursor = color "#FFFFFF";
    control = color "#A5C9EC";
    message = color "#EDF6FF";
    user_border = color "#68C79E";
    assistant_border = color "#78A8DA";
    system_border = color "#D9A568";
    stream_border = color "#4FB8F5";
    stream_text = color "#CBE9FF";
  }

let light_palette =
  {
    app_background = color "#EEF4FB";
    shell_background = color "#FBFDFF";
    shell_border = color "#90A8C1";
    title = color "#17324F";
    mode = color "#245D93";
    status = color "#23435F";
    help = color "#395B7D";
    composer_background = color "#FFFFFF";
    composer_border = color "#A5B8CB";
    placeholder = color "#7A93AB";
    input = color "#1A334D";
    focused_input = color "#13293F";
    cursor = color "#1B3550";
    control = color "#4A6481";
    message = color "#19334F";
    user_border = color "#1F9968";
    assistant_border = color "#356FA8";
    system_border = color "#B37F2D";
    stream_border = color "#2E73AF";
    stream_text = color "#2D5D87";
  }

let palette_for_theme = function
  | Some O.Renderer_theme_mode.Light -> light_palette
  | Some O.Renderer_theme_mode.Dark | None -> dark_palette

let role_label = function
  | User -> "YOU"
  | Assistant -> "ASSISTANT"
  | System -> "SYSTEM"
  | Stream -> "STREAM LIVE"

let role_border palette = function
  | User -> palette.user_border
  | Assistant -> palette.assistant_border
  | System -> palette.system_border
  | Stream -> palette.stream_border

let role_heading palette = function
  | User -> palette.user_border
  | Assistant -> palette.assistant_border
  | System -> palette.system_border
  | Stream -> palette.stream_text

let role_body palette = function
  | System -> palette.help
  | Stream -> palette.stream_text
  | User | Assistant -> palette.message

let role_attributes = function
  | Stream -> O.Lib.Text_attributes.bold lor O.Lib.Text_attributes.italic
  | User | Assistant | System -> O.Lib.Text_attributes.bold

let split_long_token token width =
  let token_length = String.length token in
  let count = (token_length + width - 1) / width in
  List.init count (fun index ->
      let offset = index * width in
      String.sub token offset (min width (token_length - offset)))

let wrap_paragraph paragraph width =
  let words =
    List.filter
      (fun word -> Int.compare (String.length word) 0 > 0)
      (String.split_on_char ' ' paragraph)
  in
  let lines = ref [] in
  let current = ref "" in
  let push_current () =
    if Int.compare (String.length !current) 0 > 0 then begin
      lines := !current :: !lines;
      current := ""
    end
  in
  List.iter
    (fun word ->
      if Int.compare (String.length word) width > 0 then begin
        push_current ();
        let chunks = split_long_token word width in
        let last = List.length chunks - 1 in
        List.iteri
          (fun index chunk ->
            if Int.equal index last then current := chunk
            else lines := chunk :: !lines)
          chunks
      end
      else if Int.equal (String.length !current) 0 then current := word
      else
        let candidate = !current ^ " " ^ word in
        if Int.compare (String.length candidate) width <= 0 then
          current := candidate
        else begin
          push_current ();
          current := word
        end)
    words;
  push_current ();
  if Int.equal (List.length !lines) 0 then [ "" ] else List.rev !lines

let wrap_text text width =
  let normalized =
    String.map (fun character -> if Char.equal character '\r' then ' ' else character)
      text
  in
  let paragraphs = String.split_on_char '\n' normalized in
  let lines =
    List.fold_left
      (fun accumulated paragraph ->
        accumulated @ wrap_paragraph paragraph (max 1 width))
      [] paragraphs
  in
  if Int.equal (List.length lines) 0 then [ "" ] else lines

type message = {
  role : role;
  body : string;
  palette : palette;
  index : int;
}

let build_snapshot (message : message)
    (context : O.Renderer.scrollback_render_context) =
  let max_text_width =
    max 1 (min 90 (max 1 (context.width - 4)))
  in
  let heading = Printf.sprintf " %s #%d" (role_label message.role) message.index in
  let body_indent =
    match message.role with Stream -> " > " | User | Assistant | System -> " "
  in
  let body_lines =
    List.map
      (fun line -> body_indent ^ line)
      (wrap_text message.body (max 1 (max_text_width - String.length body_indent)))
  in
  let longest_body =
    List.fold_left
      (fun width line -> max width (String.length line))
      1 body_lines
  in
  let box_width =
    max 1
      (min context.width
         (max 4 (max (String.length heading) longest_body + 1)))
  in
  let box_height = max 3 (List.length body_lines + 3) in
  let box =
    expect_ok
      (Box.create context.render_context
         ~id:(Printf.sprintf "split-message-%d" message.index)
         ~background_color:O.Color.transparent
         ~border_style:O.Lib.Border.Double
         ~border:(O.Lib.Border.Sides [ O.Lib.Border.Left ])
         ~border_color:(role_border message.palette message.role)
         ~should_fill:false ())
  in
  let box_renderable = Box.as_renderable box in
  set_position_absolute box_renderable ~left:0.0 ~top:0.0;
  set_width box_renderable (O.Yoga.Point (float_of_int box_width));
  set_height box_renderable (O.Yoga.Point (float_of_int box_height));
  let heading_text =
    make_text context.render_context
      ~id:(Printf.sprintf "split-heading-%d" message.index)
      ~foreground:(role_heading message.palette message.role)
      ~attributes:(role_attributes message.role) heading
  in
  let heading_renderable = Text.as_renderable heading_text in
  set_position_absolute heading_renderable ~left:1.0 ~top:1.0;
  set_width heading_renderable
    (O.Yoga.Point (float_of_int (max 1 (box_width - 1))));
  set_height heading_renderable (O.Yoga.Point 1.0);
  let body_text =
    make_text context.render_context
      ~id:(Printf.sprintf "split-body-%d" message.index)
      ~foreground:(role_body message.palette message.role)
      (String.concat "\n" body_lines)
  in
  let body_renderable = Text.as_renderable body_text in
  set_position_absolute body_renderable ~left:1.0 ~top:2.0;
  set_width body_renderable
    (O.Yoga.Point (float_of_int (max 1 (box_width - 1))));
  set_height body_renderable
    (O.Yoga.Point (float_of_int (max 1 (box_height - 3))));
  add_text_child (Box.children box) heading_text;
  add_text_child (Box.children box) body_text;
  {
    O.Renderer.root = box_renderable;
    width = box_width;
    height = box_height;
    row_columns = box_width;
    start_on_new_line = true;
    trailing_newline = true;
  }

type demo_mode = Split_footer | Fullscreen

type demo = {
  renderer : O.Renderer.t;
  shell : Box.t;
  title_text : Text.t;
  mode_text : Text.t;
  composer : Textarea.t;
  status_text : Text.t;
  meta_text : Text.t;
  controls_text : Text.t;
  composer_box : Box.t;
  mutable palette : palette;
  mutable mode : demo_mode;
  mutable desired_footer_height : int;
  mutable stream_enabled : bool;
  mutable stream_interval : float;
  mutable stream_elapsed : float;
  mutable stream_index : int;
  mutable pending_reply : string option;
  mutable reply_elapsed : float;
  mutable message_count : int;
  mutable commit_count : int;
  mutable status_message : string;
  mutable destroyed : bool;
  mutable pre_render : O.Renderer.pre_render_driver option;
  mutable live_lease : O.Renderer.live_lease option;
}

let request_render demo = ignore_ok (O.Renderer.request_render demo.renderer)

let current_width demo =
  Int32.to_int (expect_ok (O.Renderer.terminal_width demo.renderer))

let current_height demo =
  Int32.to_int (expect_ok (O.Renderer.terminal_height demo.renderer))

let clamp_footer_height demo requested =
  let max_height = max 1 (current_height demo - 5) in
  let minimum = min 8 max_height in
  min (max minimum requested) max_height

let mode_is_split demo =
  match demo.mode with Split_footer -> true | Fullscreen -> false

let refresh_status ?message demo =
  if not demo.destroyed then begin
    Option.iter (fun value -> demo.status_message <- value) message;
    let status = demo.status_message in
    let mode_label =
      match demo.mode with
      | Split_footer ->
          Printf.sprintf "split:%d" demo.desired_footer_height
      | Fullscreen -> "fullscreen"
    in
    let stream_label =
      if demo.stream_enabled then
        Printf.sprintf "%.0fms" (demo.stream_interval *. 1000.0)
      else "off"
    in
    let mouse_label =
      if expect_ok (O.Renderer.use_mouse demo.renderer) then "on" else "off"
    in
    let draft_length =
      match Textarea.value demo.composer with
      | Ok value -> String.length value
      | Error _ -> 0
    in
    set_text demo.mode_text (S.of_string mode_label);
    set_text demo.meta_text
      (S.of_string
         (Printf.sprintf "draft:%d mouse:%s stream:%s queued:%d lines:%d"
            draft_length mouse_label stream_label demo.commit_count
            demo.stream_index));
    set_text demo.controls_text
      (S.of_string
         "Ctrl+Enter send | Enter newline | Shift+U mouse | Ctrl+S stream | Ctrl+0 mode | Ctrl+R demo | Ctrl+[/] speed | Shift/Ctrl+Up/Down footer");
    let prefix =
      Printf.sprintf "messages:%d %s | " demo.message_count
        (if demo.stream_enabled then "streaming" else "idle")
    in
    set_text demo.status_text (S.of_string (prefix ^ status))
  end

let apply_palette demo =
  ignore_ok
    (O.Renderer.set_background_color demo.renderer
       ~color:demo.palette.app_background);
  ignore_ok (Box.set_background_color demo.shell demo.palette.shell_background);
  ignore_ok (Box.set_border_color demo.shell demo.palette.shell_border);
  ignore_ok
    (Box.set_background_color demo.composer_box
       demo.palette.composer_background);
  ignore_ok (Box.set_border_color demo.composer_box demo.palette.composer_border);
  ignore_ok
    (Textarea.set_placeholder_color demo.composer demo.palette.placeholder);
  ignore_ok (Textarea.set_text_color demo.composer demo.palette.input);
  ignore_ok
    (Textarea.set_focused_text_color demo.composer demo.palette.focused_input);
  ignore_ok
    (Textarea.set_background_color demo.composer
       demo.palette.composer_background);
  ignore_ok
    (Textarea.set_focused_background_color demo.composer
       demo.palette.composer_background);
  ignore_ok (Textarea.set_cursor_color demo.composer demo.palette.cursor);
  set_text demo.title_text (S.create [ S.chunk ~fg:demo.palette.title "Split Footer Demo" ]);
  set_text demo.mode_text (S.create [ S.chunk ~fg:demo.palette.mode "split" ]);
  set_text demo.status_text (S.create [ S.chunk ~fg:demo.palette.status "ready" ]);
  set_text demo.meta_text (S.create [ S.chunk ~fg:demo.palette.stream_text "" ]);
  set_text demo.controls_text (S.create [ S.chunk ~fg:demo.palette.control "" ])

let release_live demo =
  Option.iter O.Renderer.release_live_lease demo.live_lease;
  demo.live_lease <- None

let sync_live demo =
  if mode_is_split demo then
    match demo.live_lease with
    | Some _ -> ()
    | None ->
        demo.live_lease <-
          Some (expect_ok (O.Renderer.acquire_live_lease demo.renderer))
  else release_live demo

let publish_message ?(count = true) demo role body =
  if count then demo.message_count <- demo.message_count + 1;
  if not (mode_is_split demo) then
    refresh_status ~message:"output is paused in fullscreen" demo
  else begin
    let message =
      {
        role;
        body;
        palette = demo.palette;
        index = demo.message_count + demo.commit_count + 1;
      }
    in
    match
      O.Renderer.write_to_scrollback demo.renderer (fun context ->
          build_snapshot message context)
    with
    | Ok () ->
        demo.commit_count <- demo.commit_count + 1;
        refresh_status demo
    | Error error ->
        refresh_status
          ~message:("scrollback write failed: " ^ O.Error.message error)
          demo
  end

let publish_demo_transcript demo =
  publish_message ~count:false demo System "Mini medley:";
  List.iteri
    (fun index text ->
      publish_message demo Assistant
        (Printf.sprintf "Passage %d\n%s" (index + 1) text))
    [
      "So ya thought ya might like to go to the show";
      "We don't need no education";
      "Mother should I build the wall";
      "Hey you! out there in the cold";
      "I've got a little black book with my poems in";
      "Hello, is there anybody in there";
      "All alone, or in twos";
    ];
  publish_message ~count:false demo System
    "The show must go on. Press Ctrl+Enter to send a reply.";
  refresh_status ~message:"demo transcript queued" demo

let assistant_reply text =
  let normalized = String.lowercase_ascii text in
  if String.contains normalized 'w'
     && Int.compare (String.length normalized) 4 >= 0
     && String.equal (String.sub normalized 0 4) "wall"
  then "All in all you're just another brick in the wall"
  else if String.contains normalized 'h'
          && Int.compare (String.length normalized) 4 >= 0
  then "Hello, is there anybody in there"
  else "The show must go on"

let rec submit_composer demo =
  match Textarea.value demo.composer with
  | Error error ->
      refresh_status ~message:("draft read failed: " ^ O.Error.message error) demo
  | Ok value ->
      let trimmed = String.trim value in
      if Int.equal (String.length trimmed) 0 then
        refresh_status ~message:"empty draft ignored" demo
      else begin
        ignore_ok (Textarea.set_text demo.composer "");
        ignore_ok (Textarea.focus demo.composer);
        if Int.compare (String.length trimmed) 0 > 0
           && Char.equal trimmed.[0] '/'
        then begin
          let words =
            List.filter
              (fun word -> Int.compare (String.length word) 0 > 0)
              (String.split_on_char ' ' trimmed)
          in
          match words with
          | command :: args ->
              let command = String.lowercase_ascii command in
              let args = List.map String.lowercase_ascii args in
              if String.equal command "/help" then
                publish_message ~count:false demo System
                  "/help /demo /mouse on|off /stream on|off /speed <ms> /mode split|full /footer <n>"
              else if String.equal command "/demo" then publish_demo_transcript demo
              else if String.equal command "/mouse" then begin
                let enabled =
                  match args with
                  | "on" :: _ -> true
                  | "off" :: _ -> false
                  | _ -> not (expect_ok (O.Renderer.use_mouse demo.renderer))
                in
                ignore_ok (O.Renderer.set_use_mouse demo.renderer enabled);
                refresh_status
                  ~message:(if enabled then "mouse enabled" else "mouse disabled")
                  demo
              end
              else if String.equal command "/stream" then
                (match args with
                | "on" :: _ -> set_stream_enabled demo true
                | "off" :: _ -> set_stream_enabled demo false
                | _ -> set_stream_enabled demo (not demo.stream_enabled))
              else if String.equal command "/speed" then
                (match args with
                | value :: _ -> (
                    match int_of_string_opt value with
                    | Some milliseconds when Int.compare milliseconds 0 > 0 ->
                        demo.stream_interval <-
                          max 0.18 (min 2.0 (float_of_int milliseconds /. 1000.0));
                        refresh_status
                          ~message:
                            (Printf.sprintf "stream interval %.0fms"
                               (demo.stream_interval *. 1000.0))
                          demo
                    | Some _ | None ->
                        refresh_status ~message:"invalid stream interval" demo)
                | [] ->
                    refresh_status
                      ~message:
                        (Printf.sprintf "stream interval %.0fms"
                           (demo.stream_interval *. 1000.0))
                      demo)
              else if String.equal command "/mode" then
                (match args with
                | "full" :: _ | "fullscreen" :: _ -> set_mode demo Fullscreen
                | "split" :: _ | "footer" :: _ -> set_mode demo Split_footer
                | _ ->
                    set_mode demo
                      (match demo.mode with
                      | Split_footer -> Fullscreen
                      | Fullscreen -> Split_footer))
              else if String.equal command "/footer" then
                (match args with
                | value :: _ -> (
                    match int_of_string_opt value with
                    | Some height -> set_footer_height demo height
                    | None -> refresh_status ~message:"invalid footer height" demo)
                | [] -> refresh_status ~message:"usage: /footer <height>" demo)
              else
                publish_message ~count:false demo System
                  ("unknown command: " ^ command)
          | [] -> refresh_status demo
        end
        else begin
          publish_message demo User trimmed;
          demo.pending_reply <- Some (assistant_reply trimmed);
          demo.reply_elapsed <- 0.0;
          refresh_status ~message:"assistant composing" demo
        end
      end

and set_stream_enabled demo enabled =
  demo.stream_enabled <- enabled;
  refresh_status
    ~message:(if enabled then "stream enabled" else "stream disabled")
    demo

and set_mode demo next_mode =
  let transition =
    match demo.mode, next_mode with
    | Split_footer, Split_footer | Fullscreen, Fullscreen -> Ok ()
    | Split_footer, Fullscreen ->
        Result.bind
          (O.Renderer.set_external_output_mode demo.renderer O.Renderer.Passthrough)
          (fun () ->
            O.Renderer.set_render_geometry demo.renderer Modes.Main_screen
              ~footer_height:0)
    | Fullscreen, Split_footer ->
        Result.bind
          (O.Renderer.set_render_geometry demo.renderer Modes.Split_footer
             ~footer_height:demo.desired_footer_height)
          (fun () ->
            O.Renderer.set_external_output_mode demo.renderer
              O.Renderer.Capture_stdout)
  in
  match transition with
  | Error error ->
      refresh_status
        ~message:("mode transition failed: " ^ O.Error.message error)
        demo
  | Ok () ->
      demo.mode <- next_mode;
      sync_live demo;
      refresh_status
        ~message:
          (match next_mode with
          | Split_footer -> "split-footer mode"
          | Fullscreen -> "fullscreen mode")
        demo

and set_footer_height demo height =
  let clamped = clamp_footer_height demo height in
  demo.desired_footer_height <- clamped;
  match demo.mode with
  | Fullscreen ->
      refresh_status
        ~message:(Printf.sprintf "footer target %d" clamped)
        demo
  | Split_footer ->
      (match
         O.Renderer.set_render_geometry demo.renderer Modes.Split_footer
           ~footer_height:clamped
       with
      | Ok () -> refresh_status ~message:(Printf.sprintf "footer height %d" clamped) demo
      | Error error ->
          refresh_status
            ~message:("footer resize failed: " ^ O.Error.message error)
            demo)

let update_timers demo delta =
  if mode_is_split demo then begin
    if demo.stream_enabled then begin
      demo.stream_elapsed <- demo.stream_elapsed +. delta;
      let interval = demo.stream_interval in
      if Float.compare demo.stream_elapsed interval >= 0 then begin
        (* [setInterval] in the reference does not replay missed ticks after
           a long synchronous render. Drop the elapsed backlog and publish at
           most one passage for this frame. *)
        demo.stream_elapsed <- 0.0;
        demo.stream_index <- demo.stream_index + 1;
        let passage =
          match demo.stream_index mod 4 with
          | 0 -> "Together we stand, divided we fall"
          | 1 -> "The child is grown, the dream is gone"
          | 2 -> "There is no pain, you are receding"
          | _ -> "All in all you're just another brick in the wall"
        in
        publish_message ~count:false demo Stream passage
      end
    end;
    match demo.pending_reply with
    | None -> ()
    | Some reply ->
        demo.reply_elapsed <- demo.reply_elapsed +. delta;
        if Float.compare demo.reply_elapsed 0.35 >= 0 then begin
          demo.pending_reply <- None;
          publish_message demo Assistant reply;
          refresh_status ~message:"assistant reply queued" demo
        end
  end

let character_is key expected =
  match key with
  | Key.Character bytes ->
      String.equal (String.lowercase_ascii (Bytes.to_string bytes)) expected
  | Key.Named _ -> false

let named_is key expected =
  match key, expected with
  | Key.Named Key.Up, `Up
  | Key.Named Key.Kpup, `Up
  | Key.Named Key.Down, `Down
  | Key.Named Key.Kpdown, `Down
  | Key.Named Key.Page_up, `Page_up
  | Key.Named Key.Kppageup, `Page_up
  | Key.Named Key.Page_down, `Page_down
  | Key.Named Key.Kppagedown, `Page_down -> true
  | Key.Named _, _ | Key.Character _, _ -> false

let metadata_code_is metadata expected =
  match metadata.Key.code, metadata.Key.base_code with
  | Some code, _ when Int.equal code expected -> true
  | _, Some base_code when Int.equal base_code expected -> true
  | _ -> false

let number_is key_event expected =
  let key = Handler.key key_event in
  let metadata = Handler.key_metadata key_event in
  metadata_code_is metadata expected
  ||
  match key, expected with
  | Key.Character bytes, expected
    when Int.equal (Bytes.length bytes) 1
         && Int.equal (Bytes.get_uint8 bytes 0) expected -> true
  | Key.Character bytes, 48 when String.equal (Bytes.to_string bytes) ")" -> true
  | Key.Named Key.Kp0, 48 -> true
  | Key.Named _, _ | Key.Character _, _ -> false

let raw_is key_event expected =
  Bytes.equal (Handler.key_raw key_event) (Bytes.of_string expected)

let mode_toggle_key key_event =
  let modifiers = Handler.key_modifiers key_event in
  modifiers.ctrl
  &&
  (number_is key_event 48
  || raw_is key_event "\x1b[27;5;48~"
  || raw_is key_event "\x1b[27;6;48~")

let submit_key key_event =
  let modifiers = Handler.key_modifiers key_event in
  modifiers.ctrl
  &&
  match Handler.key key_event with
  | Key.Named Key.Return | Key.Named Key.Linefeed | Key.Named Key.Kpenter -> true
  | Key.Named _ | Key.Character _ -> false

let initial_keypress key_event =
  match (Handler.key_metadata key_event).Key.event_type with
  | Key.Press -> true
  | Key.Repeat | Key.Release -> false

let handle_key demo key_event =
  match Handler.key_event_kind key_event with
  | Handler.Keypress -> begin
      let modifiers = Handler.key_modifiers key_event in
      let key = Handler.key key_event in
      if modifiers.ctrl && submit_key key_event then begin
        Handler.prevent_default key_event;
        ignore_ok (Textarea.submit demo.composer)
      end
      else if modifiers.ctrl && character_is key "s" then begin
        Handler.prevent_default key_event;
        if initial_keypress key_event then
          set_stream_enabled demo (not demo.stream_enabled)
      end
      else if mode_toggle_key key_event then begin
        Handler.prevent_default key_event;
        if initial_keypress key_event then begin
          let next =
            match demo.mode with
            | Split_footer -> Fullscreen
            | Fullscreen -> Split_footer
          in
          set_mode demo next
        end
      end
      else if modifiers.ctrl && character_is key "r" then begin
        Handler.prevent_default key_event;
        if initial_keypress key_event then publish_demo_transcript demo
      end
      else if modifiers.ctrl && character_is key "l" then begin
        Handler.prevent_default key_event;
        ignore_ok (Textarea.set_text demo.composer "");
        refresh_status ~message:"draft cleared" demo
      end
      else if (modifiers.ctrl || modifiers.shift) && named_is key `Up then begin
        Handler.prevent_default key_event;
        set_footer_height demo (demo.desired_footer_height + 1)
      end
      else if (modifiers.ctrl || modifiers.shift) && named_is key `Down then begin
        Handler.prevent_default key_event;
        set_footer_height demo (demo.desired_footer_height - 1)
      end
      else if modifiers.ctrl && character_is key "[" then begin
        Handler.prevent_default key_event;
        demo.stream_interval <-
          max 0.18 (demo.stream_interval -. 0.08);
        refresh_status
          ~message:
            (Printf.sprintf "stream interval %.0fms"
               (demo.stream_interval *. 1000.0))
          demo
      end
      else if modifiers.ctrl && character_is key "]" then begin
        Handler.prevent_default key_event;
        demo.stream_interval <-
          min 2.0 (demo.stream_interval +. 0.08);
        refresh_status
          ~message:
            (Printf.sprintf "stream interval %.0fms"
               (demo.stream_interval *. 1000.0))
          demo
      end
      else if modifiers.shift && not modifiers.ctrl && not modifiers.meta
              && character_is key "u" then begin
        Handler.prevent_default key_event;
        if initial_keypress key_event then begin
          let enabled = not (expect_ok (O.Renderer.use_mouse demo.renderer)) in
          ignore_ok (O.Renderer.set_use_mouse demo.renderer enabled);
          refresh_status
            ~message:(if enabled then "mouse enabled" else "mouse disabled") demo
        end
      end
      else
        match key with
        | Key.Named Key.Escape ->
            ignore_ok (Textarea.focus demo.composer);
            refresh_status ~message:"composer focused" demo
        | Key.Character _ -> ()
        | Key.Named _ -> ()
  end
  | Handler.Keyrelease | Handler.Paste -> ()

let create_demo renderer =
  let initial_footer =
    let terminal_height = Int32.to_int (expect_ok (O.Renderer.terminal_height renderer)) in
    min 11 (max 1 (terminal_height - 5))
  in
  ignore_ok
    (O.Renderer.set_render_geometry renderer Modes.Split_footer
       ~footer_height:initial_footer);
  ignore_ok
    (O.Renderer.set_external_output_mode renderer O.Renderer.Capture_stdout);
  let context = O.Renderer.context renderer in
  let initial_palette =
    palette_for_theme (expect_ok (O.Renderer.theme_mode renderer))
  in
  ignore_ok
    (O.Renderer.set_background_color renderer
       ~color:initial_palette.app_background);
  let shell =
    expect_ok
      (Box.create context ~id:"split-footer-shell"
         ~background_color:initial_palette.shell_background
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders
         ~border_color:initial_palette.shell_border ())
  in
  let shell_renderable = Box.as_renderable shell in
  set_width shell_renderable (O.Yoga.Percent 100.0);
  set_height shell_renderable (O.Yoga.Percent 100.0);
  set_flex_direction shell_renderable O.Yoga.Flex_column;
  set_flex_shrink shell_renderable 0.0;
  let header =
    expect_ok
      (Box.create context ~id:"split-footer-header"
         ~background_color:initial_palette.shell_background ())
  in
  let header_renderable = Box.as_renderable header in
  set_width header_renderable (O.Yoga.Percent 100.0);
  set_height header_renderable (O.Yoga.Point 1.0);
  set_flex_shrink header_renderable 0.0;
  set_flex_direction header_renderable O.Yoga.Flex_row;
  set_justify_content header_renderable O.Yoga.Justify_space_between;
  set_align_items header_renderable O.Yoga.Align_center;
  let title_text =
    make_text context ~id:"split-footer-title" ~foreground:initial_palette.title
      "Split Footer Demo"
  in
  let mode_text =
    make_text context ~id:"split-footer-mode" ~foreground:initial_palette.mode
      "split"
  in
  add_text_child (Box.children header) title_text;
  add_text_child (Box.children header) mode_text;
  let composer_box =
    expect_ok
      (Box.create context ~id:"split-footer-composer-frame"
         ~background_color:initial_palette.composer_background
         ~border_style:O.Lib.Border.Rounded ~border:Box.all_borders
         ~border_color:initial_palette.composer_border ())
  in
  let composer_box_renderable = Box.as_renderable composer_box in
  set_width composer_box_renderable (O.Yoga.Percent 100.0);
  set_min_height composer_box_renderable 4.0;
  set_flex_grow composer_box_renderable 1.0;
  set_flex_shrink composer_box_renderable 1.0;
  let composer =
    expect_ok
      (Textarea.create context ~id:"split-footer-composer"
         ~placeholder:"Type message... (Ctrl+Enter sends)"
         ~placeholder_color:initial_palette.placeholder
         ~background_color:initial_palette.composer_background
         ~text_color:initial_palette.input
         ~focused_text_color:initial_palette.focused_input
         ~focused_background_color:initial_palette.composer_background
         ~cursor_color:initial_palette.cursor ~wrap_mode:O.Text_buffer_view.Word
         ~show_cursor:true ~width:(O.Yoga.Percent 100.0)
         ~height:(O.Yoga.Percent 100.0)
         ~key_bindings:
           [
             Keybinding.binding ~name:"return" ~ctrl:true
               ~action:(O.Renderables.Edit_buffer_renderable.Submit : Textarea.action) ();
             Keybinding.binding ~name:"kpenter" ~ctrl:true
               ~action:(O.Renderables.Edit_buffer_renderable.Submit : Textarea.action) ();
             Keybinding.binding ~name:"linefeed" ~ctrl:true
               ~action:(O.Renderables.Edit_buffer_renderable.Submit : Textarea.action) ();
             (* Many terminal emulators encode Ctrl+Enter as LF rather than a
                distinguishable modified Return. The ordinary Enter key is
                CR, so this preserves Enter-for-newline while accepting that
                portable Ctrl+Enter representation. *)
             Keybinding.binding ~name:"linefeed"
               ~action:(O.Renderables.Edit_buffer_renderable.Submit : Textarea.action) ();
           ]
         ())
  in
  add_child (Box.children composer_box) (Textarea.as_renderable composer);
  let status_row =
    expect_ok
      (Box.create context ~id:"split-footer-status-row"
         ~background_color:initial_palette.shell_background ())
  in
  let status_row_renderable = Box.as_renderable status_row in
  set_width status_row_renderable (O.Yoga.Percent 100.0);
  set_height status_row_renderable (O.Yoga.Point 1.0);
  set_flex_shrink status_row_renderable 0.0;
  set_flex_direction status_row_renderable O.Yoga.Flex_row;
  set_justify_content status_row_renderable O.Yoga.Justify_space_between;
  set_align_items status_row_renderable O.Yoga.Align_center;
  let status_text =
    make_text context ~id:"split-footer-status" ~foreground:initial_palette.status
      "ready"
  in
  let meta_text =
    make_text context ~id:"split-footer-meta" ~foreground:initial_palette.stream_text
      ""
  in
  add_text_child (Box.children status_row) status_text;
  add_text_child (Box.children status_row) meta_text;
  let controls_row =
    expect_ok
      (Box.create context ~id:"split-footer-controls-row"
         ~background_color:initial_palette.shell_background ())
  in
  let controls_row_renderable = Box.as_renderable controls_row in
  set_width controls_row_renderable (O.Yoga.Percent 100.0);
  set_height controls_row_renderable (O.Yoga.Point 1.0);
  set_flex_shrink controls_row_renderable 0.0;
  let controls_text =
    make_text context ~id:"split-footer-controls"
      ~foreground:initial_palette.control ""
  in
  add_text_child (Box.children controls_row) controls_text;
  add_box_child (Box.children shell) header;
  add_box_child (Box.children shell) composer_box;
  add_box_child (Box.children shell) status_row;
  add_box_child (Box.children shell) controls_row;
  add_box_child (O.Renderer.children renderer) shell;
  let demo =
    {
      renderer;
      shell;
      title_text;
      mode_text;
      composer;
      status_text;
      meta_text;
      controls_text;
      composer_box;
      palette = initial_palette;
      mode = Split_footer;
      desired_footer_height = initial_footer;
      stream_enabled = true;
      stream_interval = 1.6;
      stream_elapsed = 0.0;
      stream_index = 0;
      pending_reply = None;
      reply_elapsed = 0.0;
      message_count = 0;
      commit_count = 0;
      status_message = "ready";
      destroyed = false;
      pre_render = None;
      live_lease = None;
    }
  in
  ignore (Textarea.on_submit demo.composer (fun () -> submit_composer demo));
  ignore (Textarea.on_content_change demo.composer (fun () -> refresh_status demo));
  ignore_ok
    (O.Renderer.on_keypress renderer (fun key_event ->
         handle_key demo key_event));
  ignore_ok
    (O.Renderer.on_theme_mode renderer (fun mode ->
         demo.palette <- palette_for_theme (Some mode);
         apply_palette demo;
         refresh_status ~message:"theme updated" demo));
  let pre_render =
    expect_ok
      (O.Renderer.attach_pre_render renderer (fun delta ->
           update_timers demo delta;
           refresh_status demo))
  in
  demo.pre_render <- Some pre_render;
  ignore_ok
    (O.Renderer.attach_before_destroy renderer (fun () ->
         demo.destroyed <- true;
         Option.iter O.Renderer.detach_pre_render demo.pre_render;
         release_live demo));
  apply_palette demo;
  publish_message ~count:false demo System
    (Printf.sprintf "Split footer capture is active at width %d." (current_width demo));
  publish_message ~count:false demo System
    "Type text and press Ctrl+Enter, or press Ctrl+R for a transcript.";
  ignore_ok (Textarea.focus demo.composer);
  sync_live demo;
  refresh_status ~message:"ready" demo;
  demo

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  ignore (create_demo renderer);
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
    ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~screen:O.Lib.Terminal_modes.Main
    ~reserve_screen:true
    ~target_frames_per_second:30
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard)
