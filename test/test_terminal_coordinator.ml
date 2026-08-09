open Windtrap

module Coordinator = Opentui_terminal.Input_coordinator
module Input = Opentui_terminal.Input_decoder

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Coordinator.message error)

let expect_deadline expected actual =
  match expected, actual with
  | None, None -> ()
  | Some expected, Some actual -> equal int64 expected actual
  | None, Some _ -> fail "expected no timeout deadline"
  | Some _, None -> fail "expected a timeout deadline"

let () =
  run "opentui-terminal-coordinator"
    [
      test "arms and fires one parser deadline" (fun () ->
          let coordinator =
            expect_ok (Coordinator.create ~timeout_ms:20 ())
          in
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:100L
               ~source:(Bytes.of_string "\x1b") ~off:0 ~len:1);
          expect_deadline (Some 120L) (Coordinator.deadline coordinator);
          (match Coordinator.read coordinator with
          | None -> ()
          | Some _ -> fail "incomplete escape was emitted before timeout");
          Coordinator.fire_timeout coordinator ~now_ms:119L;
          expect_deadline (Some 120L) (Coordinator.deadline coordinator);
          (match Coordinator.read coordinator with
          | None -> ()
          | Some _ -> fail "early timeout emitted an event");
          Coordinator.fire_timeout coordinator ~now_ms:120L;
          expect_deadline None (Coordinator.deadline coordinator);
          match Coordinator.read coordinator with
          | Some (Input.Key { key = Opentui_terminal.Key_decoder.Named Escape; _ }) ->
              ()
          | Some _ -> fail "timeout emitted the wrong key"
          | None -> fail "timeout did not emit the pending escape");
      test "continuation before deadline wins and disarms" (fun () ->
          let coordinator =
            expect_ok (Coordinator.create ~timeout_ms:20 ())
          in
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:100L
               ~source:(Bytes.of_string "\x1b[") ~off:0 ~len:2);
          expect_deadline (Some 120L) (Coordinator.deadline coordinator);
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:110L
               ~source:(Bytes.of_string "A") ~off:0 ~len:1);
          expect_deadline None (Coordinator.deadline coordinator);
          match Coordinator.read coordinator with
          | Some (Input.Key { key = Opentui_terminal.Key_decoder.Named Up; _ }) ->
              ()
          | Some _ -> fail "continuation emitted the wrong key"
          | None -> fail "continuation did not emit a key");
      test "refreshes the deadline for a still-incomplete continuation" (fun () ->
          let coordinator =
            expect_ok (Coordinator.create ~timeout_ms:20 ())
          in
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:100L
               ~source:(Bytes.of_string "\x1b") ~off:0 ~len:1);
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:110L
               ~source:(Bytes.of_string "[") ~off:0 ~len:1);
          expect_deadline (Some 130L) (Coordinator.deadline coordinator);
          Coordinator.fire_timeout coordinator ~now_ms:129L;
          (match Coordinator.read coordinator with
          | None -> ()
          | Some _ -> fail "refreshed timeout emitted too early");
          Coordinator.fire_timeout coordinator ~now_ms:130L;
          expect_deadline None (Coordinator.deadline coordinator);
          match Coordinator.read coordinator with
          | Some
              (Input.Key
                {
                  key = Opentui_terminal.Key_decoder.Character bytes;
                  modifiers;
                }) ->
              equal string "[" (Bytes.to_string bytes);
              equal bool true modifiers.Opentui_terminal.Key_decoder.meta
          | Some (Input.Key _) -> fail "incomplete CSI emitted a key"
          | Some (Input.Sequence _) ->
              fail "incomplete CSI remained an unexpected opaque sequence"
          | Some (Input.Mouse _) -> fail "incomplete CSI emitted a mouse event"
          | Some (Input.Paste _) -> fail "incomplete CSI emitted a paste"
          | None -> fail "refreshed timeout did not flush the sequence");
      test "reset clears pending bytes, events, deadline, and mouse state" (fun () ->
          let coordinator =
            expect_ok (Coordinator.create ~timeout_ms:20 ())
          in
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:90L
               ~source:(Bytes.of_string "A") ~off:0 ~len:1);
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:100L
               ~source:(Bytes.of_string "\x1b") ~off:0 ~len:1);
          Coordinator.reset coordinator;
          expect_deadline None (Coordinator.deadline coordinator);
          equal int 0 (Coordinator.pending_bytes coordinator);
          (match Coordinator.read coordinator with
          | None -> ()
          | Some _ -> fail "reset retained a queued event");
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:200L
               ~source:(Bytes.of_string "\x1b[<32;8;6M") ~off:0 ~len:10);
          match Coordinator.read coordinator with
          | Some (Input.Mouse event) ->
              (match event.Opentui_terminal.Mouse_decoder.kind with
              | Opentui_terminal.Mouse_decoder.Move -> ()
              | _ -> fail "reset leaked mouse button state")
          | Some _ -> fail "reset emitted the wrong event"
          | None -> fail "reset input did not emit a mouse event");
      test "a complete event does not arm a deadline" (fun () ->
          let coordinator =
            expect_ok (Coordinator.create ~timeout_ms:20 ())
          in
          expect_ok
            (Coordinator.push_bytes coordinator ~now_ms:100L
               ~source:(Bytes.of_string "A") ~off:0 ~len:1);
          expect_deadline None (Coordinator.deadline coordinator);
          match Coordinator.read coordinator with
          | Some (Input.Key { key = Opentui_terminal.Key_decoder.Character _; _ }) ->
              ()
          | Some _ -> fail "complete input emitted the wrong event"
          | None -> fail "complete input did not emit an event")
    ]
