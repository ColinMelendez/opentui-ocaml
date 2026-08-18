open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Box = Core.Renderables.Box
module Layout_children = Core.Layout_children
module Yoga = Core.Yoga
module Mouse = Core.Lib.Mouse_decoder

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let set_geometry renderable ~x ~y ~width ~height =
  ignore
    (expect_ok
       (Renderable.set_position_type renderable Yoga.Position_absolute));
  ignore
    (expect_ok
       (Renderable.set_position renderable ~edge:Yoga.Left
          (Yoga.Point (float_of_int x))));
  ignore
    (expect_ok
       (Renderable.set_position renderable ~edge:Yoga.Top
          (Yoga.Point (float_of_int y))));
  ignore
    (expect_ok
       (Renderable.set_width renderable (Yoga.Point (float_of_int width))));
  ignore
    (expect_ok
       (Renderable.set_height renderable (Yoga.Point (float_of_int height))))

let create_box renderer ?id ~x ~y ~width ~height () =
  let box = expect_ok (Box.create (Renderer.context renderer) ?id ()) in
  let renderable = Box.as_renderable box in
  set_geometry renderable ~x ~y ~width ~height;
  box, renderable

let create_renderable renderer ?id ?behavior ~x ~y ~width ~height () =
  let renderable =
    expect_ok
      (Renderable.Private.create (Renderer.context renderer) ?id ?behavior ())
  in
  set_geometry renderable ~x ~y ~width ~height;
  renderable

let attach_root renderer renderable =
  ignore
    (expect_ok
       (Layout_children.add (Renderer.children renderer) renderable))

let attach_child box renderable =
  ignore (expect_ok (Layout_children.add (Box.children box) renderable))

let render renderer =
  match Renderer.render renderer ~force:true with
  | Ok Renderer.Rendered -> ()
  | Ok Renderer.Skipped -> fail "forced frame was skipped"
  | Ok Renderer.Failed -> fail "forced frame failed"
  | Error error -> fail (Core.Error.message error)

let assert_hit renderer ~x ~y expected =
  match expect_ok (Renderer.hit_test renderer ~x ~y), expected with
  | None, None -> ()
  | Some actual, Some expected -> equal bool true (actual == expected)
  | Some _, None -> fail "hit-grid returned an unexpected renderable"
  | None, Some _ -> fail "hit-grid missed the expected renderable"

let write_failure_marker buffer =
  ignore
    (expect_ok
       (Core.Buffer.push_scissor_rect buffer ~x:1l ~y:0l ~width:1l ~height:1l));
  ignore (expect_ok (Core.Buffer.push_opacity buffer 0.5));
  ignore
    (expect_ok
       (Core.Buffer.set_cell buffer ~x:1l ~y:0l ~character:88l
          ~foreground:Core.Color.white ~background:Core.Color.black
          ~attributes:0l))

let assert_next_buffer_blank renderer =
  let buffer = expect_ok (Renderer.next_buffer renderer) in
  let characters, _foreground, _background, _attributes =
    expect_ok (Core.Buffer.snapshot buffer)
  in
  equal int32 32l characters.(1);
  equal (float 0.0001) 1.0 (expect_ok (Core.Buffer.current_opacity buffer));
  ignore
    (expect_ok
       (Core.Buffer.set_cell buffer ~x:0l ~y:0l ~character:65l
          ~foreground:Core.Color.white ~background:Core.Color.black
          ~attributes:0l));
  let characters, _foreground, _background, _attributes =
    expect_ok (Core.Buffer.snapshot buffer)
  in
  equal int32 65l characters.(0);
  ignore (expect_ok (Core.Buffer.clear buffer ~background:Core.Color.black));
  ignore (expect_ok (Core.Buffer.clear_scissor_rects buffer));
  ignore (expect_ok (Core.Buffer.clear_opacity buffer))

let no_modifiers = { Mouse.shift = false; alt = false; ctrl = false }

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
          modifiers = no_modifiers;
          scroll = None;
        };
    }

