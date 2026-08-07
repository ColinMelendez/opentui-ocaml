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
    ]
