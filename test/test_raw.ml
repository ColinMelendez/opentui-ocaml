open Windtrap

external emit_event_for_test : unit -> bool =
  "opentui_raw_test_event_sink_emit"

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_raw.Error.message error)

let same_error left right =
  match left, right with
  | Opentui_raw.Error.Invalid_argument, Opentui_raw.Error.Invalid_argument -> true
  | Opentui_raw.Error.Closed, Opentui_raw.Error.Closed -> true
  | Opentui_raw.Error.Stale_handle, Opentui_raw.Error.Stale_handle -> true
  | Opentui_raw.Error.Native_failure, Opentui_raw.Error.Native_failure -> true
  | Opentui_raw.Error.Output_too_small, Opentui_raw.Error.Output_too_small -> true
  | Opentui_raw.Error.Queue_overflow, Opentui_raw.Error.Queue_overflow -> true
  | _ -> false

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual -> equal bool true (same_error actual expected)

let expect_layout ~left ~top ~right ~bottom ~width ~height actual =
  equal (float 0.0001) left actual.Opentui_raw.Yoga.left;
  equal (float 0.0001) top actual.Opentui_raw.Yoga.top;
  equal (float 0.0001) right actual.Opentui_raw.Yoga.right;
  equal (float 0.0001) bottom actual.Opentui_raw.Yoga.bottom;
  equal (float 0.0001) width actual.Opentui_raw.Yoga.width;
  equal (float 0.0001) height actual.Opentui_raw.Yoga.height

