open Windtrap

module Core = Opentui_core
module Decoder = Core.Lib.Key_decoder
module Mouse = Core.Lib.Mouse_decoder
module Renderer = Core.Renderer
module Renderable = Core.Renderable

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let modifiers ?(shift = false) ?(meta = false) ?(ctrl = false) () =
  { Decoder.shift; meta; ctrl }

let key ?(shift = false) ?(meta = false) ?(ctrl = false) value =
  Core.Lib.Stdin_parser.Key
    {
      raw = Bytes.empty;
      key = value;
      modifiers = modifiers ~shift ~meta ~ctrl ();
      metadata = Decoder.raw_metadata;
    }

let character ?(shift = false) ?(meta = false) ?(ctrl = false) value =
  key ~shift ~meta ~ctrl (Decoder.Character (Bytes.of_string value))

let attach renderer renderable =
  ignore
    (expect_ok
       (Core.Layout_children.add (Renderer.children renderer) renderable))

let mouse kind ~x ~y =
  Core.Lib.Stdin_parser.Mouse
    {
      raw = Bytes.empty;
      encoding = Mouse.Sgr;
      event =
        {
          Mouse.kind;
          button = 0;
          x;
          y;
          modifiers = { Mouse.shift = false; alt = false; ctrl = false };
          scroll = None;
        };
    }

let option name description =
  { Core.Renderables.Select.name; description; value = Some name }

