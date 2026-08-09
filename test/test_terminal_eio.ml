open Windtrap

module Flow = Opentui_terminal_eio.Input_flow
module Input = Opentui_terminal.Input_decoder

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
          | Ok (Flow.Bytes_read _) -> fail "unexpected byte count")
    ]