let () =
  run "opentui-raw"
    [
      test "renderer and buffers preserve ownership through native calls" (fun () ->
          let renderer = expect_ok (Opentui_raw.Renderer.create ~width:2l ~height:1l) in
          let current = expect_ok (Opentui_raw.Renderer.current_buffer renderer) in
          let next = expect_ok (Opentui_raw.Renderer.next_buffer renderer) in
          let white = Opentui_raw.Color.white in
          let black = Opentui_raw.Color.black in
          ignore (expect_ok (Opentui_raw.Buffer.clear current ~background:black));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.set_cell current ~x:0l ~y:0l ~character:65l
                  ~foreground:white ~background:black ~attributes:0l));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.draw_text next ~text:"B" ~x:1l ~y:0l
                  ~foreground:white ~background:black ~attributes:0l));
          let output = Bytes.create 2 in
          let written =
            expect_ok
              (Opentui_raw.Buffer.write_resolved_chars current ~output
                 ~add_line_breaks:false)
          in
          equal int32 2l written;
          equal string "A " (Bytes.to_string output);
          Opentui_raw.Renderer.close renderer;
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Buffer.width current);
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Buffer.height next));
      test "invalid dimensions and colors are structured errors" (fun () ->
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Renderer.create ~width:0l ~height:1l);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Color.rgba ~red:256 ~green:0 ~blue:0 ~alpha:255));
      test "small output is reported without raising" (fun () ->
          let renderer = expect_ok (Opentui_raw.Renderer.create ~width:1l ~height:1l) in
          let buffer = expect_ok (Opentui_raw.Renderer.current_buffer renderer) in
          let output = Bytes.create 0 in
          expect_error Opentui_raw.Error.Output_too_small
            (Opentui_raw.Buffer.write_resolved_chars buffer ~output
               ~add_line_breaks:false);
          Opentui_raw.Renderer.close renderer);
      test "event delivery is polled from an owned copy" (fun () ->
          let sink = expect_ok (Opentui_raw.Event_sink.create ()) in
          equal bool true (emit_event_for_test ());
          let first =
            match Opentui_raw.Event_sink.poll sink with
            | Ok (Some event) -> event
            | Ok None -> fail "event queue was empty"
            | Error error -> fail (Opentui_raw.Error.message error)
          in
          let second =
            match Opentui_raw.Event_sink.poll sink with
            | Ok (Some event) -> event
            | Ok None -> fail "event queue ended early"
            | Error error -> fail (Opentui_raw.Error.message error)
          in
          equal string "eb_cursor-changed"
            (Bytes.to_string (Opentui_raw.Event.name first));
          equal string "eb_content-changed"
            (Bytes.to_string (Opentui_raw.Event.name second));
          equal int 2 (Bytes.length (Opentui_raw.Event.data first));
          equal int 2 (Bytes.length (Opentui_raw.Event.data second));
          Opentui_raw.Event_sink.close sink;
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Event_sink.poll sink));
      test "event overflow preserves accepted packets before reporting loss" (fun () ->
          let sink = expect_ok (Opentui_raw.Event_sink.create ()) in
          for _ = 1 to 33 do
            equal bool true (emit_event_for_test ())
          done;
          for _ = 1 to 64 do
            match Opentui_raw.Event_sink.poll sink with
            | Ok (Some _) -> ()
            | Ok None -> fail "event queue dropped an accepted packet"
            | Error error -> fail (Opentui_raw.Error.message error)
          done;
          expect_error Opentui_raw.Error.Queue_overflow
            (Opentui_raw.Event_sink.poll sink);
          (match Opentui_raw.Event_sink.poll sink with
          | Ok None -> ()
          | Ok (Some _) -> fail "overflow remained sticky after reporting"
          | Error error -> fail (Opentui_raw.Error.message error));
          Opentui_raw.Event_sink.close sink);
      test "Yoga owns a tree and exposes computed layout" (fun () ->
          let tree = expect_ok (Opentui_raw.Yoga.create ()) in
          let root = expect_ok (Opentui_raw.Yoga.root tree) in
          let child =
            expect_ok (Opentui_raw.Yoga.add_child tree ~parent:root)
          in
          ignore (expect_ok (Opentui_raw.Yoga.Node.set_width child 10.0));
          ignore (expect_ok (Opentui_raw.Yoga.Node.set_height child 5.0));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.calculate tree ~width:100.0 ~height:40.0
                  ~direction:Opentui_raw.Yoga.Ltr));
          let root_layout = expect_ok (Opentui_raw.Yoga.Node.layout root) in
          expect_layout ~left:0.0 ~top:0.0 ~right:0.0 ~bottom:0.0 ~width:100.0
            ~height:40.0 root_layout;
          let child_layout = expect_ok (Opentui_raw.Yoga.Node.layout child) in
          expect_layout ~left:0.0 ~top:0.0 ~right:0.0 ~bottom:0.0 ~width:10.0
            ~height:5.0 child_layout;
          Opentui_raw.Yoga.close tree;
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Yoga.Node.layout child);
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Yoga.root tree));
      test "Yoga rejects invalid dimensions and cross-tree parents" (fun () ->
          let first = expect_ok (Opentui_raw.Yoga.create ()) in
          let second = expect_ok (Opentui_raw.Yoga.create ()) in
          let first_root = expect_ok (Opentui_raw.Yoga.root first) in
          let second_root = expect_ok (Opentui_raw.Yoga.root second) in
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.add_child first ~parent:second_root);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.set_width first_root Float.nan);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.set_height first_root Float.infinity);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.calculate first ~width:(-1.0) ~height:1.0
               ~direction:Opentui_raw.Yoga.Inherit);
          Opentui_raw.Yoga.close first;
          Opentui_raw.Yoga.close second);
      test "capability responses become typed copied snapshots" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:2l ~height:1l)
          in
          ignore
            (expect_ok
               (Opentui_raw.Capabilities.process_response renderer
                  ~response:"\x1bP>|kitty(0.42.2)\x1b\\"));
          ignore
            (expect_ok
               (Opentui_raw.Capabilities.process_response renderer
                  ~response:"\x1b[?2027;2$y"));
          let capabilities =
            expect_ok (Opentui_raw.Capabilities.snapshot renderer)
          in
          equal string "kitty" capabilities.terminal.name;
          equal string "0.42.2" capabilities.terminal.version;
          equal bool true capabilities.terminal.from_xtversion;
          (match capabilities.unicode with
          | Opentui_raw.Capabilities.Unicode -> ()
          | Opentui_raw.Capabilities.Wcwidth -> fail "expected Unicode mode");
          (match capabilities.multiplexer with
          | Opentui_raw.Capabilities.No_multiplexer -> ()
          | _ -> fail "unexpected multiplexer");
          (match capabilities.image_protocol with
          | Opentui_raw.Capabilities.Auto -> ()
          | _ -> fail "unexpected image protocol");
          Opentui_raw.Renderer.close renderer;
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Capabilities.snapshot renderer);
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Capabilities.process_response renderer ~response:""));
    ]
