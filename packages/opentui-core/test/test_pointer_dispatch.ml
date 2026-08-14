open Windtrap

module Core = Opentui_core
module Mouse = Core.Lib.Mouse_decoder
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Box = Core.Renderables.Box

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let modifiers = { Mouse.shift = false; alt = false; ctrl = false }

let mouse kind ~x ~y ~button =
  Core.Lib.Stdin_parser.Mouse
    {
      raw = Bytes.empty;
      encoding = Mouse.Sgr;
      event = { Mouse.kind; button; x; y; modifiers; scroll = None };
    }

let () =
  run "opentui-core-pointer-dispatch"
    [
      test "hit-grid targets bubble from child to parent" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:4l ~height:2l) in
          let context = Renderer.context renderer in
          let parent =
            expect_ok (Box.create context ~id:"parent" ())
          in
          let child =
            expect_ok (Box.create context ~id:"child" ~focusable:true ())
          in
          ignore (expect_ok (Box.set_width parent (Core.Yoga.Point 4.0)));
          ignore (expect_ok (Box.set_height parent (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_width child (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_height child (Core.Yoga.Point 1.0)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Box.as_renderable parent)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Box.children parent)
                  (Box.as_renderable child)));
          let calls = ref [] in
          let child_node = Box.as_renderable child in
          let parent_node = Box.as_renderable parent in
          ignore
            (expect_ok
               (Renderable.set_on_mouse_down child_node
                  (Some (fun event ->
                       calls :=
                         ("child",
                          Option.get (Renderable.mouse_current_target event)
                          == child_node,
                          Option.get (Renderable.mouse_target event) == child_node)
                         :: !calls))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_down parent_node
                  (Some (fun event ->
                       calls :=
                         ("parent",
                          Option.get (Renderable.mouse_current_target event)
                          == parent_node,
                          Option.get (Renderable.mouse_target event) == child_node)
                         :: !calls))));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let hit = expect_ok (Renderer.hit_test renderer ~x:0 ~y:0) in
          equal bool true (match hit with Some value -> value == child_node | None -> false);
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          (match List.rev !calls with
          | [ ("child", true, true); ("parent", true, true) ] -> ()
          | _ -> fail "pointer event did not bubble with stable target/current_target");
          equal bool true (Renderable.focused child_node);
          Renderer.destroy renderer);
      test "drag capture routes completion and drop to the captured source" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:4l ~height:2l) in
          let context = Renderer.context renderer in
          let parent = expect_ok (Box.create context ~id:"parent" ()) in
          let child = expect_ok (Box.create context ~id:"child" ()) in
          ignore (expect_ok (Box.set_width parent (Core.Yoga.Point 4.0)));
          ignore (expect_ok (Box.set_height parent (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_width child (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_height child (Core.Yoga.Point 1.0)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Box.as_renderable parent)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Box.children parent)
                  (Box.as_renderable child)));
          let calls = ref [] in
          let child_node = Box.as_renderable child in
          let parent_node = Box.as_renderable parent in
          let record name event =
            calls :=
              (name,
               Option.map Renderable.num (Renderable.mouse_source event),
               Option.map Renderable.num (Renderable.mouse_target event),
               Renderable.mouse_current_target event |> Option.map Renderable.num)
              :: !calls
          in
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drag child_node
                  (Some (record "drag"))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drag_end child_node
                  (Some (record "drag-end"))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_up child_node
                  (Some (record "up"))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drop parent_node
                  (Some (record "drop"))));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Drag ~x:0 ~y:0 ~button:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Drag ~x:3 ~y:0 ~button:0)));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Up ~x:3 ~y:0 ~button:0)));
          (match List.rev !calls with
          | [ ("drag", None, Some target_first, Some current_first);
              ("drag", None, Some target_second, Some current_second);
              ("drag-end", None, Some target_end, Some current_end);
              ("up", None, Some target_up, Some current_up);
              ("drop", Some source_drop, Some target_drop, Some current_drop) ] ->
              equal int (Renderable.num child_node) target_first;
              equal int (Renderable.num child_node) current_first;
              equal int (Renderable.num child_node) target_second;
              equal int (Renderable.num child_node) current_second;
              equal int (Renderable.num child_node) target_end;
              equal int (Renderable.num child_node) current_end;
              equal int (Renderable.num child_node) target_up;
              equal int (Renderable.num child_node) current_up;
              equal int (Renderable.num child_node) source_drop;
              equal int (Renderable.num parent_node) target_drop;
              equal int (Renderable.num parent_node) current_drop
          | _ -> fail "drag capture did not produce the reference event sequence");
          Renderer.destroy renderer);
      test "pointer callback failures publish handler errors" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let context = Renderer.context renderer in
          let box = expect_ok (Box.create context ()) in
          ignore (expect_ok (Box.set_width box (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_height box (Core.Yoga.Point 1.0)));
          let node = Box.as_renderable box in
          ignore
            (expect_ok (Core.Layout_children.add (Renderer.children renderer) node));
          let errors = ref 0 in
          ignore
            (expect_ok
               (Renderer.on_handler_error renderer (fun error ->
                    match error.Core.Renderer.kind with
                    | Core.Renderer.Mouse -> errors := !errors + 1
                    | Core.Renderer.Keypress | Core.Renderer.Keyrelease
                    | Core.Renderer.Paste -> ())));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_down node
                  (Some (fun _ -> raise (Failure "mouse handler failure")))));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          equal int 1 !errors;
          Renderer.destroy renderer);
      test "a committed grid rechecks a stationary pointer" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let box = expect_ok (Box.create (Renderer.context renderer) ()) in
          ignore (expect_ok (Box.set_width box (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_height box (Core.Yoga.Point 1.0)));
          let node = Box.as_renderable box in
          ignore
            (expect_ok (Core.Layout_children.add (Renderer.children renderer) node));
          let over_count = ref 0 in
          ignore
            (expect_ok
               (Renderable.set_on_mouse_over node
                  (Some (fun _ -> over_count := !over_count + 1))));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Move ~x:0 ~y:0 ~button:0)));
          equal int 0 !over_count;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 1 !over_count;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 1 !over_count;
          Renderer.destroy renderer);
      test "destroyed hover targets do not receive a later out event" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let box = expect_ok (Box.create (Renderer.context renderer) ()) in
          ignore (expect_ok (Box.set_width box (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_height box (Core.Yoga.Point 1.0)));
          let node = Box.as_renderable box in
          ignore
            (expect_ok (Core.Layout_children.add (Renderer.children renderer) node));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Move ~x:0 ~y:0 ~button:0)));
          let out_count = ref 0 in
          ignore
            (expect_ok
               (Renderable.set_on_mouse_out node
                  (Some (fun _ -> out_count := !out_count + 1))));
          Renderable.destroy node;
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Move ~x:0 ~y:0 ~button:0)));
          equal int 0 !out_count;
          Renderer.destroy renderer);
      test "resize drops pointer capture" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let box = expect_ok (Box.create (Renderer.context renderer) ()) in
          ignore (expect_ok (Box.set_width box (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_height box (Core.Yoga.Point 1.0)));
          let node = Box.as_renderable box in
          ignore
            (expect_ok (Core.Layout_children.add (Renderer.children renderer) node));
          let drag_end_count = ref 0 in
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drag_end node
                  (Some (fun _ -> drag_end_count := !drag_end_count + 1))));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:0 ~y:0 ~button:0)));
          ignore (expect_ok (Renderer.resize renderer ~width:3l ~height:1l));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:0 ~y:0 ~button:0)));
          equal int 0 !drag_end_count;
          Renderer.destroy renderer);
      test "a destroyed mousedown target does not turn focus into an input error" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let box =
            expect_ok (Box.create (Renderer.context renderer) ~focusable:true ())
          in
          ignore (expect_ok (Box.set_width box (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Box.set_height box (Core.Yoga.Point 1.0)));
          let node = Box.as_renderable box in
          ignore
            (expect_ok (Core.Layout_children.add (Renderer.children renderer) node));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_down node
                  (Some (fun _ -> Renderable.destroy node))));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          equal bool true (Renderable.is_destroyed node);
          Renderer.destroy renderer);
    ]
