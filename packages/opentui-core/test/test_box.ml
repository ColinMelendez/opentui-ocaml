open Windtrap

module Core = Opentui_core
module Box = Core.Renderables.Box
module Renderer = Core.Renderer

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual ->
      equal bool true
        (match expected, actual with
        | Core.Error.Unsupported, Core.Error.Unsupported -> true
        | Core.Error.Owner_mismatch, Core.Error.Owner_mismatch -> true
        | Core.Error.Invalid_anchor, Core.Error.Invalid_anchor -> true
        | Core.Error.Not_child, Core.Error.Not_child -> true
        | _ -> false)

let () =
  run "opentui-core-box"
    [
      test "renderer and box capabilities attach physical children"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:10l ~height:6l ()) in
          let context = Renderer.context renderer in
          let parent = expect_ok (Box.create context ~id:"parent" ()) in
          let child = expect_ok (Box.create context ~id:"child" ()) in
          ignore (expect_ok (Box.set_width parent (Core.Yoga.Point 6.0)));
          ignore (expect_ok (Box.set_height parent (Core.Yoga.Point 4.0)));
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
          equal int 1 (Core.Renderable.child_count (Renderer.root renderer));
          equal int 1
            (Core.Renderable.child_count (Box.as_renderable parent));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (float 0.0001) 2.0 (Box.width child);
          equal (float 0.0001) 1.0 (Box.height child);
          Renderer.destroy renderer);
      test "box border and gap setters update Yoga layout"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:12l ~height:8l ()) in
          let context = Renderer.context renderer in
          let parent = expect_ok (Box.create context ~id:"parent" ()) in
          let first = expect_ok (Box.create context ~id:"first" ()) in
          let second = expect_ok (Box.create context ~id:"second" ()) in
          ignore (expect_ok (Box.set_width parent (Core.Yoga.Point 8.0)));
          ignore (expect_ok (Box.set_height parent (Core.Yoga.Point 6.0)));
          ignore (expect_ok (Box.set_border parent Box.all_borders));
          ignore
            (expect_ok
               (Box.set_gap parent ~gutter:Core.Yoga.Gutter_row
                  (Core.Yoga.Point 1.0)));
          ignore (expect_ok (Box.set_height first (Core.Yoga.Point 1.0)));
          ignore (expect_ok (Box.set_height second (Core.Yoga.Point 1.0)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Box.as_renderable parent)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Box.children parent)
                  (Box.as_renderable first)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Box.children parent)
                  (Box.as_renderable second)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let border = Box.border parent in
          (match border with
          | Core.Lib.Border.All_borders -> ()
          | _ -> fail "expected all box borders");
          let border_sides = Box.border_sides parent in
          equal bool true (Core.Lib.Border.left border_sides);
          equal bool true (Core.Lib.Border.top border_sides);
          equal bool true (Core.Lib.Border.right border_sides);
          equal bool true (Core.Lib.Border.bottom border_sides);
          let first_layout =
            expect_ok (Core.Renderable.layout (Box.as_renderable first))
          in
          let second_layout =
            expect_ok (Core.Renderable.layout (Box.as_renderable second))
          in
          equal (float 0.0001) 1.0 first_layout.left;
          equal (float 0.0001) 1.0 first_layout.top;
          equal (float 0.0001) 3.0 second_layout.top;
          Renderer.destroy renderer);
      test "public layout capabilities preserve indexed and ownership semantics"
        (fun () ->
          let left = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:10l ~height:6l ()) in
          let right = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:10l ~height:6l ()) in
          let context = Renderer.context left in
          let right_context = Renderer.context right in
          let first = expect_ok (Box.create context ~id:"first" ()) in
          let second = expect_ok (Box.create context ~id:"second" ()) in
          let third = expect_ok (Box.create context ~id:"third" ()) in
          let foreign = expect_ok (Box.create right_context ~id:"foreign" ()) in
          let children = Renderer.children left in
          ignore (expect_ok (Core.Layout_children.add children (Box.as_renderable first)));
          ignore (expect_ok (Core.Layout_children.add children (Box.as_renderable second)));
          ignore (expect_ok (Core.Layout_children.add children (Box.as_renderable third)));
          equal int 1
            (expect_ok
               (Core.Layout_children.add ~index:1 children
                  (Box.as_renderable third)));
          (match Core.Renderable.children (Renderer.root left) with
          | current :: rest ->
              equal string "first" (Core.Renderable.id current);
              (match rest with
              | current :: _ -> equal string "third" (Core.Renderable.id current)
              | [] -> fail "indexed add removed a child")
          | [] -> fail "indexed add removed all children");
          expect_error Core.Error.Invalid_anchor
            (Core.Layout_children.add ~index:0 children
               (Box.as_renderable first));
          ignore
            (expect_ok
               (Core.Layout_children.insert_before children
                  (Box.as_renderable second) ~anchor:(Box.as_renderable first)));
          expect_error Core.Error.Invalid_anchor
            (Core.Layout_children.insert_before children
               (Box.as_renderable third) ~anchor:(Box.as_renderable foreign));
          expect_error Core.Error.Owner_mismatch
            (Core.Layout_children.add (Renderer.children right)
               (Box.as_renderable first));
          ignore
            (expect_ok
               (Core.Layout_children.remove children (Box.as_renderable third)));
          equal bool true
            (not (Core.Renderable.is_destroyed (Box.as_renderable third)));
          equal bool true
            (Option.is_none (Core.Renderable.parent (Box.as_renderable third)));
          Renderer.destroy left;
          Renderer.destroy right);
      test "box draws its border at the laid out position" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:6l ~height:4l ()) in
          let box =
            expect_ok
              (Box.create (Renderer.context renderer) ~border:Box.all_borders
                 ())
          in
          ignore (expect_ok (Box.set_width box (Core.Yoga.Point 6.0)));
          ignore (expect_ok (Box.set_height box (Core.Yoga.Point 4.0)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Box.as_renderable box)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let output = Bytes.create 128 in
          let written =
            expect_ok
              (Core.Buffer.write_resolved_chars
                 (expect_ok (Renderer.current_buffer renderer)) ~output
                 ~add_line_breaks:false)
          in
          let rendered = Bytes.sub_string output 0 (Int32.to_int written) in
          equal string "┌────┐│    ││    │└────┘" rendered;
          Renderer.destroy renderer);
      test "box forwards title and border style options" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:6l ~height:2l ()) in
          let box =
            expect_ok
              (Box.create (Renderer.context renderer)
                 ~border_style:Core.Lib.Border.Double ~title:"T" ())
          in
          (match Box.border box with
          | Core.Lib.Border.All_borders -> ()
          | _ -> fail "border style should initialize the border");
          ignore (expect_ok (Box.set_width box (Core.Yoga.Point 6.0)));
          ignore (expect_ok (Box.set_height box (Core.Yoga.Point 2.0)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Box.as_renderable box)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let output = Bytes.create 128 in
          let written =
            expect_ok
              (Core.Buffer.write_resolved_chars
                 (expect_ok (Renderer.current_buffer renderer)) ~output
                 ~add_line_breaks:false)
          in
          let rendered = Bytes.sub_string output 0 (Int32.to_int written) in
          equal string "╔═T══╗╚════╝" rendered;
          Renderer.destroy renderer);
    ]
