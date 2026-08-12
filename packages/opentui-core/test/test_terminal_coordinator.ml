open Windtrap
module Coordinator = Opentui_core.Lib.Input_coordinator
module Input = Opentui_core.Lib.Stdin_parser

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Coordinator.message error)

let expect_push result =
  match result with
  | Coordinator.Accepted_all -> ()
  | Coordinator.Full_after count ->
      failf "input was backpressured after %d bytes" count

let expect_accepted = function
  | Coordinator.Accepted -> ()
  | Coordinator.Full -> fail "event sink unexpectedly reported Full"

let sink () =
  let events = Queue.create () in
  let emit event =
    Queue.add event events;
    Coordinator.Accepted
  in
  (events, emit)

let expect_deadline expected actual =
  match (expected, actual) with
  | None, None -> ()
  | Some expected, Some actual -> equal int64 expected actual
  | None, Some _ -> fail "expected no timeout deadline"
  | Some _, None -> fail "expected a timeout deadline"

let () =
  run "opentui-core-coordinator"
    [
      test "arms and fires one parser deadline" (fun () ->
          let coordinator = expect_ok (Coordinator.create ~timeout_ms:20 ()) in
          let events, emit = sink () in
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:100L ~emit
                  ~source:(Bytes.of_string "\x1b") ~off:0 ~len:1));
          expect_deadline (Some 120L) (Coordinator.deadline coordinator);
          equal int 0 (Queue.length events);
          expect_accepted
            (Coordinator.fire_timeout coordinator ~now_ms:119L ~emit);
          expect_deadline (Some 120L) (Coordinator.deadline coordinator);
          equal int 0 (Queue.length events);
          expect_accepted
            (Coordinator.fire_timeout coordinator ~now_ms:120L ~emit);
          expect_deadline None (Coordinator.deadline coordinator);
          match Queue.take events with
          | Input.Key { key = Opentui_core.Lib.Key_decoder.Named Escape; _ } ->
              ()
          | _ -> fail "timeout emitted the wrong key");
      test "continuation before deadline wins and disarms" (fun () ->
          let coordinator = expect_ok (Coordinator.create ~timeout_ms:20 ()) in
          let events, emit = sink () in
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:100L ~emit
                  ~source:(Bytes.of_string "\x1b[") ~off:0 ~len:2));
          expect_deadline (Some 120L) (Coordinator.deadline coordinator);
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:110L ~emit
                  ~source:(Bytes.of_string "A") ~off:0 ~len:1));
          expect_deadline None (Coordinator.deadline coordinator);
          match Queue.take events with
          | Input.Key { key = Opentui_core.Lib.Key_decoder.Named Up; _ } -> ()
          | _ -> fail "continuation emitted the wrong key");
      test "refreshes the deadline for a still-incomplete continuation"
        (fun () ->
          let coordinator = expect_ok (Coordinator.create ~timeout_ms:20 ()) in
          let events, emit = sink () in
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:100L ~emit
                  ~source:(Bytes.of_string "\x1b") ~off:0 ~len:1));
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:110L ~emit
                  ~source:(Bytes.of_string "[") ~off:0 ~len:1));
          expect_deadline (Some 130L) (Coordinator.deadline coordinator);
          expect_accepted
            (Coordinator.fire_timeout coordinator ~now_ms:129L ~emit);
          equal int 0 (Queue.length events);
          expect_accepted
            (Coordinator.fire_timeout coordinator ~now_ms:130L ~emit);
          expect_deadline None (Coordinator.deadline coordinator);
          match Queue.take events with
          | Input.Response { protocol = Input.Unknown; bytes } ->
              equal string "\x1b[" (Bytes.to_string bytes)
          | Input.Response _ -> fail "incomplete CSI used the wrong protocol"
          | Input.Key _ -> fail "incomplete CSI emitted a key"
          | Input.Mouse _ -> fail "incomplete CSI emitted a mouse event"
          | Input.Paste _ -> fail "incomplete CSI emitted a paste"
          | exception Queue.Empty -> fail "timeout emitted no event");
      test "does not extend a deadline during a blocked no-progress retry"
        (fun () ->
          let coordinator = expect_ok (Coordinator.create ~timeout_ms:20 ()) in
          let events = Queue.create () in
          let blocked = ref true in
          let emit event =
            if !blocked then Coordinator.Full
            else (
              Queue.add event events;
              Coordinator.Accepted)
          in
          (match
             Coordinator.push_bytes coordinator ~now_ms:0L ~emit
               ~source:(Bytes.of_string "A\x1b") ~off:0 ~len:2
           with
          | Ok (Coordinator.Full_after 2) -> ()
          | Ok Coordinator.Accepted_all ->
              fail "the sink unexpectedly accepted A"
          | Ok (Coordinator.Full_after count) ->
              failf "expected two consumed bytes, got %d" count
          | Error error -> fail (Coordinator.message error));
          expect_deadline (Some 20L) (Coordinator.deadline coordinator);
          (match
             Coordinator.push_bytes coordinator ~now_ms:15L ~emit
               ~source:Bytes.empty ~off:0 ~len:0
           with
          | Ok (Coordinator.Full_after 0) -> ()
          | Ok Coordinator.Accepted_all ->
              fail "the blocked sink unexpectedly accepted an event"
          | Ok (Coordinator.Full_after count) ->
              failf "expected no-progress retry, got %d bytes" count
          | Error error -> fail (Coordinator.message error));
          expect_deadline (Some 20L) (Coordinator.deadline coordinator);
          (match Coordinator.fire_timeout coordinator ~now_ms:20L ~emit with
          | Coordinator.Full -> ()
          | Coordinator.Accepted ->
              fail "the blocked timeout unexpectedly accepted an event");
          expect_deadline (Some 20L) (Coordinator.deadline coordinator);
          blocked := false;
          expect_accepted
            (Coordinator.fire_timeout coordinator ~now_ms:20L ~emit);
          expect_deadline None (Coordinator.deadline coordinator);
          equal int 2 (Queue.length events);
          match (Queue.take events, Queue.take events) with
          | ( Input.Key { key = Opentui_core.Lib.Key_decoder.Character _; _ },
              Input.Key { key = Opentui_core.Lib.Key_decoder.Named Escape; _ } )
            ->
              ()
          | _ -> fail "blocked input or timeout escape was lost");
      test
        "reset clears pending bytes, framed events, deadline, and mouse state"
        (fun () ->
          let coordinator = expect_ok (Coordinator.create ~timeout_ms:20 ()) in
          let blocked _event = Coordinator.Full in
          (match
             Coordinator.push_bytes coordinator ~now_ms:90L ~emit:blocked
               ~source:(Bytes.of_string "A") ~off:0 ~len:1
           with
          | Ok (Coordinator.Full_after 1) -> ()
          | Ok Coordinator.Accepted_all ->
              fail "the blocked sink unexpectedly accepted the first event"
          | Ok (Coordinator.Full_after count) ->
              failf "expected one consumed byte, got %d" count
          | Error error -> fail (Coordinator.message error));
          (match
             Coordinator.push_bytes coordinator ~now_ms:100L ~emit:blocked
               ~source:(Bytes.of_string "\x1b") ~off:0 ~len:1
           with
          | Ok (Coordinator.Full_after 0) -> ()
          | Ok Coordinator.Accepted_all ->
              fail "the blocked sink unexpectedly accepted the second event"
          | Ok (Coordinator.Full_after count) ->
              failf "expected no additional consumed byte, got %d" count
          | Error error -> fail (Coordinator.message error));
          Coordinator.reset coordinator;
          expect_deadline None (Coordinator.deadline coordinator);
          equal int 0 (Coordinator.pending_bytes coordinator);
          let events, emit = sink () in
          expect_accepted (Coordinator.drain coordinator ~emit);
          equal int 0 (Queue.length events);
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:200L ~emit
                  ~source:(Bytes.of_string "\x1b[<32;8;6M")
                  ~off:0 ~len:10));
          match Queue.take events with
          | Input.Mouse { event; _ } -> (
              match event.Opentui_core.Lib.Mouse_decoder.kind with
              | Opentui_core.Lib.Mouse_decoder.Move -> ()
              | _ -> fail "reset leaked mouse button state")
          | _ -> fail "reset emitted the wrong event");
      test "a complete event does not arm a deadline" (fun () ->
          let coordinator = expect_ok (Coordinator.create ~timeout_ms:20 ()) in
          let events, emit = sink () in
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:100L ~emit
                  ~source:(Bytes.of_string "A") ~off:0 ~len:1));
          expect_deadline None (Coordinator.deadline coordinator);
          match Queue.take events with
          | Input.Key { key = Opentui_core.Lib.Key_decoder.Character _; _ } ->
              ()
          | _ -> fail "complete input emitted the wrong event");
      test "an empty push emits an empty key event" (fun () ->
          let coordinator = expect_ok (Coordinator.create ()) in
          let events, emit = sink () in
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:100L ~emit
                  ~source:Bytes.empty ~off:0 ~len:0));
          expect_deadline None (Coordinator.deadline coordinator);
          match Queue.take events with
          | Input.Key
              { key = Opentui_core.Lib.Key_decoder.Character bytes; modifiers }
            ->
              equal string "" (Bytes.to_string bytes);
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.shift;
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.meta;
              equal bool false modifiers.Opentui_core.Lib.Key_decoder.ctrl
          | _ -> fail "empty input emitted the wrong event");
      test "reports a precise prefix and preserves every blocked input byte"
        (fun () ->
          let coordinator = expect_ok (Coordinator.create ()) in
          let payload = Bytes.make 5000 'a' in
          let blocked _event = Coordinator.Full in
          (match
             Coordinator.push_bytes coordinator ~now_ms:0L ~emit:blocked
               ~source:payload ~off:0 ~len:(Bytes.length payload)
           with
          | Ok (Coordinator.Full_after 4096) -> ()
          | Ok Coordinator.Accepted_all ->
              fail "the full sink unexpectedly accepted all input"
          | Ok (Coordinator.Full_after count) ->
              failf "expected a 4096-byte prefix, got %d" count
          | Error error -> fail (Coordinator.message error));
          let events, emit = sink () in
          expect_accepted (Coordinator.drain coordinator ~emit);
          expect_push
            (expect_ok
               (Coordinator.push_bytes coordinator ~now_ms:0L ~emit
                  ~source:payload ~off:4096 ~len:904));
          equal int 5000 (Queue.length events));
    ]
