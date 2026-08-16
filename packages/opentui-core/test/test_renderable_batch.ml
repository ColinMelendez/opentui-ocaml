open Windtrap

module Core = Opentui_core
module Mouse = Core.Lib.Mouse_decoder
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Renderables = Core.Renderables

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

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

let rec int_list_equal left right =
  match left, right with
  | [], [] -> true
  | left :: left_rest, right :: right_rest ->
      Int.equal left right && int_list_equal left_rest right_rest
  | [], _ | _, [] -> false

let expect_int_list expected actual =
  if not (int_list_equal expected actual) then
    fail
      (Printf.sprintf "expected [%s], got [%s]"
         (String.concat "," (List.map string_of_int expected))
         (String.concat "," (List.map string_of_int actual)))

let frame renderer =
  let output = Bytes.create 4096 in
  let written =
    expect_ok
      (Core.Buffer.write_resolved_chars
         (expect_ok (Renderer.current_buffer renderer)) ~output
         ~add_line_breaks:false)
  in
  Bytes.sub_string output 0 (Int32.to_int written)

let contains source needle =
  let limit = String.length source - String.length needle in
  let found = ref false in
  if limit >= 0 then
    for index = 0 to limit do
      if String.equal (String.sub source index (String.length needle)) needle then
        found := true
    done;
  !found