let () =
  run "opentui-core-interactive-controls"
    [
      test "native line info and standalone pointer selection stay coherent" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:12l ~height:4l ()) in
          let text =
            expect_ok
              (Core.Renderables.Text_buffer_renderable.create
                 (Renderer.context renderer) ~wrap_mode:Core.Text_buffer_view.Char
                 ~selectable:true ())
          in
          let renderable = Core.Renderables.Text_buffer_renderable.as_renderable text in
          ignore (expect_ok (Renderable.set_width renderable (Core.Yoga.Point 3.0)));
          ignore (expect_ok (Renderable.set_height renderable (Core.Yoga.Point 2.0)));
          attach renderer renderable;
          ignore (expect_ok (Core.Renderables.Text_buffer_renderable.set_text text "abcdef"));
          ignore (expect_ok (Core.Renderables.Text_buffer_renderable.set_viewport_size text ~width:3 ~height:2));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let wrapped = expect_ok (Core.Renderables.Text_buffer_renderable.line_info text) in
          equal int 2 (Array.length wrapped.line_width_cols);
          equal int 3 wrapped.line_width_cols.(0);
          equal int 3 wrapped.line_width_cols.(1);
          let logical = expect_ok (Core.Renderables.Text_buffer_renderable.logical_line_info text) in
          equal int 2 (Array.length logical.line_width_cols);
          equal int 3 logical.line_width_cols.(0);
          equal int 3 logical.line_width_cols.(1);
          ignore (expect_ok (Core.Renderables.Text_buffer_renderable.set_wrap_mode text Core.Text_buffer_view.Word));
          ignore
            (expect_ok
               (Core.Renderables.Text_buffer_renderable.set_text text
                  "Hello world this is a test"));
          ignore (expect_ok (Core.Renderables.Text_buffer_renderable.set_viewport_size text ~width:12 ~height:4));
          let word_wrapped = expect_ok (Core.Renderables.Text_buffer_renderable.line_info text) in
          equal bool true (Array.length word_wrapped.line_width_cols > 1);
          equal int 26 word_wrapped.line_width_cols_max;
          equal bool true
            (Array.for_all
               (fun width -> width <= 12)
               word_wrapped.line_width_cols);
          let editor_buffer = Core.Edit_buffer.create Core.Edit_buffer.Unicode in
          ignore (expect_ok (Core.Edit_buffer.set_text editor_buffer "ABCDEFGHIJKLMNOPQRSTUVWXYZ"));
          let editor_view = Core.Editor_view.create editor_buffer ~viewport_width:10 ~viewport_height:4 in
          Core.Editor_view.set_wrap_mode editor_view Core.Editor_view.Char;
          let editor_info = Core.Editor_view.line_info editor_view in
          equal int 3 (Array.length editor_info.line_width_cols);
          equal int 10 editor_info.line_start_cols.(1);
          equal int 20 editor_info.line_start_cols.(2);
          equal int 6 editor_info.line_width_cols.(2);
          equal int 26 editor_info.line_width_cols_max;
          ignore
            (expect_ok
               (Core.Edit_buffer.set_text editor_buffer
                  "Hello world this is a test"));
          Core.Editor_view.set_wrap_mode editor_view Core.Editor_view.Word;
          let editor_word_info = Core.Editor_view.line_info editor_view in
          equal bool true (Array.length editor_word_info.line_width_cols > 1);
          equal bool true
            (Array.for_all
               (fun width -> width <= 10)
               editor_word_info.line_width_cols);
          Core.Editor_view.destroy editor_view;
          Core.Edit_buffer.destroy editor_buffer;
          ignore (expect_ok (Core.Renderables.Text_buffer_renderable.set_wrap_mode text Core.Text_buffer_view.Char));
          ignore (expect_ok (Core.Renderables.Text_buffer_renderable.set_text text "abcdef"));
          ignore (expect_ok (Core.Renderables.Text_buffer_renderable.set_viewport_size text ~width:3 ~height:2));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:1 ~y:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Drag ~x:2 ~y:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Up ~x:2 ~y:0)));
          equal string "b" (expect_ok (Core.Renderables.Text_buffer_renderable.selected_text text));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:0 ~y:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Drag ~x:20 ~y:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Up ~x:20 ~y:0)));
          equal string "abc" (expect_ok (Core.Renderables.Text_buffer_renderable.selected_text text));
          Core.Renderables.Text_buffer_renderable.destroy text;
          Renderer.destroy renderer);
      test "input owns focused keyboard and paste constraints and events" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:16l ~height:3l ()) in
          let input =
            expect_ok
              (Core.Renderables.Input.create (Renderer.context renderer)
                 ~value:"a\nb" ~min_length:2 ~max_length:4 ())
          in
          let node = Core.Renderables.Input.as_renderable input in
          ignore (expect_ok (Renderable.set_width node (Core.Yoga.Point 10.0)));
          attach renderer node;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let inputs = ref [] in
          let changes = ref [] in
          let enters = ref [] in
          ignore
            (Core.Renderables.Input.on_input input (fun value -> inputs := value :: !inputs));
          ignore
            (Core.Renderables.Input.on_change input (fun value -> changes := value :: !changes));
          ignore
            (Core.Renderables.Input.on_enter input (fun value -> enters := value :: !enters));
          ignore (expect_ok (Renderable.focus node));
          ignore (expect_ok (Renderer.handle_input renderer (character "c")));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (character ~ctrl:true "a")));
          let cursor = expect_ok (Core.Renderables.Input.cursor input) in
          equal int 0 cursor.col;
          ignore (expect_ok (Core.Renderables.Input.goto_buffer_end input ()));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (Core.Lib.Stdin_parser.Paste
                     (Bytes.of_string "\027[31mXYZ\n\027[0m"))));
          equal string "abcX" (expect_ok (Core.Renderables.Input.value input));
          equal int 2 (List.length !inputs);
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (key (Decoder.Named Decoder.Return))));
          equal int 1 (List.length !changes);
          equal int 1 (List.length !enters);
          equal string "abcX" (List.hd !enters);
          Core.Renderables.Input.destroy input;
          Renderer.destroy renderer);
      test "textarea selection editing and submit remain typed" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:12l ~height:5l ()) in
          let submitted = ref 0 in
          let textarea =
            expect_ok
              (Core.Renderables.Textarea.create (Renderer.context renderer)
                 ~initial_value:"hello" ~wrap_mode:Core.Text_buffer_view.Char
                 ~on_submit:(fun () -> incr submitted) ())
          in
          let node = Core.Renderables.Textarea.as_renderable textarea in
          ignore (expect_ok (Renderable.set_width node (Core.Yoga.Point 4.0)));
          ignore (expect_ok (Renderable.set_height node (Core.Yoga.Point 2.0)));
          attach renderer node;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:1 ~y:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Drag ~x:3 ~y:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Up ~x:3 ~y:0)));
          equal string "el" (expect_ok (Core.Renderables.Textarea.selected_text textarea));
          ignore (expect_ok (Core.Renderables.Textarea.set_selection textarea ~start:1 ~end_:4));
          equal string "ell" (expect_ok (Core.Renderables.Textarea.selected_text textarea));
          ignore (expect_ok (Core.Renderables.Textarea.insert_text textarea "X"));
          equal string "hXo" (expect_ok (Core.Renderables.Textarea.text textarea));
          ignore (expect_ok (Core.Renderables.Textarea.submit textarea));
          equal int 1 !submitted;
          Core.Renderables.Textarea.destroy textarea;
          Renderer.destroy renderer);
      test "select and tab-select movement follow their directional contracts" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:24l ~height:8l ()) in
          let options = [ option "one" "first"; option "two" "second"; option "three" "third" ] in
          let select =
            expect_ok
              (Core.Renderables.Select.create (Renderer.context renderer) ~options
                 ~width:(Core.Yoga.Point 12.0) ~height:(Core.Yoga.Point 6.0) ())
          in
          let select_node = Core.Renderables.Select.as_renderable select in
          attach renderer select_node;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let selected = ref [] in
          let activated = ref [] in
          ignore
            (Core.Renderables.Select.on_selection_changed select (fun change -> selected := change.index :: !selected));
          ignore
            (Core.Renderables.Select.on_item_selected select (fun change -> activated := change.index :: !activated));
          ignore (expect_ok (Renderable.focus select_node));
          ignore (expect_ok (Renderer.handle_input renderer (key (Decoder.Named Decoder.Down))));
          ignore (expect_ok (Renderer.handle_input renderer (key (Decoder.Named Decoder.Down) ~shift:true)));
          equal int 2 (Core.Renderables.Select.selected_index select);
          ignore (expect_ok (Renderer.handle_input renderer (key (Decoder.Named Decoder.Return))));
          equal int 1 (List.length !activated);
          equal int 2 (List.hd !activated);
          let tabs =
            expect_ok
              (Core.Renderables.Tab_select.create (Renderer.context renderer) ~options
                 ~width:(Core.Yoga.Point 20.0) ())
          in
          let tab_node = Core.Renderables.Tab_select.as_renderable tabs in
          attach renderer tab_node;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore (expect_ok (Renderable.focus tab_node));
          ignore (expect_ok (Renderer.handle_input renderer (key (Decoder.Named Decoder.Right))));
          equal int 1 (Core.Renderables.Tab_select.selected_index tabs);
          Core.Renderables.Select.destroy select;
          Core.Renderables.Tab_select.destroy tabs;
          Renderer.destroy renderer);
      test "scrollbar, scrollbox, and slider preserve scroll ownership" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:20l ~height:8l ()) in
          let bar =
            expect_ok
              (Core.Renderables.Scroll_bar.create (Renderer.context renderer)
                 ~orientation:Core.Renderables.Scroll_bar.Vertical ())
          in
          let bar_node = Core.Renderables.Scroll_bar.as_renderable bar in
          ignore (expect_ok (Renderable.set_height bar_node (Core.Yoga.Point 5.0)));
          attach renderer bar_node;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_viewport_size bar 3.0));
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_scroll_size bar 10.0));
          equal bool true (Core.Renderables.Scroll_bar.visible bar);
          let bar_changes = ref [] in
          ignore
            (Core.Renderables.Scroll_bar.on_change bar (fun value -> bar_changes := value :: !bar_changes));
          ignore (expect_ok (Core.Renderables.Slider.set_value (Core.Renderables.Scroll_bar.slider bar) 2.6));
          equal (float 0.0001) 3.0 (Core.Renderables.Scroll_bar.scroll_position bar);
          equal (float 0.0001) 3.0 (List.hd !bar_changes);
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_scroll_position bar 0.0));
          ignore (expect_ok (Core.Renderables.Scroll_bar.scroll_by bar 1.0 Core.Renderables.Scroll_bar.Viewport));
          equal (float 0.0001) 3.0 (Core.Renderables.Scroll_bar.scroll_position bar);
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_scroll_size bar 2.0));
          equal bool false (Core.Renderables.Scroll_bar.visible bar);
          let box =
            expect_ok
              (Core.Renderables.Scroll_box.create (Renderer.context renderer)
                 ~scroll_y:true ~width:(Core.Yoga.Point 10.0)
                 ~height:(Core.Yoga.Point 4.0) ())
          in
          let box_node = Core.Renderables.Scroll_box.as_renderable box in
          attach renderer box_node;
          let vertical = Core.Renderables.Scroll_box.vertical_scrollbar box in
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_viewport_size vertical 3.0));
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_scroll_size vertical 10.0));
          ignore (expect_ok (Core.Renderables.Scroll_box.scroll_by box ~dx:0.0 ~dy:3.0));
          equal (float 0.0001) 3.0 (Core.Renderables.Scroll_box.scroll_top box);
          Core.Renderables.Scroll_bar.destroy bar;
          Core.Renderables.Scroll_box.destroy box;
          Renderer.destroy renderer);
      test "scrollbar layout exposes the docked track to pointer dragging" (fun () ->
          let renderer =
            expect_ok
              (Renderer.create ~output:Renderer.Output.Memory ~width:12l ~height:8l ())
          in
          let bar =
            expect_ok
              (Core.Renderables.Scroll_bar.create (Renderer.context renderer)
                 ~orientation:Core.Renderables.Scroll_bar.Vertical
                 ~width:(Core.Yoga.Point 4.0) ~height:(Core.Yoga.Point 8.0) ())
          in
          let bar_node = Core.Renderables.Scroll_bar.as_renderable bar in
          let slider_node =
            Core.Renderables.Slider.as_renderable
              (Core.Renderables.Scroll_bar.slider bar)
          in
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_viewport_size bar 3.0));
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_scroll_size bar 20.0));
          attach renderer bar_node;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (float 0.0001) 4.0 (Renderable.width bar_node);
          equal (float 0.0001) 2.0 (Renderable.width slider_node);
          equal (float 0.0001) 2.0 (Renderable.screen_x slider_node);
          equal bool true
            (match expect_ok (Renderer.hit_test renderer ~x:3 ~y:0) with
            | Some target -> target == slider_node
            | None -> false);
          equal bool true
            (match expect_ok (Renderer.hit_test renderer ~x:0 ~y:0) with
            | Some target -> target == bar_node
            | None -> false);
          let before = Core.Renderables.Scroll_bar.scroll_position bar in
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:3 ~y:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Drag ~x:3 ~y:7)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Up ~x:3 ~y:7)));
          equal bool true
            (Core.Renderables.Scroll_bar.scroll_position bar > before);
          Core.Renderables.Scroll_bar.destroy bar;
          Renderer.destroy renderer);
      test "scrollbox stretches and commits its scrollbar edge hit target" (fun () ->
          let renderer =
            expect_ok
              (Renderer.create ~output:Renderer.Output.Memory ~width:20l ~height:8l ())
          in
          let box =
            expect_ok
              (Core.Renderables.Scroll_box.create (Renderer.context renderer)
                 ~scroll_y:true ~width:(Core.Yoga.Point 10.0)
                 ~height:(Core.Yoga.Point 4.0) ())
          in
          let content =
            expect_ok (Renderable.Private.create (Renderer.context renderer) ())
          in
          ignore (expect_ok (Renderable.set_width content (Core.Yoga.Point 10.0)));
          ignore (expect_ok (Renderable.set_height content (Core.Yoga.Point 12.0)));
          ignore (expect_ok (Core.Renderables.Scroll_box.add box content));
          attach renderer (Core.Renderables.Scroll_box.as_renderable box);
          for _ = 1 to 3 do
            ignore (expect_ok (Renderer.render renderer ~force:true))
          done;
          let bar = Core.Renderables.Scroll_box.vertical_scrollbar box in
          let bar_node = Core.Renderables.Scroll_bar.as_renderable bar in
          let slider_node =
            Core.Renderables.Slider.as_renderable
              (Core.Renderables.Scroll_bar.slider bar)
          in
          equal bool true (Core.Renderables.Scroll_bar.visible bar);
          let bar_x =
            int_of_float
              (Float.floor
                 (Renderable.screen_x bar_node +. Renderable.width bar_node -. 1.0))
          in
          equal bool true
            (match expect_ok (Renderer.hit_test renderer ~x:bar_x ~y:0) with
            | Some target -> target == slider_node
            | None -> false);
          let before = Core.Renderables.Scroll_box.scroll_top box in
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:bar_x ~y:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Drag ~x:bar_x ~y:3)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Up ~x:bar_x ~y:3)));
          equal bool true (Core.Renderables.Scroll_box.scroll_top box > before);
          Core.Renderables.Scroll_box.destroy box;
          Renderable.destroy content;
          Renderer.destroy renderer);
    ]
