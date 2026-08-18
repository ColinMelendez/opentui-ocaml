open Windtrap

module Core = Opentui_core
module Mouse = Core.Lib.Mouse_decoder
module Selection = Core.Lib.Selection
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Box = Core.Renderables.Box
module Text_buffer_renderable = Core.Renderables.Text_buffer_renderable

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let no_modifiers = { Mouse.shift = false; alt = false; ctrl = false }

let mouse ?(modifiers = no_modifiers) kind ~x ~y ~button =
  Core.Lib.Stdin_parser.Mouse
    {
      raw = Bytes.empty;
      encoding = Mouse.Sgr;
      event = { Mouse.kind; button; x; y; modifiers; scroll = None };
    }

let attach renderer node =
  ignore
    (expect_ok
       (Core.Layout_children.add (Renderer.children renderer) node))

let selectable_text renderer ~id ~left ~width =
  let text =
    expect_ok
      (Text_buffer_renderable.create (Renderer.context renderer) ~id
         ~wrap_mode:Core.Text_buffer_view.Char ~selectable:true ())
  in
  let node = Text_buffer_renderable.as_renderable text in
  ignore (expect_ok (Renderable.set_position_type node Core.Yoga.Position_absolute));
  ignore
    (expect_ok
       (Renderable.set_position node ~edge:Core.Yoga.Left
          (Core.Yoga.Point (float_of_int left))));
  ignore
    (expect_ok
       (Renderable.set_position node ~edge:Core.Yoga.Top (Core.Yoga.Point 0.0)));
  ignore
    (expect_ok
       (Renderable.set_width node (Core.Yoga.Point (float_of_int width))));
  ignore (expect_ok (Renderable.set_height node (Core.Yoga.Point 1.0)));
  ignore (expect_ok (Text_buffer_renderable.set_text text "abcdef"));
  attach renderer node;
  text, node