let () =
  run "opentui-core-renderable-batch"
    [
      test "text-table width allocation preserves upstream priority" (fun () ->
          expect_int_list [ 28; 9 ]
            (Core.Text_table_width.allocate_proportional_column_widths
               ~widths:[ 91; 9 ] ~target_width:37 ~min_width:1);
          expect_int_list [ 4; 3; 3 ]
            (Core.Text_table_width.allocate_proportional_column_widths
               ~widths:[ 7; 7; 7 ] ~target_width:10 ~min_width:3);
          expect_int_list [ 1; 1; 1; 1; 1 ]
            (Core.Text_table_width.allocate_proportional_column_widths
               ~widths:[ 4; 49; 4; 54; 38 ] ~target_width:3 ~min_width:1));
      test "framebuffer owns drawing storage and preserves it through render" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:8l ~height:3l) in
          let value =
            expect_ok
              (Renderables.Frame_buffer.create (Renderer.context renderer)
                 ~width:3 ~height:1 ~respect_alpha:false ())
          in
          ignore
            (expect_ok
               (Core.Owned_buffer.set_cell
                  (Renderables.Frame_buffer.frame_buffer value) ~x:0 ~y:0
                  ~character:(Int32.of_int (Char.code 'X'))
                  ~foreground:Core.Color.white ~background:Core.Color.black
                  ~attributes:0l));
          attach renderer (Renderables.Frame_buffer.as_renderable value);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let rendered = frame renderer in
          if not (String.length rendered > 0 && Char.equal (String.get rendered 0) 'X') then
            fail (Printf.sprintf "unexpected framebuffer output %S" rendered);
          Renderables.Frame_buffer.destroy value;
          (match
             Renderables.Frame_buffer.resize value ~width:2 ~height:1
           with
          | Error Core.Error.Destroyed -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok () -> fail "destroyed framebuffer accepted resize");
          Renderer.destroy renderer);
      test "ascii font helpers measure, clip, and update retained dimensions" (fun () ->
          let measurement = Core.Ascii_font_spec.measure_text ~font:Core.Ascii_font_spec.Tiny "A" in
          equal int 3 measurement.width;
          equal int 2 measurement.height;
          let positions =
            Core.Ascii_font_spec.character_positions ~font:Core.Ascii_font_spec.Tiny
              "AB"
          in
          equal int 3 (Array.length positions);
          equal int 7 positions.(2);
          let renderer = expect_ok (Renderer.create ~width:16l ~height:6l) in
          let font =
            expect_ok
              (Renderables.Ascii_font.create (Renderer.context renderer)
                 ~text:"A" ~font:Core.Ascii_font_spec.Tiny ())
          in
          let node = Renderables.Ascii_font.as_renderable font in
          attach renderer node;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 3 (int_of_float (Renderable.width node));
          ignore (expect_ok (Renderables.Ascii_font.set_text font "AB"));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 7 (int_of_float (Renderable.width node));
          ignore
            (expect_ok
               (Renderer.handle_input renderer (mouse Mouse.Down ~x:0 ~y:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer (mouse Mouse.Drag ~x:2 ~y:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer (mouse Mouse.Up ~x:2 ~y:0)));
          equal bool true (Renderables.Ascii_font.has_selection font);
          equal string "A" (Renderables.Ascii_font.selected_text font);
          Renderables.Ascii_font.destroy font;
          Renderer.destroy renderer);
      test "select renders ASCII-font labels without changing selection events" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:24l ~height:8l) in
          let options =
            [ { Renderables.Select.name = "A"; description = "first"; value = Some "a" };
              { name = "B"; description = "second"; value = Some "b" } ]
          in
          let select =
            expect_ok
              (Renderables.Select.create (Renderer.context renderer) ~options
                 ~font:Core.Ascii_font_spec.Tiny ~width:(Core.Yoga.Point 16.0)
                 ~height:(Core.Yoga.Point 6.0) ())
          in
          let selected = ref [] in
          ignore
            (Renderables.Select.on_selection_changed select (fun change ->
                 selected := change.index :: !selected));
          attach renderer (Renderables.Select.as_renderable select);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (option string) (Some "tiny")
            (Option.map Core.Ascii_font_spec.string_of_name
               (Renderables.Select.font select));
          if not (contains (frame renderer) "▀") then
            fail "Select did not rasterize its font label";
          ignore (expect_ok (Renderables.Select.move_down select ()));
          equal int 1 (Renderables.Select.selected_index select);
          equal int 1 (List.length !selected);
          Renderables.Select.destroy select;
          Renderer.destroy renderer);
      test "time-to-first-draw records once and resets" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:30l ~height:2l) in
          let value =
            expect_ok
              (Renderables.Time_to_first_draw.create (Renderer.context renderer)
                 ~precision:7 ())
          in
          attach renderer (Renderables.Time_to_first_draw.as_renderable value);
          (match Renderables.Time_to_first_draw.runtime_ms value with
          | None -> ()
          | Some _ -> fail "runtime was recorded before the first render");
          ignore (expect_ok (Renderer.render renderer ~force:true));
          (match Renderables.Time_to_first_draw.runtime_ms value with
          | Some runtime -> equal bool true (runtime >= 0.0)
          | None -> fail "first render did not record a runtime");
          let first = Renderables.Time_to_first_draw.runtime_ms value in
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (option (float 0.0001)) first
            (Renderables.Time_to_first_draw.runtime_ms value);
          ignore (expect_ok (Renderables.Time_to_first_draw.reset value));
          equal (option (float 0.0001)) None
            (Renderables.Time_to_first_draw.runtime_ms value);
          Renderables.Time_to_first_draw.destroy value;
          Renderer.destroy renderer);
      test "line-number composition renders logical sources and custom colors" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:20l ~height:4l) in
          let text =
            expect_ok
              (Renderables.Text_buffer_renderable.create
                 (Renderer.context renderer) ~wrap_mode:Core.Text_buffer_view.Char
                 ())
          in
          ignore
            (expect_ok
               (Renderables.Text_buffer_renderable.set_text text
                  "abcdef\nxyz"));
          let line_numbers =
            expect_ok
              (Renderables.Line_number.create (Renderer.context renderer)
                 ~target:(Renderables.Line_number.target_of_text_buffer_renderable text)
                 ~min_width:2 ())
          in
          attach renderer (Renderables.Line_number.as_renderable line_numbers);
          ignore (expect_ok (Renderable.set_width (Renderables.Line_number.as_renderable line_numbers) (Core.Yoga.Point 10.0)));
          ignore (expect_ok (Renderable.set_height (Renderables.Line_number.as_renderable line_numbers) (Core.Yoga.Point 4.0)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let rendered = frame renderer in
          if String.length rendered < 4 then
            fail (Printf.sprintf "unexpected line-number output %S" rendered);
          if not (String.contains rendered '1' && String.contains rendered '2') then
            fail
              (Printf.sprintf
                 "line numbers missing from output %S (gutter x=%g width=%g target x=%g width=%g)"
                 rendered
                 (match Renderables.Line_number.gutter line_numbers with
                 | None -> -1.0
                 | Some gutter -> Renderable.screen_x gutter)
                 (match Renderables.Line_number.gutter line_numbers with
                 | None -> -1.0
                 | Some gutter -> Renderable.width gutter)
                 (Renderable.screen_x (Renderables.Text_buffer_renderable.as_renderable text))
                 (Renderable.width (Renderables.Text_buffer_renderable.as_renderable text)));
          ignore
            (expect_ok
               (Renderables.Line_number.set_show_line_numbers line_numbers false));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal bool false (String.contains (frame renderer) '1');
          ignore
            (expect_ok
               (Renderables.Line_number.set_show_line_numbers line_numbers true));
          Renderables.Line_number.destroy line_numbers;
          Renderer.destroy renderer);
      test "text table measures, draws borders, updates, and selects cells" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:24l ~height:8l) in
          let table =
            expect_ok
              (Renderables.Text_table.create (Renderer.context renderer)
                 ~content:[ [ Renderables.Text_table.Text "one"; Text "two" ]; [ Text "three"; Empty ] ]
                 ~width:(Core.Yoga.Point 16.0) ~height:(Core.Yoga.Point 4.0) ())
          in
          attach renderer (Renderables.Text_table.as_renderable table);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (float 0.0001) 16.0
            (Renderable.width (Renderables.Text_table.as_renderable table));
          let rendered = frame renderer in
          equal bool true (String.contains rendered 'o');
          ignore
            (expect_ok
               (Renderables.Text_table.set_content table
                  [ [ Text "updated" ] ]));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal bool true (String.contains (frame renderer) 'u');
          ignore
            (expect_ok
               (Renderer.handle_input renderer (mouse Mouse.Down ~x:1 ~y:1)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer (mouse Mouse.Drag ~x:2 ~y:1)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer (mouse Mouse.Up ~x:2 ~y:1)));
          equal bool true (expect_ok (Renderables.Text_table.has_selection table));
          equal bool true
            (String.length (expect_ok (Renderables.Text_table.selected_text table)) > 0);
          Renderables.Text_table.destroy table;
          Renderer.destroy renderer);
      test "composition instantiates children into the retained identity tree" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:20l ~height:6l) in
          let child =
            Renderables.Composition.Constructs.box ~id:"child" []
          in
          let root =
            Renderables.Composition.Constructs.box ~id:"root"
              [ child ]
          in
          let mounted =
            expect_ok
              (Renderables.Composition.Vnode.instantiate_one
                 (Renderer.context renderer) root)
          in
          equal string "root" (Renderable.id mounted);
          equal int 1 (Renderable.child_count mounted);
          let child =
            match Renderable.find_child_by_id mounted "child" with
            | Some child -> child
            | None -> fail "composition child was not mounted"
          in
          equal bool true (match Renderable.parent child with Some parent -> parent == mounted | None -> false);
          attach renderer mounted;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          Renderable.destroy_recursively mounted;
          Renderer.destroy renderer);
      test "composition exposes Code and typed styled-text conveniences" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:24l ~height:6l) in
          let styled =
            Renderables.Composition.Constructs.Vstyles.bold
              [ Core.Lib.Styled_text.Text "bold" ]
          in
          let text =
            Renderables.Composition.Constructs.text ~content:styled []
          in
          let code =
            Renderables.Composition.Constructs.code ~content:"code" []
          in
          let text_renderable =
            expect_ok
              (Renderables.Composition.Vnode.instantiate_one
                 (Renderer.context renderer) text)
          in
          let code_renderable =
            expect_ok
              (Renderables.Composition.Vnode.instantiate_one
                 (Renderer.context renderer) code)
          in
          attach renderer text_renderable;
          attach renderer code_renderable;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let rendered = frame renderer in
          if not (String.contains rendered 'b' && String.contains rendered 'c') then
            fail (Printf.sprintf "composition output omitted text or code: %S" rendered);
          (match Core.Lib.Styled_text.chunks styled with
          | [ chunk ] ->
              equal int Core.Lib.Text_attributes.bold chunk.attributes
          | _ -> fail "bold style did not produce one styled chunk");
          Renderable.destroy_recursively text_renderable;
          Renderable.destroy_recursively code_renderable;
          Renderer.destroy renderer);
    ]
