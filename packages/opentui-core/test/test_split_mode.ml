open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Text = Core.Renderables.Text

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let contains_substring value substring =
  let value_length = String.length value in
  let substring_length = String.length substring in
  if Int.equal substring_length 0 then true
  else if Int.compare substring_length value_length > 0 then false
  else
    let found = ref false in
    for index = 0 to value_length - substring_length do
      if
        not !found
        && String.equal
             (String.sub value index substring_length)
             substring
      then found := true
    done;
    !found

let make_snapshot ?(width = 5) ?(row_columns = 5) ?(start_on_new_line = true)
    ?(trailing_newline = true) context text =
  let renderable =
    expect_ok
      (Text.create context.Renderer.render_context
         ~content:(Core.Lib.Styled_text.of_string text) ())
  in
  let root = Text.as_renderable renderable in
  ignore
    (expect_ok
       (Core.Renderable.set_width root (Core.Yoga.Point (float_of_int width))));
  ignore (expect_ok (Core.Renderable.set_height root (Core.Yoga.Point 1.0)));
  {
    Renderer.root;
    width;
    height = 1;
    row_columns;
    start_on_new_line;
    trailing_newline;
  }

let () =
  run "opentui-core-split-mode"
    [
      test "split capture commits snapshots and exposes surface dimensions" (fun () ->
          let frames = ref [] in
          let sink =
            Renderer.Output.sink ~write_frame:(fun chunks ->
                frames := !frames @ [ String.concat "" (List.map Bytes.to_string chunks) ];
                Ok ())
          in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Output.Sink sink)
                 ~remote_mode:Renderer.Output.Remote ~width:20l ~height:8l ())
          in
          ignore
            (expect_ok
               (Renderer.set_render_geometry renderer
                  Core.Lib.Render_geometry.Split_footer ~footer_height:3));
          ignore
            (expect_ok
               (Renderer.set_external_output_mode renderer
                  Renderer.Capture_stdout));
          equal int32 20l (expect_ok (Renderer.width renderer));
          equal int32 3l (expect_ok (Renderer.height renderer));
          equal int32 20l (expect_ok (Renderer.terminal_width renderer));
          equal int32 8l (expect_ok (Renderer.terminal_height renderer));
          equal bool true
            (match expect_ok (Renderer.external_output_mode renderer) with
            | Renderer.Capture_stdout -> true
            | Renderer.Passthrough -> false);
          let observed_tails = ref [] in
          ignore
            (expect_ok
               (Renderer.write_to_scrollback renderer (fun context ->
                    equal int 3
                      (Int32.to_int
                         (expect_ok
                            (Core.Render_context.height context.render_context)));
                    equal int 8
                      (Int32.to_int
                         (expect_ok
                            (Core.Render_context.terminal_height
                               context.render_context)));
                    observed_tails := !observed_tails @ [ context.tail_column ];
                    make_snapshot ~width:2 ~row_columns:2 ~trailing_newline:false
                      context "hi")));
          ignore
            (expect_ok
               (Renderer.write_to_scrollback renderer (fun context ->
                    observed_tails := !observed_tails @ [ context.tail_column ];
                    make_snapshot ~width:2 ~row_columns:2 ~trailing_newline:false
                      context "ok")));
          (match !observed_tails with
          | [ 0; 2 ] -> ()
          | _ -> fail "queued scrollback did not project its tail column");
          (match expect_ok (Renderer.render renderer ~force:true) with
          | Renderer.Rendered -> ()
          | Renderer.Skipped -> fail "split snapshot render was backpressured"
          | Renderer.Failed -> fail "split snapshot render failed");
          equal int 1 (List.length !frames);
          equal bool true (String.contains (List.hd !frames) 'h');
          ignore
            (expect_ok
               (Renderer.set_external_output_mode renderer Renderer.Passthrough));
          ignore
            (expect_ok
               (Renderer.set_render_geometry renderer Core.Lib.Render_geometry.Main_screen
                  ~footer_height:0));
          equal int32 8l (expect_ok (Renderer.height renderer));
          (match
             Renderer.write_to_scrollback renderer (fun context ->
               make_snapshot context "invalid")
           with
          | Error Core.Error.Invalid_argument -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok () -> fail "passthrough accepted a scrollback snapshot");
          ignore (Renderer.close renderer));
      test "split resize keeps terminal and surface geometry distinct" (fun () ->
          let renderer =
            expect_ok
              (Renderer.create ~output:Renderer.Output.Memory ~width:12l ~height:6l ())
          in
          ignore
            (expect_ok
               (Renderer.set_render_geometry renderer
                  Core.Lib.Render_geometry.Split_footer ~footer_height:2));
          ignore
            (expect_ok
               (Renderer.set_external_output_mode renderer
                  Renderer.Capture_stdout));
          ignore (expect_ok (Renderer.resize renderer ~width:18l ~height:9l));
          equal int32 18l (expect_ok (Renderer.width renderer));
          equal int32 2l (expect_ok (Renderer.height renderer));
          equal int32 18l (expect_ok (Renderer.terminal_width renderer));
          equal int32 9l (expect_ok (Renderer.terminal_height renderer));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore (Renderer.close renderer));
      test "split width resize clears the visible stale surface before repaint" (fun () ->
          let frames = ref [] in
          let sink =
            Renderer.Output.sink ~write_frame:(fun chunks ->
                frames :=
                  !frames
                  @ [ String.concat "" (List.map Bytes.to_string chunks) ];
                Ok ())
          in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Output.Sink sink)
                 ~remote_mode:Renderer.Output.Remote ~width:20l ~height:10l ())
          in
          ignore
            (expect_ok
               (Renderer.set_render_geometry renderer
                  Core.Lib.Render_geometry.Split_footer ~footer_height:4));
          ignore
            (expect_ok
               (Renderer.set_external_output_mode renderer
                  Renderer.Capture_stdout));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          frames := [];
          ignore (expect_ok (Renderer.resize renderer ~width:12l ~height:10l));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let output = String.concat "" !frames in
          equal bool true (contains_substring output "\027[2;1H\027[J");
          ignore (Renderer.close renderer));
      test "split width resize uses the pending footer source height for cleanup" (fun () ->
          let frames = ref [] in
          let sink =
            Renderer.Output.sink ~write_frame:(fun chunks ->
                frames :=
                  !frames
                  @ [ String.concat "" (List.map Bytes.to_string chunks) ];
                Ok ())
          in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Output.Sink sink)
                 ~remote_mode:Renderer.Output.Remote ~width:20l ~height:20l ())
          in
          ignore
            (expect_ok
               (Renderer.set_render_geometry renderer
                  Core.Lib.Render_geometry.Split_footer ~footer_height:4));
          ignore
            (expect_ok
               (Renderer.set_external_output_mode renderer
                  Renderer.Capture_stdout));
          for index = 0 to 19 do
            ignore
              (expect_ok
                 (Renderer.write_to_scrollback renderer (fun context ->
                      make_snapshot ~width:2 ~row_columns:2 context
                        (Printf.sprintf "x%d" index))))
          done;
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Renderer.set_render_geometry renderer
                  Core.Lib.Render_geometry.Split_footer ~footer_height:3));
          frames := [];
          ignore (expect_ok (Renderer.resize renderer ~width:10l ~height:20l));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let output = String.concat "" !frames in
          equal bool true (contains_substring output "\027[12;1H\027[J");
          ignore (Renderer.close renderer));
    ]
