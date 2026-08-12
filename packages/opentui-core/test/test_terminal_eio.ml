open Windtrap

module Flow = Opentui_core.Platform.Eio_runtime.Input_flow
module Coordinator = Opentui_core.Lib.Input_coordinator
module Input = Opentui_core.Lib.Stdin_parser
module Events = Opentui_core.Lib.Event_queue

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Flow.message error)

let emit_to queue event =
  match Events.push queue (Events.Input event) with
  | Ok () -> Coordinator.Accepted
  | Error Events.Full -> Coordinator.Full
  | Error Events.Invalid_capacity ->
      fail "a queue created successfully reported Invalid_capacity"

let expect_deadline expected actual =
  match expected, actual with
  | None, None -> ()
  | Some expected, Some actual -> equal int64 expected actual
  | None, Some _ -> fail "expected no timeout deadline"
  | Some _, None -> fail "expected a timeout deadline"

let expect_accepted = function
  | Coordinator.Accepted -> ()
  | Coordinator.Full -> fail "event sink unexpectedly reported Full"

let () =
  run "opentui-core-platform-eio"
    [
      test "rejects a zero-sized reusable flow buffer" (fun () ->
          match Flow.create ~buffer_size:0 () with
          | Error Flow.Invalid_buffer_size -> ()
          | Error error -> fail (Flow.message error)
          | Ok _ -> fail "expected invalid buffer size");
      test "reads a reusable flow buffer into typed events" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:8 ~timeout_ms:20 ()) in
          let queue =
            match Events.create ~capacity:8 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let source = Eio.Flow.string_source "\x1b[A" in
          let clock = Eio.Stdenv.mono_clock env in
          (match
             Flow.read_once input ~clock ~source ~emit:(emit_to queue)
           with
          | Error error -> fail (Flow.message error)
          | Ok Flow.End_of_input -> fail "source ended before the key"
          | Ok (Flow.Backpressured _) -> fail "the test queue was unexpectedly full"
          | Ok (Flow.Bytes_read count) ->
              equal int 3 count;
              expect_deadline None (Flow.deadline input));
          (match Events.read queue with
          | Some (Events.Input (Input.Key { key = Opentui_core.Lib.Key_decoder.Named Up; _ })) ->
              ()
          | Some _ -> fail "flow adapter emitted the wrong event"
          | None -> fail "flow adapter emitted no event");
          (match
             Flow.read_once input ~clock ~source ~emit:(emit_to queue)
           with
          | Ok Flow.End_of_input -> ()
          | Ok (Flow.Backpressured _) -> fail "the test queue was unexpectedly full"
          | Ok (Flow.Bytes_read _) -> fail "expected EOF after one source"
          | Error error -> fail (Flow.message error)));
      test "fires the coordinator timeout through the Eio clock" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:8 ~timeout_ms:1 ()) in
          let queue =
            match Events.create ~capacity:1 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let source = Eio.Flow.string_source "\x1b" in
          let clock = Eio.Stdenv.mono_clock env in
          (match
             Flow.read_once input ~clock ~source ~emit:(emit_to queue)
           with
          | Error error -> fail (Flow.message error)
          | Ok Flow.End_of_input -> fail "source ended before the escape"
          | Ok (Flow.Backpressured _) -> fail "the test queue was unexpectedly full"
          | Ok (Flow.Bytes_read 1) ->
              equal int 0 (Events.length queue)
          | Ok (Flow.Bytes_read _) -> fail "unexpected byte count");
          Eio.Time.Mono.sleep clock 0.005;
          expect_accepted
            (expect_ok
               (Flow.fire_timeout input ~clock ~emit:(emit_to queue)));
          match Events.read queue with
          | Some (Events.Input (Input.Key { key = Opentui_core.Lib.Key_decoder.Named Escape; _ })) ->
              ()
          | Some _ -> fail "timeout emitted the wrong event"
          | None -> fail "timeout emitted no event");
      test "starts a fresh-source timeout after blocking read admission" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let source, sink = Eio_unix.pipe sw in
          let input = expect_ok (Flow.create ~timeout_ms:10 ()) in
          let clock = Eio.Stdenv.mono_clock env in
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Time.Mono.sleep clock 0.020;
              Eio.Flow.copy_string "\x1b" sink;
              Eio.Flow.close sink);
          let events = Queue.create () in
          let emit event =
            Queue.add event events;
            Coordinator.Accepted
          in
          (match Flow.read_once input ~clock ~source ~emit with
          | Ok (Flow.Bytes_read 1) -> ()
          | Ok Flow.End_of_input -> fail "source ended before the delayed ESC"
          | Ok (Flow.Backpressured count) ->
              failf "delayed ESC was backpressured after %d bytes" count
          | Ok (Flow.Bytes_read count) ->
              failf "expected one delayed byte, got %d" count
          | Error error -> fail (Flow.message error));
          expect_accepted (expect_ok (Flow.fire_timeout input ~clock ~emit));
          equal int 0 (Queue.length events));
      test "stops reading while full and preserves the blocked input" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:8 ()) in
          let queue =
            match Events.create ~capacity:1 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let source = Eio.Flow.string_source "ab" in
          let clock = Eio.Stdenv.mono_clock env in
          (match
             Flow.read_once input ~clock ~source ~emit:(emit_to queue)
           with
          | Ok (Flow.Backpressured 2) -> ()
          | Ok Flow.End_of_input -> fail "source ended before both keys"
          | Ok (Flow.Backpressured count) ->
              failf "expected two backpressured bytes, got %d" count
          | Ok (Flow.Bytes_read count) ->
              fail (Printf.sprintf "expected two bytes, got %d" count)
          | Error error -> fail (Flow.message error));
          (match
             Flow.read_once input ~clock ~source ~emit:(emit_to queue)
           with
          | Ok (Flow.Backpressured 0) -> ()
          | Ok (Flow.Backpressured count) ->
              failf "blocked retry read %d new bytes" count
          | Ok Flow.End_of_input -> fail "blocked input was read past"
          | Ok (Flow.Bytes_read _) -> fail "blocked input caused another read"
          | Error error -> fail (Flow.message error));
          (match Events.read queue with
          | Some
              (Events.Input
                (Input.Key
                  {
                    key = Opentui_core.Lib.Key_decoder.Character bytes;
                    modifiers;
                  })) ->
              equal string "a" (Bytes.to_string bytes);
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.shift;
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.meta;
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.ctrl
          | Some _ -> fail "first event was not key a"
          | None -> fail "first event was lost");
          (match
             Flow.read_once input ~clock ~source ~emit:(emit_to queue)
           with
          | Ok Flow.End_of_input -> ()
          | Ok (Flow.Backpressured count) ->
              failf "the freed queue remained blocked after %d bytes" count
          | Ok (Flow.Bytes_read _) -> fail "expected EOF after the first read"
          | Error error -> fail (Flow.message error));
          match Events.read queue with
          | Some
              (Events.Input
                (Input.Key
                  {
                    key = Opentui_core.Lib.Key_decoder.Character bytes;
                    modifiers;
                  })) ->
              equal string "b" (Bytes.to_string bytes);
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.shift;
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.meta;
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.ctrl
          | Some _ -> fail "second event was not key b"
          | None -> fail "second event was lost");
      test "retains a source suffix across a blocked sink" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:5000 ()) in
          let payload = Bytes.to_string (Bytes.make 5000 'a') in
          let source = Eio.Flow.string_source payload in
          let clock = Eio.Stdenv.mono_clock env in
          let blocked = ref true in
          let attempts = ref 0 in
          let accepted = ref 0 in
          let emit _event =
            attempts := !attempts + 1;
            if !blocked then (
              blocked := false;
              Coordinator.Full)
            else (
              accepted := !accepted + 1;
              Coordinator.Accepted)
          in
          (match Flow.read_once input ~clock ~source ~emit with
          | Ok (Flow.Backpressured 5000) -> ()
          | Ok Flow.End_of_input -> fail "source ended before the full chunk"
          | Ok (Flow.Backpressured count) ->
              failf "expected 5000 backpressured bytes, got %d" count
          | Ok (Flow.Bytes_read count) ->
              failf "expected 5000 bytes, got %d" count
          | Error error -> fail (Flow.message error));
          (match Flow.read_once input ~clock ~source ~emit with
          | Ok Flow.End_of_input -> ()
          | Ok (Flow.Backpressured count) ->
              failf "the accepted sink remained blocked after %d bytes" count
          | Ok (Flow.Bytes_read _) -> fail "expected EOF after the retained suffix"
          | Error error -> fail (Flow.message error));
          equal int 5001 !attempts;
          equal int 5000 !accepted);
      test "starts a retained-prefix timeout when bytes enter the parser" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:4097 ~timeout_ms:1 ()) in
          let prefix = Bytes.make 4096 'a' in
          let payload = Bytes.create 4097 in
          Bytes.blit prefix 0 payload 0 4096;
          Bytes.set_uint8 payload 4096 0x1b;
          let source = Eio.Flow.string_source (Bytes.to_string payload) in
          let clock = Eio.Stdenv.mono_clock env in
          let blocked = ref true in
          let accepted = ref 0 in
          let emit _event =
            if !blocked then (
              blocked := false;
              Coordinator.Full)
            else (
              accepted := !accepted + 1;
              Coordinator.Accepted)
          in
          (match Flow.read_once input ~clock ~source ~emit with
          | Ok (Flow.Backpressured 4097) -> ()
          | Ok Flow.End_of_input -> fail "source ended before the retained ESC"
          | Ok (Flow.Bytes_read count) ->
              failf "expected backpressure after %d bytes" count
          | Ok (Flow.Backpressured count) ->
              failf "expected 4097 backpressured bytes, got %d" count
          | Error error -> fail (Flow.message error));
          Eio.Time.Mono.sleep clock 0.005;
          (match Flow.read_once input ~clock ~source ~emit with
          | Ok Flow.End_of_input -> ()
          | Ok (Flow.Backpressured count) ->
              failf "retained ESC remained blocked after %d bytes" count
          | Ok (Flow.Bytes_read count) ->
              failf "unexpected source data after %d bytes" count
          | Error error -> fail (Flow.message error));
          let accepted_before_timeout = !accepted in
          expect_accepted
            (expect_ok (Flow.fire_timeout input ~clock ~emit));
          if not
            (Int.equal !accepted accepted_before_timeout
            || Int.equal !accepted (accepted_before_timeout + 1))
          then
            failf "timeout delivered %d events after the retained prefix"
              (!accepted - accepted_before_timeout));
      test "delivers the latest motion through queue coalescing" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:64 ()) in
          let queue =
            match Events.create ~capacity:1 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let payload = "\x1b[<35;2;2M\x1b[<35;3;3M" in
          let source = Eio.Flow.string_source payload in
          let clock = Eio.Stdenv.mono_clock env in
          (match
             Flow.read_once input ~clock ~source ~emit:(emit_to queue)
           with
          | Ok (Flow.Bytes_read count) ->
              equal int (String.length payload) count
          | Ok Flow.End_of_input -> fail "source ended before mouse motion"
          | Ok (Flow.Backpressured count) ->
              failf "motion unexpectedly backpressured after %d bytes" count
          | Error error -> fail (Flow.message error));
          match Events.read queue with
          | Some (Events.Input (Input.Mouse { event; _ })) ->
              (match event.Opentui_core.Lib.Mouse_decoder.kind with
              | Opentui_core.Lib.Mouse_decoder.Move ->
                  equal int 2 event.Opentui_core.Lib.Mouse_decoder.x;
                  equal int 2 event.Opentui_core.Lib.Mouse_decoder.y
              | Opentui_core.Lib.Mouse_decoder.Down
              | Opentui_core.Lib.Mouse_decoder.Up
              | Opentui_core.Lib.Mouse_decoder.Drag
              | Opentui_core.Lib.Mouse_decoder.Scroll ->
                  fail "motion coalescing changed the event kind")
          | Some _ -> fail "coalesced motion emitted a non-mouse event"
          | None -> fail "coalesced motion was lost")
    ]