let () =
  run "opentui-core-native-hit-grid"
    [
      test "current hit-grid remains visible until the next frame commits" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          let _, target = create_box renderer ~id:"target" ~x:0 ~y:0 ~width:1
              ~height:1 () in
          attach_root renderer target;
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some target);
          ignore (expect_ok (Renderable.set_visible target false));
          assert_hit renderer ~x:0 ~y:0 (Some target);
          render renderer;
          assert_hit renderer ~x:0 ~y:0 None;
          ignore (expect_ok (Renderable.set_visible target true));
          assert_hit renderer ~x:0 ~y:0 None;
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some target);
          Renderer.destroy renderer);
      test "a Core render failure preserves current and clears next" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          let should_fail = ref false in
          let stable =
            create_renderable renderer ~id:"stable" ~x:0 ~y:0 ~width:1 ~height:1
              ()
          in
          let failing_behavior =
            Renderable.Private.make_behavior
              ~render_self:(fun _ buffer _ ->
                if !should_fail then begin
                  write_failure_marker buffer;
                  Error Core.Error.Unsupported
                end else Ok ())
              ()
          in
          let failing =
            create_renderable renderer ~id:"failing" ~behavior:failing_behavior
              ~x:1 ~y:0 ~width:1 ~height:1 ()
          in
          attach_root renderer stable;
          attach_root renderer failing;
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some stable);
          assert_hit renderer ~x:1 ~y:0 (Some failing);
          should_fail := true;
          ignore (expect_ok (Renderable.request_render failing));
          (match Renderer.render renderer ~force:true with
          | Error Core.Error.Unsupported -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok _ -> fail "a failing renderable produced a successful frame");
          assert_next_buffer_blank renderer;
          assert_hit renderer ~x:0 ~y:0 (Some stable);
          assert_hit renderer ~x:1 ~y:0 (Some failing);
          equal bool true (expect_ok (Renderer.has_pending_render renderer));
          should_fail := false;
          ignore (expect_ok (Renderable.set_visible failing false));
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some stable);
          assert_hit renderer ~x:1 ~y:0 None;
          Renderer.destroy renderer);
      test "an exception during Core rendering preserves current and clears next" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          let should_raise = ref false in
          let stable =
            create_renderable renderer ~id:"stable" ~x:0 ~y:0 ~width:1 ~height:1
              ()
          in
          let raising_behavior =
            Renderable.Private.make_behavior
              ~render_self:(fun _ buffer _ ->
                if !should_raise then begin
                  write_failure_marker buffer;
                  raise (Failure "native hit-grid test")
                end
                else Ok ())
              ()
          in
          let raising =
            create_renderable renderer ~id:"raising" ~behavior:raising_behavior
              ~x:1 ~y:0 ~width:1 ~height:1 ()
          in
          attach_root renderer stable;
          attach_root renderer raising;
          render renderer;
          should_raise := true;
          ignore (expect_ok (Renderable.request_render raising));
          let raised_message =
            try
              ignore (Renderer.render renderer ~force:true);
              None
            with
            | Failure message -> Some message
          in
          (match raised_message with
          | Some message -> equal string "native hit-grid test" message
          | None -> fail "rendering exception did not escape the frame");
          assert_next_buffer_blank renderer;
          assert_hit renderer ~x:0 ~y:0 (Some stable);
          assert_hit renderer ~x:1 ~y:0 (Some raising);
          should_raise := false;
          ignore (expect_ok (Renderable.set_visible raising false));
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some stable);
          assert_hit renderer ~x:1 ~y:0 None;
          Renderer.destroy renderer);
      test "a captured ID is omitted while captured and returns after release" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          let _, source = create_box renderer ~id:"source" ~x:0 ~y:0 ~width:1
              ~height:1 () in
          let _, target = create_box renderer ~id:"target" ~x:1 ~y:0 ~width:1
              ~height:1 () in
          attach_root renderer source;
          attach_root renderer target;
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some source);
          assert_hit renderer ~x:1 ~y:0 (Some target);
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Drag ~x:0 ~y:0)));
          render renderer;
          assert_hit renderer ~x:0 ~y:0 None;
          assert_hit renderer ~x:1 ~y:0 (Some target);
          ignore
            (expect_ok
               (Renderer.handle_input renderer
                  (mouse Mouse.Up ~x:0 ~y:0)));
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some source);
          Renderer.destroy renderer);
      test "hit-grid scissors clip descendants to an overflow-hidden box" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:4l ~height:1l ()) in
          let parent_box, parent =
            create_box renderer ~id:"clip-parent" ~x:0 ~y:0 ~width:2 ~height:1 ()
          in
          ignore (expect_ok (Renderable.set_overflow parent Yoga.Overflow_hidden));
          let _, child =
            create_box renderer ~id:"clipped-child" ~x:1 ~y:0 ~width:3 ~height:1 ()
          in
          attach_root renderer parent;
          attach_child parent_box child;
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some parent);
          assert_hit renderer ~x:1 ~y:0 (Some child);
          assert_hit renderer ~x:2 ~y:0 None;
          Renderer.destroy renderer);
      test "resize clears stale committed hit-grid cells before the next frame" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          let _, target = create_box renderer ~id:"resized" ~x:0 ~y:0 ~width:1
              ~height:1 () in
          attach_root renderer target;
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some target);
          ignore (expect_ok (Renderer.resize renderer ~width:1l ~height:1l));
          assert_hit renderer ~x:0 ~y:0 None;
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some target);
          Renderer.destroy renderer);
      test "detached and destroyed IDs are rejected from the committed grid" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          let _, detached =
            create_box renderer ~id:"detached" ~x:0 ~y:0 ~width:1 ~height:1 ()
          in
          attach_root renderer detached;
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some detached);
          ignore
            (expect_ok
               (Layout_children.remove (Renderer.children renderer) detached));
          assert_hit renderer ~x:0 ~y:0 None;
          let _, destroyed =
            create_box renderer ~id:"destroyed" ~x:1 ~y:0 ~width:1 ~height:1 ()
          in
          attach_root renderer destroyed;
          render renderer;
          assert_hit renderer ~x:1 ~y:0 (Some destroyed);
          Renderable.destroy destroyed;
          assert_hit renderer ~x:1 ~y:0 None;
          Renderer.destroy renderer);
      test "non-forced frames preserve current when the native backend skips" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          let _, stable = create_box renderer ~id:"stable" ~x:0 ~y:0 ~width:1
              ~height:1 () in
          let _, candidate =
            create_box renderer ~id:"candidate" ~x:1 ~y:0 ~width:1 ~height:1 ()
          in
          attach_root renderer stable;
          attach_root renderer candidate;
          ignore (expect_ok (Renderable.set_visible candidate false));
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some stable);
          assert_hit renderer ~x:1 ~y:0 None;
          ignore (expect_ok (Renderable.set_visible candidate true));
          let status =
            match Renderer.render renderer ~force:false with
            | Ok status -> status
            | Error error -> fail (Core.Error.message error)
          in
          (match status with
          | Renderer.Skipped ->
              assert_hit renderer ~x:0 ~y:0 (Some stable);
              assert_hit renderer ~x:1 ~y:0 None
          | Renderer.Rendered ->
              assert_hit renderer ~x:0 ~y:0 (Some stable);
              assert_hit renderer ~x:1 ~y:0 (Some candidate)
          | Renderer.Failed -> fail "non-forced native frame failed");
          ignore (expect_ok (Renderable.set_visible candidate false));
          render renderer;
          assert_hit renderer ~x:0 ~y:0 (Some stable);
          assert_hit renderer ~x:1 ~y:0 None;
          Renderer.destroy renderer);
    ]