let () =
  run "opentui-core-pointer-dispatch"
    [
      test "hit-grid targets bubble from child to parent" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:4l ~height:2l ()) in
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
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:4l ~height:2l ()) in
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
          ignore
            (expect_ok
               (Renderable.set_on_mouse_up parent_node
                  (Some (record "target-up"))));
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
              ("target-up", None, Some target_bubbled, Some current_bubbled);
              ("drop", Some source_drop, Some target_drop, Some current_drop);
              ("target-up", None, Some target_release, Some current_release) ] ->
              equal int (Renderable.num child_node) target_first;
              equal int (Renderable.num child_node) current_first;
              equal int (Renderable.num child_node) target_second;
              equal int (Renderable.num child_node) current_second;
              equal int (Renderable.num child_node) target_end;
              equal int (Renderable.num child_node) current_end;
              equal int (Renderable.num child_node) target_up;
              equal int (Renderable.num child_node) current_up;
              equal int (Renderable.num child_node) target_bubbled;
              equal int (Renderable.num parent_node) current_bubbled;
              equal int (Renderable.num child_node) source_drop;
              equal int (Renderable.num parent_node) target_drop;
              equal int (Renderable.num parent_node) current_drop;
              equal int (Renderable.num parent_node) target_release;
              equal int (Renderable.num parent_node) current_release
          | _ -> fail "drag capture did not produce the reference event sequence");
          Renderer.destroy renderer);
      test "destroying a captured renderable releases capture before the next input" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:4l ~height:2l ()) in
          let context = Renderer.context renderer in
          let source = expect_ok (Box.create context ~id:"captured-source" ()) in
          let target = expect_ok (Box.create context ~id:"release-target" ()) in
          List.iter
            (fun box ->
              ignore (expect_ok (Box.set_width box (Core.Yoga.Point 2.0)));
              ignore (expect_ok (Box.set_height box (Core.Yoga.Point 1.0))))
            [ source; target ];
          attach renderer (Box.as_renderable source);
          attach renderer (Box.as_renderable target);
          let source_node = Box.as_renderable source in
          let target_node = Box.as_renderable target in
          let source_drag_end = ref 0 in
          let source_up = ref 0 in
          let target_drop = ref 0 in
          let target_up = ref 0 in
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drag_end source_node
                  (Some (fun _ -> incr source_drag_end))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_up source_node
                  (Some (fun _ -> incr source_up))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drop target_node
                  (Some (fun _ -> incr target_drop))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_up target_node
                  (Some (fun _ -> incr target_up))));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:0 ~y:0 ~button:0)));
          Renderable.destroy source_node;
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:0 ~y:1 ~button:0)));
          equal int 0 !source_drag_end;
          equal int 0 !source_up;
          equal int 0 !target_drop;
          equal int 1 !target_up;
          Renderer.destroy renderer);
      test "selection drags stay hit-tested instead of capturing the start target" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:1l ()) in
          let source_text, source_node =
            selectable_text renderer ~id:"selection-source" ~left:0 ~width:2
          in
          let target_text, target_node =
            selectable_text renderer ~id:"selection-target" ~left:3 ~width:2
          in
          let source_drag = ref 0 in
          let source_drag_end = ref 0 in
          let source_up = ref 0 in
          let target_drag = ref 0 in
          let target_up = ref 0 in
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drag source_node
                  (Some (fun _ -> incr source_drag))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drag_end source_node
                  (Some (fun _ -> incr source_drag_end))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_up source_node
                  (Some (fun _ -> incr source_up))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_drag target_node
                  (Some (fun _ -> incr target_drag))));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_up target_node
                  (Some (fun _ -> incr target_up))));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:1 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:3 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:3 ~y:0 ~button:0)));
          equal int 1 !source_drag;
          equal int 0 !source_drag_end;
          equal int 0 !source_up;
          equal int 1 !target_drag;
          equal int 1 !target_up;
          let selection = expect_ok (Renderer.selection renderer) in
          equal bool true (Option.is_some selection);
          equal bool false (Selection.is_dragging (Option.get selection));
          ignore (expect_ok (Text_buffer_renderable.selected_text source_text));
          ignore (expect_ok (Text_buffer_renderable.selected_text target_text));
          Renderer.destroy renderer);
      test "left down clears selection in empty space but prevention preserves it" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:1l ()) in
          let selectable, selectable_node =
            selectable_text renderer ~id:"selection-default" ~left:0 ~width:2
          in
          let blocker =
            expect_ok (Box.create (Renderer.context renderer) ~id:"selection-blocker" ())
          in
          let blocker_node = Box.as_renderable blocker in
          ignore (expect_ok (Renderable.set_position_type blocker_node Core.Yoga.Position_absolute));
          ignore
            (expect_ok
               (Renderable.set_position blocker_node ~edge:Core.Yoga.Left
                  (Core.Yoga.Point 3.0)));
          ignore
            (expect_ok
               (Renderable.set_position blocker_node ~edge:Core.Yoga.Top
                  (Core.Yoga.Point 0.0)));
          ignore (expect_ok (Renderable.set_width blocker_node (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Renderable.set_height blocker_node (Core.Yoga.Point 1.0)));
          attach renderer blocker_node;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:1 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:1 ~y:0 ~button:0)));
          equal bool true
            (Option.is_some (expect_ok (Renderer.selection renderer)));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_down blocker_node
                  (Some (fun event -> Renderable.mouse_prevent_default event))));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:3 ~y:0 ~button:0)));
          equal bool true
            (Option.is_some (expect_ok (Renderer.selection renderer)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:7 ~y:0 ~button:0)));
          equal bool false
            (Option.is_some (expect_ok (Renderer.selection renderer)));
          ignore (expect_ok (Text_buffer_renderable.selected_text selectable));
          Renderer.destroy renderer);
      test "Ctrl-click moves an active selection without mouse-down or focus" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:6l ~height:1l ()) in
          let text, node =
            selectable_text renderer ~id:"selection-ctrl" ~left:0 ~width:4
          in
          let down_count = ref 0 in
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:1 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:1 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderable.set_on_mouse_down node
                  (Some (fun _ -> incr down_count))));
          ignore (expect_ok (Renderable.set_focusable node true));
          let ctrl = { no_modifiers with Mouse.ctrl = true } in
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse ~modifiers:ctrl Mouse.Down ~x:2 ~y:0 ~button:0)));
          let after_down = expect_ok (Renderer.selection renderer) in
          equal int 0 !down_count;
          equal bool false (Renderable.focused node);
          equal bool true (Selection.is_dragging (Option.get after_down));
          equal (float 0.0001) 2.0
            (Selection.focus (Option.get after_down)).Selection.x;
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse ~modifiers:ctrl Mouse.Up ~x:2 ~y:0 ~button:0)));
          let after_up = expect_ok (Renderer.selection renderer) in
          equal bool false (Selection.is_dragging (Option.get after_up));
          ignore (expect_ok (Text_buffer_renderable.selected_text text));
          Renderer.destroy renderer);
      test "starting a new selection clears every previously touched renderable" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:1l ()) in
          let previous_text, previous_node =
            selectable_text renderer ~id:"selection-previous" ~left:0 ~width:2
          in
          let next_text, next_node =
            selectable_text renderer ~id:"selection-next" ~left:3 ~width:2
          in
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:1 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:1 ~y:0 ~button:0)));
          let previous_selected =
            expect_ok (Text_buffer_renderable.selected_text previous_text)
          in
          equal bool true (String.length previous_selected > 0);
          let previous_selection =
            Option.get (expect_ok (Renderer.selection renderer))
          in
          let previous_touched = Selection.touched_renderables previous_selection in
          equal bool true
            (List.exists
               (fun value -> Int.equal value.Selection.id (Renderable.num previous_node))
               previous_touched);
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:3 ~y:0 ~button:0)));
          equal string ""
            (expect_ok (Text_buffer_renderable.selected_text previous_text));
          let next_selection =
            Option.get (expect_ok (Renderer.selection renderer))
          in
          let next_touched = Selection.touched_renderables next_selection in
          equal bool false
            (List.exists
               (fun value -> Int.equal value.Selection.id (Renderable.num previous_node))
               next_touched);
          equal bool true
            (List.exists
               (fun value -> Int.equal value.Selection.id (Renderable.num next_node))
               next_touched);
          Renderer.destroy renderer);
      test "selection tracks every affected renderable with generic snapshots" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:10l ~height:1l ()) in
          let first_text, first_node =
            selectable_text renderer ~id:"selection-first" ~left:0 ~width:2
          in
          let second_text, second_node =
            selectable_text renderer ~id:"selection-second" ~left:3 ~width:2
          in
          let destroyed_text, destroyed_node =
            selectable_text renderer ~id:"selection-destroyed" ~left:7 ~width:2
          in
          Text_buffer_renderable.destroy destroyed_text;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Down ~x:0 ~y:0 ~button:0)));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:4 ~y:0 ~button:0)));
          let selection = Option.get (expect_ok (Renderer.selection renderer)) in
          let selected = Selection.selected_renderables selection in
          let touched = Selection.touched_renderables selection in
          let assert_snapshot snapshots node expected_x =
            match
              List.find_opt
                (fun value -> Int.equal value.Selection.id (Renderable.num node))
                snapshots
            with
            | None -> fail "selection snapshot missing renderable"
            | Some value ->
                equal (float 0.0001) expected_x value.Selection.x;
                equal bool false value.Selection.destroyed;
                equal string "" value.Selection.text
          in
          equal int 2 (List.length selected);
          equal int 2 (List.length touched);
          assert_snapshot selected first_node 0.0;
          assert_snapshot selected second_node 3.0;
          assert_snapshot touched first_node 0.0;
          assert_snapshot touched second_node 3.0;
          equal bool false
            (List.exists
               (fun value -> Int.equal value.Selection.id (Renderable.num destroyed_node))
               selected);
          equal bool false
            (List.exists
               (fun value -> Int.equal value.Selection.id (Renderable.num destroyed_node))
               touched);
          equal bool true
            (String.length (expect_ok (Text_buffer_renderable.selected_text first_text)) > 0);
          equal bool true
            (String.length (expect_ok (Text_buffer_renderable.selected_text second_text)) > 0);
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:1 ~y:0 ~button:0)));
          let narrowed_selection =
            Option.get (expect_ok (Renderer.selection renderer))
          in
          equal int 1
            (List.length (Selection.selected_renderables narrowed_selection));
          equal int 1
            (List.length (Selection.touched_renderables narrowed_selection));
          equal bool false
            (List.exists
               (fun value -> Int.equal value.Selection.id (Renderable.num second_node))
               (Selection.touched_renderables narrowed_selection));
          equal string ""
            (expect_ok (Text_buffer_renderable.selected_text second_text));
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:1 ~y:0 ~button:0)));
          Renderer.destroy renderer);
      test "pointer callback failures publish handler errors" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
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
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
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
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
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
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
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
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
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
