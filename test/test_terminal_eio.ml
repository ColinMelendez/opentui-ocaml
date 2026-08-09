open Windtrap

module Flow = Opentui_terminal_eio.Input_flow
module Input = Opentui_terminal.Input_decoder
module Events = Opentui_terminal.Event_queue

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Flow.message error)

let expect_deadline expected actual =
  match expected, actual with
  | None, None -> ()
  | Some expected, Some actual -> equal int64 expected actual
  | None, Some _ -> fail "expected no timeout deadline"
  | Some _, None -> fail "expected a timeout deadline"

let () =
  run "opentui-terminal-eio"
    [
      test "rejects a zero-sized reusable flow buffer" (fun () ->
          match Flow.create ~buffer_size:0 () with
          | Error Flow.Invalid_buffer_size -> ()
          | Error error -> fail (Flow.message error)
          | Ok _ -> fail "expected invalid buffer size");
      test "reads a reusable flow buffer into typed events" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:8 ~timeout_ms:20 ()) in
          let source = Eio.Flow.string_source "\x1b[A" in
          let clock = Eio.Stdenv.mono_clock env in
          match Flow.read_once input ~clock ~source with
          | Error error -> fail (Flow.message error)
          | Ok Flow.End_of_input -> fail "source ended before the key"
          | Ok (Flow.Bytes_read count) ->
              equal int 3 count;
              expect_deadline None (Flow.deadline input);
              (match Flow.read input with
              | Some (Input.Key { key = Opentui_terminal.Key_decoder.Named Up; _ }) ->
                  ()
              | Some _ -> fail "flow adapter emitted the wrong event"
              | None -> fail "flow adapter emitted no event");
              (match Flow.read_once input ~clock ~source with
              | Ok Flow.End_of_input -> ()
              | Ok (Flow.Bytes_read _) -> fail "expected EOF after one source"
              | Error error -> fail (Flow.message error)));
      test "fires the coordinator timeout through the Eio clock" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:8 ~timeout_ms:1 ()) in
          let source = Eio.Flow.string_source "\x1b" in
          let clock = Eio.Stdenv.mono_clock env in
          match Flow.read_once input ~clock ~source with
          | Error error -> fail (Flow.message error)
          | Ok Flow.End_of_input -> fail "source ended before the escape"
          | Ok (Flow.Bytes_read 1) ->
              (match Flow.read input with
              | None -> ()
              | Some _ -> fail "incomplete escape emitted too early");
              Eio.Time.Mono.sleep clock 0.005;
              Flow.fire_timeout input ~clock;
              (match Flow.read input with
              | Some (Input.Key { key = Opentui_terminal.Key_decoder.Named Escape; _ }) ->
                  ()
              | Some _ -> fail "timeout emitted the wrong event"
              | None -> fail "timeout emitted no event")
          | Ok (Flow.Bytes_read _) -> fail "unexpected byte count");
      test "transfers one owned input event without losing it on full" (fun () ->
          Eio_main.run @@ fun env ->
          let input = expect_ok (Flow.create ~buffer_size:8 ()) in
          let queue =
            match Events.create ~capacity:1 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let source = Eio.Flow.string_source "ab" in
          let clock = Eio.Stdenv.mono_clock env in
          (match Flow.transfer_one input ~queue with
          | Ok false -> ()
          | Ok true -> fail "empty input reported a transferred event"
          | Error error -> fail (Events.message error));
          (match Flow.read_once input ~clock ~source with
          | Ok (Flow.Bytes_read 2) -> ()
          | Ok Flow.End_of_input -> fail "source ended before both keys"
          | Ok (Flow.Bytes_read count) ->
              fail (Printf.sprintf "expected two bytes, got %d" count)
          | Error error -> fail (Flow.message error));
          (match Flow.transfer_one input ~queue with
          | Ok true -> ()
          | Ok false -> fail "first input event was absent"
          | Error error -> fail (Events.message error));
          (match Flow.transfer_one input ~queue with
          | Error Events.Full -> ()
          | Error Events.Invalid_capacity -> fail "unexpected capacity error"
          | Ok true -> fail "full destination accepted a second key"
          | Ok false -> fail "second input event was absent");
          (match Events.read queue with
          | Some
              (Events.Input
                (Input.Key
                  {
                    key = Opentui_terminal.Key_decoder.Character bytes;
                    modifiers;
                  })) ->
              equal string "a" (Bytes.to_string bytes);
              equal bool false
                modifiers.Opentui_terminal.Key_decoder.shift;
              equal bool false modifiers.Opentui_terminal.Key_decoder.meta;
              equal bool false modifiers.Opentui_terminal.Key_decoder.ctrl
          | Some _ -> fail "first transferred event was not key a"
          | None -> fail "first transferred event was lost");
          (match Flow.transfer_one input ~queue with
          | Ok true -> ()
          | Ok false -> fail "pending input event was lost"
          | Error error -> fail (Events.message error));
          match Events.read queue with
          | Some
              (Events.Input
                (Input.Key
                  {
                    key = Opentui_terminal.Key_decoder.Character bytes;
                    modifiers;
                  })) ->
              equal string "b" (Bytes.to_string bytes);
              equal bool false
                modifiers.Opentui_terminal.Key_decoder.shift;
              equal bool false modifiers.Opentui_terminal.Key_decoder.meta;
              equal bool false modifiers.Opentui_terminal.Key_decoder.ctrl
          | Some _ -> fail "second transferred event was not key b"
          | None -> fail "second transferred event was lost");
      test "transfers motion through a full destination by coalescing" (fun () ->
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
          (match Flow.read_once input ~clock ~source with
          | Ok (Flow.Bytes_read count) ->
              equal int (String.length payload) count
          | Ok Flow.End_of_input -> fail "source ended before mouse motion"
          | Error error -> fail (Flow.message error));
          (match Flow.transfer_one input ~queue with
          | Ok true -> ()
          | Ok false -> fail "first mouse motion was absent"
          | Error error -> fail (Events.message error));
          (match Flow.transfer_one input ~queue with
          | Ok true -> ()
          | Ok false -> fail "second mouse motion was absent"
          | Error error -> fail (Events.message error));
          (match Flow.transfer_one input ~queue with
          | Ok false -> ()
          | Ok true -> fail "unexpected third mouse motion"
          | Error error -> fail (Events.message error));
          match Events.read queue with
          | Some (Events.Input (Input.Mouse event)) ->
              (match event.Opentui_terminal.Mouse_decoder.kind with
              | Opentui_terminal.Mouse_decoder.Move ->
                  equal int 2 event.Opentui_terminal.Mouse_decoder.x;
                  equal int 2 event.Opentui_terminal.Mouse_decoder.y
              | Opentui_terminal.Mouse_decoder.Down
              | Opentui_terminal.Mouse_decoder.Up
              | Opentui_terminal.Mouse_decoder.Drag
              | Opentui_terminal.Mouse_decoder.Scroll ->
                  fail "motion transfer changed the event kind")
          | Some _ -> fail "motion transfer emitted a non-mouse event"
          | None -> fail "coalesced motion was lost")
    ]
