open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Box = Core.Renderables.Box
module Scroll_bar = Core.Renderables.Scroll_bar
module Scroll_box = Core.Renderables.Scroll_box
module Slider = Core.Renderables.Slider
module Yoga = Core.Yoga
module Mouse = Core.Lib.Mouse_decoder

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let no_modifiers = { Mouse.shift = false; alt = false; ctrl = false }

let mouse kind ~x ~y =
  Core.Lib.Stdin_parser.Mouse
    {
      raw = Bytes.empty;
      encoding = Mouse.Sgr;
      event = { Mouse.kind; button = 0; x; y; modifiers = no_modifiers; scroll = None };
    }

let render renderer =
  match expect_ok (Renderer.render renderer ~force:true) with
  | Renderer.Rendered -> ()
  | Renderer.Skipped -> fail "forced ScrollBox audit frame was skipped"
  | Renderer.Failed -> fail "forced ScrollBox audit frame failed"

let assert_hit renderer ~x ~y expected =
  match expect_ok (Renderer.hit_test renderer ~x ~y) with
  | Some actual when actual == expected -> ()
  | Some _ -> fail "committed ScrollBox hit grid returned a different renderable"
  | None -> fail "committed ScrollBox hit grid missed the expected renderable"

let make_item context index =
  let item =
    expect_ok
      (Box.create context ~id:(Printf.sprintf "scroll-audit-item-%d" index) ())
  in
  let renderable = Box.as_renderable item in
  ignore (expect_ok (Renderable.set_width renderable (Yoga.Point 10.0)));
  ignore (expect_ok (Renderable.set_height renderable (Yoga.Point 1.0)));
  renderable

let () =
  run "opentui-core-scrollbox-audit"
    [
      test "scroll geometry, committed hit grid, and slider capture stay aligned"
        (fun () ->
          let renderer =
            expect_ok
              (Renderer.create ~output:Renderer.Output.Memory ~width:12l ~height:8l ())
          in
          let parent =
            expect_ok (Box.create (Renderer.context renderer) ~id:"audit-parent" ())
          in
          let parent_node = Box.as_renderable parent in
          ignore (expect_ok (Renderable.set_width parent_node (Yoga.Point 10.0)));
          ignore (expect_ok (Renderable.set_height parent_node (Yoga.Point 6.0)));
          let make_row height =
            let row = expect_ok (Box.create (Renderer.context renderer) ()) in
            let node = Box.as_renderable row in
            ignore (expect_ok (Renderable.set_width node (Yoga.Percent 100.0)));
            ignore (expect_ok (Renderable.set_height node (Yoga.Point height)));
            ignore (expect_ok (Core.Layout_children.add (Box.children parent) node));
            row
          in
          ignore (make_row 1.0);
          let box =
            expect_ok
              (Scroll_box.create (Renderer.context renderer) ~scroll_y:true
                 ~width:(Yoga.Percent 100.0) ~height:(Yoga.Percent 100.0) ())
          in
          ignore
            (expect_ok
               (Core.Layout_children.add (Box.children parent)
                  (Scroll_box.as_renderable box)));
          let items =
            List.init 6 (fun index ->
                let item = make_item (Renderer.context renderer) index in
                ignore (expect_ok (Scroll_box.add box item));
                item)
          in
          ignore (make_row 1.0);
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  parent_node));
          for _ = 1 to 4 do render renderer done;
          equal (float 0.0001) 6.0 (Scroll_box.scroll_height box);
          if Float.compare (Scroll_box.viewport_height box) 0.0 <= 0 then
            fail
              (Printf.sprintf
                 "nested ScrollBox has no viewport: root=%.1fx%.1f viewport=%.1fx%.1f bar=%.1fx%.1f scroll=%.1f/%.1f"
                 (Renderable.width (Scroll_box.as_renderable box))
                 (Renderable.height (Scroll_box.as_renderable box))
                 (Renderable.width (Scroll_box.viewport box))
                 (Renderable.height (Scroll_box.viewport box))
                 (Renderable.width
                    (Scroll_bar.as_renderable (Scroll_box.vertical_scrollbar box)))
                 (Renderable.height
                    (Scroll_bar.as_renderable (Scroll_box.vertical_scrollbar box)))
                 (Scroll_box.scroll_height box) (Scroll_box.viewport_height box));
          let item_at index = List.nth items index in
          let viewport = Scroll_box.viewport box in
          let bar = Scroll_box.vertical_scrollbar box in
          let bar_node = Scroll_bar.as_renderable bar in
          let slider = Slider.as_renderable (Scroll_bar.slider bar) in
          let root = Scroll_box.as_renderable box in
          let root_right = Renderable.screen_x root +. Renderable.width root in
          let viewport_right =
            Renderable.screen_x viewport +. Renderable.width viewport
          in
          let bar_left = Renderable.screen_x bar_node in
          let bar_right = bar_left +. Renderable.width bar_node in
          let hit_x =
            int_of_float (Float.floor (Renderable.screen_x viewport +. 1.0))
          in
          let hit_y = int_of_float (Float.floor (Renderable.screen_y viewport)) in
          assert_hit renderer ~x:hit_x ~y:hit_y (item_at 0);
          if not (Float.equal bar_left viewport_right) then
            fail "vertical scrollbar is not docked immediately after the viewport";
          if not (Float.equal bar_right root_right) then
            fail "vertical scrollbar does not end at the ScrollBox root edge";
          if Float.compare (Renderable.screen_x slider) bar_left < 0
             || Float.compare
                  (Renderable.screen_x slider +. Renderable.width slider)
                  bar_right > 0
          then fail "slider rectangle is not contained by the scrollbar rectangle";

          let bar_x = int_of_float (Float.floor (bar_right -. 1.0)) in
          let bar_y = int_of_float (Float.floor (Renderable.screen_y bar_node)) in
          assert_hit renderer ~x:bar_x ~y:bar_y slider;

          ignore (expect_ok (Scroll_box.set_scroll_top box 1.0));
          (* The native hit grid is committed only by a successful frame. *)
          assert_hit renderer ~x:hit_x ~y:hit_y (item_at 0);
          render renderer;
          equal (float 0.0001) 1.0 (Scroll_box.scroll_top box);
          equal (float 0.0001) 6.0 (Scroll_box.scroll_height box);
          assert_hit renderer ~x:hit_x ~y:hit_y (item_at 1);

          ignore (expect_ok (Scroll_box.set_scroll_top box 0.0));
          render renderer;
          let before_drag = Scroll_box.scroll_top box in
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:bar_x ~y:bar_y)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:0
                     ~y:(bar_y + int_of_float (Float.floor (Renderable.height bar_node)) - 1))));
          if Float.compare (Scroll_box.scroll_top box) before_drag <= 0 then
            fail "scrollbar drag did not update the owning ScrollBox";
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:0
                     ~y:(bar_y + int_of_float (Float.floor (Renderable.height bar_node)) - 1))));
          Renderer.destroy renderer)
    ]
