(* Port of vendor/opentui/packages/examples/src/text-truncation-demo.ts.

   The demo keeps the reference's two-column layout and uses the native text
   buffer view directly so the T and W controls exercise truncation and
   wrapping independently. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Text = O.Renderables.Text_buffer_renderable
module Box = O.Renderables.Box
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler
module Util = Opentui_examples_lib.Util

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let ignore_ok result = ignore (expect_ok result)
let color = Util.color_of_hex

let background_color = color "#0d1117"
let panel_color = color "#161b22"
let border_color = color "#30363d"
let blue_color = color "#58a6ff"
let default_text_color = color "#c9d1d9"
let green_color = color "#3fb950"
let yellow_color = color "#d29922"
let pink_color = color "#f778ba"
let purple_color = color "#bc8cff"
let red_color = color "#ff7b72"
let muted_color = color "#8b949e"
let selection_start_color = color "#7dd3fc"
let selection_middle_color = color "#94a3b8"

let add_child children renderable =
  ignore_ok (O.Layout_children.add children renderable)

let add_box_child parent child = add_child (Box.children parent) (Box.as_renderable child)
let add_text_child parent child = add_child (Box.children parent) (Text.as_renderable child)

let set_flex_direction renderable value =
  ignore_ok (O.Renderable.set_flex_direction renderable value)

let set_flex_grow renderable value =
  ignore_ok (O.Renderable.set_flex_grow renderable (Some value))

let set_flex_basis renderable value =
  ignore_ok (O.Renderable.set_flex_basis renderable (O.Yoga.Point value))

let set_height renderable value =
  ignore_ok (O.Renderable.set_height renderable (O.Yoga.Point value))

let set_min_height renderable value =
  ignore_ok (O.Renderable.set_min_height renderable (O.Yoga.Point value))

let set_padding renderable value =
  ignore_ok
    (O.Renderable.set_padding renderable ~edge:O.Yoga.All
       (O.Yoga.Point value))

let set_gap renderable value =
  ignore_ok
    (O.Renderable.set_gap renderable ~gutter:O.Yoga.Gutter_all
       (O.Yoga.Point value))

let create_text context ?id ?(selectable = false)
    ?(wrap_mode = O.Text_buffer_view.No_wrap) ~foreground content =
  let text =
    expect_ok
      (Text.create context ?id ~width_method:O.Text_buffer.Unicode ~wrap_mode
         ~selectable ())
  in
  ignore_ok (Text.set_default_fg text (Some foreground));
  ignore_ok (Text.set_styled_text text content);
  text

let create_panel context ~id ~title ~border ~border_color ?min_height
    ?flex_grow () =
  let panel =
    expect_ok
      (Box.create context ~id ~background_color:panel_color
         ~border_style:O.Lib.Border.Rounded ~border ~border_color
         ~title ())
  in
  set_flex_direction (Box.as_renderable panel) O.Yoga.Flex_column;
  set_gap (Box.as_renderable panel) 1.0;
  set_padding (Box.as_renderable panel) 1.0;
  Option.iter
    (fun value -> set_min_height (Box.as_renderable panel) (float_of_int value))
    min_height;
  Option.iter
    (fun value -> set_flex_grow (Box.as_renderable panel) value)
    flex_grow;
  panel

type column_size = Equal | Left_larger | Right_larger

type demo = {
  renderer : O.Renderer.t;
  main_container : Box.t;
  left_column : Box.t;
  right_column : Box.t;
  footer_text : Text.t;
  selection_status_text : Text.t;
  selection_start_text : Text.t;
  selection_middle_text : Text.t;
  selection_end_text : Text.t;
  text_elements : Text.t list;
  mutable truncate_enabled : bool;
  mutable wrap_mode : O.Text_buffer_view.wrap_mode;
  mutable column_size : column_size;
  mutable key_subscription : O.Event_subscription.t option;
  mutable selection_subscription : O.Event_subscription.t option;
  mutable live_lease : O.Renderer.live_lease option;
  mutable destroyed : bool;
}

let wrap_mode_name = function
  | O.Text_buffer_view.No_wrap -> "NONE"
  | O.Text_buffer_view.Char -> "CHAR"
  | O.Text_buffer_view.Word -> "WORD"

let javascript_char_count text =
  Array.fold_left
    (fun count codepoint ->
      count
      + if Int.compare codepoint.O.Lib.Text_metrics.code 0xffff > 0 then 2
        else 1)
    0
    (O.Lib.Text_metrics.scan O.Lib.Text_metrics.Unicode text)

let clamp_int value ~lower ~upper =
  let value = if Int.compare value lower < 0 then lower else value in
  if Int.compare value upper > 0 then upper else value

let codepoint_count text =
  Array.length (O.Lib.Text_metrics.scan O.Lib.Text_metrics.Unicode text)

let codepoint_substring text ~start ~length =
  let codepoints = O.Lib.Text_metrics.scan O.Lib.Text_metrics.Unicode text in
  let count = Array.length codepoints in
  let start = clamp_int start ~lower:0 ~upper:count in
  let length = if Int.compare length 0 < 0 then 0 else length in
  let finish = clamp_int (start + length) ~lower:start ~upper:count in
  let byte_start =
    if Int.equal start count then String.length text
    else codepoints.(start).O.Lib.Text_metrics.byte_start
  in
  let byte_finish =
    if Int.equal finish count then String.length text
    else codepoints.(finish).O.Lib.Text_metrics.byte_start
  in
  String.sub text byte_start (byte_finish - byte_start)

let set_plain_text text value =
  ignore_ok (Text.set_styled_text text (S.of_string value))

let set_selection_display demo ~status ~start_text ~middle ~end_text =
  set_plain_text demo.selection_status_text status;
  ignore_ok
    (Text.set_styled_text demo.selection_start_text
       (S.create [ S.chunk ~fg:selection_start_color start_text ]));
  ignore_ok
    (Text.set_styled_text demo.selection_middle_text
       (S.create [ S.chunk ~fg:selection_middle_color middle ]));
  ignore_ok
    (Text.set_styled_text demo.selection_end_text
       (S.create [ S.chunk ~fg:selection_start_color end_text ]))

let update_selection_status demo selection =
  match selection with
  | None ->
      set_selection_display demo ~status:"Empty selection" ~start_text:""
        ~middle:"" ~end_text:""
  | Some selection ->
      let selected_text = O.Lib.Selection.selected_text selection in
      if String.equal selected_text "" then
        set_selection_display demo ~status:"Empty selection" ~start_text:""
          ~middle:"" ~end_text:""
      else
        let lines = String.split_on_char '\n' selected_text in
        let line_count = List.length lines in
        let total_length = javascript_char_count selected_text in
        if Int.compare line_count 1 > 0 then begin
          let first_line =
            match lines with
            | first :: _ -> first
            | [] -> ""
          in
          let last_line =
            match List.rev lines with
            | last :: _ -> last
            | [] -> ""
          in
          set_selection_display demo
            ~status:(Printf.sprintf "Selected %d lines (%d chars):" line_count
                       total_length)
            ~start_text:first_line ~middle:"..." ~end_text:last_line
        end
        else if Int.compare total_length 60 > 0 then
          let suffix_start =
            let count = codepoint_count selected_text in
            if Int.compare count 30 > 0 then count - 30 else 0
          in
          set_selection_display demo
            ~status:(Printf.sprintf "Selected %d chars:" total_length)
            ~start_text:(codepoint_substring selected_text ~start:0 ~length:30)
            ~middle:"..."
            ~end_text:
              (codepoint_substring selected_text ~start:suffix_start ~length:30)
        else
          set_selection_display demo
            ~status:(Printf.sprintf "Selected %d chars:" total_length)
            ~start_text:(Printf.sprintf "\"%s\"" selected_text) ~middle:""
            ~end_text:""

let update_footer demo =
  let truncate_status =
    if demo.truncate_enabled then "ENABLED" else "DISABLED"
  in
  let truncate_color =
    if demo.truncate_enabled then green_color else yellow_color
  in
  let wrap_color =
    match demo.wrap_mode with
    | O.Text_buffer_view.No_wrap -> yellow_color
    | O.Text_buffer_view.Char | O.Text_buffer_view.Word -> blue_color
  in
  let bold = O.Lib.Text_attributes.bold in
  let content =
    S.create
      [
        S.chunk "Truncate: ";
        S.chunk ~fg:truncate_color ~attributes:bold truncate_status;
        S.chunk " | Wrap: ";
        S.chunk ~fg:wrap_color ~attributes:bold (wrap_mode_name demo.wrap_mode);
        S.chunk " | ";
        S.chunk ~fg:blue_color "T";
        S.chunk ": toggle truncate | ";
        S.chunk ~fg:blue_color "W";
        S.chunk ": cycle wrap | ";
        S.chunk ~fg:blue_color "R";
        S.chunk ": resize | ";
        S.chunk ~fg:blue_color "C";
        S.chunk ": clear selection | ";
        S.chunk ~fg:blue_color "Ctrl+C";
        S.chunk ": exit";
      ]
  in
  ignore_ok (Text.set_styled_text demo.footer_text content)

let toggle_truncation demo =
  demo.truncate_enabled <- not demo.truncate_enabled;
  List.iter
    (fun text -> ignore_ok (Text.set_truncate text demo.truncate_enabled))
    demo.text_elements;
  update_footer demo

let cycle_wrap_mode demo =
  let next_mode =
    match demo.wrap_mode with
    | O.Text_buffer_view.No_wrap -> O.Text_buffer_view.Char
    | O.Text_buffer_view.Char -> O.Text_buffer_view.Word
    | O.Text_buffer_view.Word -> O.Text_buffer_view.No_wrap
  in
  demo.wrap_mode <- next_mode;
  List.iter
    (fun text -> ignore_ok (Text.set_wrap_mode text next_mode))
    demo.text_elements;
  update_footer demo

let toggle_column_sizes demo =
  match demo.column_size with
  | Equal ->
      set_flex_grow (Box.as_renderable demo.left_column) 2.0;
      set_flex_grow (Box.as_renderable demo.right_column) 1.0;
      demo.column_size <- Left_larger
  | Left_larger ->
      set_flex_grow (Box.as_renderable demo.left_column) 1.0;
      set_flex_grow (Box.as_renderable demo.right_column) 2.0;
      demo.column_size <- Right_larger
  | Right_larger ->
      set_flex_grow (Box.as_renderable demo.left_column) 1.0;
      set_flex_grow (Box.as_renderable demo.right_column) 1.0;
      demo.column_size <- Equal

let clear_selection demo =
  ignore_ok (O.Renderer.clear_selection demo.renderer);
  set_selection_display demo ~status:"Selection cleared" ~start_text:""
    ~middle:"" ~end_text:""

let handle_key demo event =
  if not demo.destroyed then
    match Handler.key_event_kind event with
    | Handler.Keyrelease | Handler.Paste -> ()
    | Handler.Keypress ->
        let modifiers = Handler.key_modifiers event in
        if not modifiers.ctrl && not modifiers.meta then
          match Handler.key event with
          | Key.Character bytes -> (
              match String.lowercase_ascii (Bytes.to_string bytes) with
              | "t" -> toggle_truncation demo
              | "w" -> cycle_wrap_mode demo
              | "r" -> toggle_column_sizes demo
              | "c" -> clear_selection demo
              | _ -> ())
          | Key.Named _ -> ()

let create_panel_text context panel ~id ~foreground content =
  let text = create_text context ~id ~selectable:true ~foreground content in
  add_text_child panel text;
  text

let create_demo renderer =
  ignore_ok (O.Renderer.set_background_color renderer ~color:background_color);
  let context = O.Renderer.context renderer in
  let main_container =
    expect_ok
      (Box.create context ~id:"main-container"
         ~background_color:background_color ())
  in
  set_flex_direction (Box.as_renderable main_container) O.Yoga.Flex_column;
  set_flex_grow (Box.as_renderable main_container) 1.0;
  add_child (O.Renderer.children renderer) (Box.as_renderable main_container);

  let header =
    expect_ok
      (Box.create context ~id:"header" ~background_color:panel_color
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders
         ~border_color ())
  in
  set_height (Box.as_renderable header) 3.0;
  ignore_ok
    (O.Renderable.set_align_items (Box.as_renderable header)
       O.Yoga.Align_center);
  ignore_ok
    (O.Renderable.set_justify_content (Box.as_renderable header)
       O.Yoga.Justify_center);
  add_box_child main_container header;
  let header_text =
    create_text context ~id:"header-text" ~foreground:blue_color
      (S.of_string "Text Truncation Demo - Press 'T' to toggle truncation")
  in
  add_text_child header header_text;

  let content_area =
    expect_ok
      (Box.create context ~id:"content-area" ~gap:(O.Yoga.Point 1.0) ())
  in
  set_flex_direction (Box.as_renderable content_area) O.Yoga.Flex_row;
  set_flex_grow (Box.as_renderable content_area) 1.0;
  set_padding (Box.as_renderable content_area) 1.0;
  add_box_child main_container content_area;

  let left_column =
    expect_ok
      (Box.create context ~id:"left-column" ~gap:(O.Yoga.Point 1.0) ())
  in
  set_flex_direction (Box.as_renderable left_column) O.Yoga.Flex_column;
  set_flex_grow (Box.as_renderable left_column) 1.0;
  (* Let flex-grow, rather than long no-wrap children, determine the ratio. *)
  set_flex_basis (Box.as_renderable left_column) 0.0;
  add_box_child content_area left_column;

  let right_column =
    expect_ok
      (Box.create context ~id:"right-column" ~gap:(O.Yoga.Point 1.0) ())
  in
  set_flex_direction (Box.as_renderable right_column) O.Yoga.Flex_column;
  set_flex_grow (Box.as_renderable right_column) 1.0;
  set_flex_basis (Box.as_renderable right_column) 0.0;
  add_box_child content_area right_column;

  let single_line_box1 =
    create_panel context ~id:"single-line-box-1"
      ~title:"Single Line Text 1" ~border:Box.all_borders ~border_color:blue_color
      ~min_height:5 ()
  in
  add_box_child left_column single_line_box1;
  let single_line_text1 =
    create_panel_text context single_line_box1 ~id:"single-line-text-1"
      ~foreground:default_text_color
      (S.of_string
         "This is a very long single line of text that will definitely exceed the width of most terminal windows and should be truncated when truncation is enabled")
  in

  let single_line_box2 =
    create_panel context ~id:"single-line-box-2"
      ~title:"Single Line Text 2" ~border:Box.all_borders ~border_color:green_color
      ~min_height:5 ()
  in
  add_box_child left_column single_line_box2;
  let single_line_text2 =
    create_panel_text context single_line_box2 ~id:"single-line-text-2"
      ~foreground:green_color
      (S.of_string "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz")
  in

  let single_line_box3 =
    create_panel context ~id:"single-line-box-3"
      ~title:"Single Line Text 3 (Unicode)" ~border:Box.all_borders
      ~border_color:yellow_color ~min_height:7 ()
  in
  add_box_child left_column single_line_box3;
  let single_line_text3 =
    create_panel_text context single_line_box3 ~id:"single-line-text-3"
      ~foreground:yellow_color
      (S.of_string
         "🌟 Unicode test: こんにちは世界 Hello World 你好世界 안녕하세요 🚀 More emoji: 🎨🎭🎪🎬🎮🎯")
  in

  let multiline_box1 =
    create_panel context ~id:"multiline-box-1"
      ~title:"Multiline Text (Word Wrap)" ~border:Box.all_borders
      ~border_color:pink_color ~flex_grow:1.0 ()
  in
  add_box_child right_column multiline_box1;
  let multiline_text1 =
    create_panel_text context multiline_box1 ~id:"multiline-text-1"
      ~foreground:pink_color
      (S.of_string
         "This is a multiline text block that demonstrates how truncation works with word wrapping enabled. Each line that exceeds the viewport width will be truncated independently. Try resizing the terminal to see how it behaves!")
  in

  let multiline_box2 =
    create_panel context ~id:"multiline-box-2" ~title:"Multiline Text"
      ~border:Box.all_borders ~border_color:purple_color ~flex_grow:1.0 ()
  in
  add_box_child right_column multiline_box2;
  let multiline_text2 =
    create_panel_text context multiline_box2 ~id:"multiline-text-2"
      ~foreground:purple_color
      (S.of_string
         "Line 1: This is a long line without wrapping\nLine 2: Another very long line that will be truncated when enabled\nLine 3: Short line\nLine 4: Yet another extremely long line with lots of text to demonstrate middle truncation behavior")
  in

  let styled_box =
    create_panel context ~id:"styled-box"
      ~title:"Styled Text with Truncation" ~border:Box.all_borders
      ~border_color:red_color ~flex_grow:1.0 ()
  in
  add_box_child right_column styled_box;
  let styled_text =
    create_panel_text context styled_box ~id:"styled-text"
      ~foreground:default_text_color
      (S.create
         [
           S.chunk ~fg:blue_color ~attributes:O.Lib.Text_attributes.bold
             "Bold Cyan:";
           S.chunk " ";
           S.chunk ~fg:yellow_color "Yellow text";
           S.chunk " ";
           S.chunk ~fg:(color "#d2a8ff") "and magenta";
           S.chunk " ";
           S.chunk ~fg:green_color "with green parts";
           S.chunk " and more styled text that goes on and on";
         ])
  in

  let footer =
    expect_ok
      (Box.create context ~id:"footer" ~background_color:panel_color
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders
         ~border_color ())
  in
  set_height (Box.as_renderable footer) 3.0;
  ignore_ok
    (O.Renderable.set_align_items (Box.as_renderable footer)
       O.Yoga.Align_center);
  ignore_ok
    (O.Renderable.set_justify_content (Box.as_renderable footer)
       O.Yoga.Justify_center);
  add_box_child main_container footer;
  let footer_text =
    create_text context ~id:"footer-text" ~foreground:muted_color
      (S.of_string "")
  in
  add_text_child footer footer_text;

  let selection_box =
    expect_ok
      (Box.create context ~id:"selection-box" ~background_color
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders
         ~border_color ~title:"Selection"
         ~title_alignment:O.Lib.Border.Left ())
  in
  set_height (Box.as_renderable selection_box) 7.0;
  set_flex_direction (Box.as_renderable selection_box) O.Yoga.Flex_column;
  set_gap (Box.as_renderable selection_box) 1.0;
  set_padding (Box.as_renderable selection_box) 1.0;
  add_box_child main_container selection_box;
  let selection_status_text =
    create_text context ~id:"selection-status-text" ~foreground:muted_color
      (S.of_string "Select text to see details here")
  in
  add_text_child selection_box selection_status_text;
  let selection_start_text =
    create_text context ~id:"selection-start-text" ~foreground:selection_start_color
      (S.of_string "")
  in
  add_text_child selection_box selection_start_text;
  let selection_middle_text =
    create_text context ~id:"selection-middle-text"
      ~foreground:selection_middle_color (S.of_string "")
  in
  add_text_child selection_box selection_middle_text;
  let selection_end_text =
    create_text context ~id:"selection-end-text" ~foreground:selection_start_color
      (S.of_string "")
  in
  add_text_child selection_box selection_end_text;

  let live_lease = expect_ok (O.Renderer.acquire_live_lease renderer) in
  let demo =
    {
      renderer;
      main_container;
      left_column;
      right_column;
      footer_text;
      selection_status_text;
      selection_start_text;
      selection_middle_text;
      selection_end_text;
      text_elements =
        [
          single_line_text1;
          single_line_text2;
          single_line_text3;
          multiline_text1;
          multiline_text2;
          styled_text;
        ];
      truncate_enabled = false;
      wrap_mode = O.Text_buffer_view.No_wrap;
      column_size = Equal;
      key_subscription = None;
      selection_subscription = None;
      live_lease = Some live_lease;
      destroyed = false;
    }
  in
  update_footer demo;
  let selection_subscription =
    expect_ok
      (O.Renderer.on_selection renderer (fun selection ->
           if not demo.destroyed then update_selection_status demo selection))
  in
  demo.selection_subscription <- Some selection_subscription;
  let key_subscription =
    expect_ok (O.Renderer.on_keypress renderer (handle_key demo))
  in
  demo.key_subscription <- Some key_subscription;
  demo

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    Option.iter O.Event_subscription.cancel demo.selection_subscription;
    Option.iter O.Renderer.release_live_lease demo.live_lease;
    ignore_ok (O.Renderer.clear_selection demo.renderer);
    Box.destroy_recursively demo.main_container;
    demo.key_subscription <- None;
    demo.selection_subscription <- None;
    demo.live_lease <- None
  end

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  let demo = create_demo renderer in
  ignore_ok
    (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo));
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
    ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~target_frames_per_second:30
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard)
