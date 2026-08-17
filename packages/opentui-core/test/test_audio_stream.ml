open Windtrap

module Audio = Opentui_core.Audio_stream

exception Owner_switch_cancelled
exception Connect_raised
exception Read_raised
exception Cleanup_raised
exception Retry_policy_raised
exception Observer_raised

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Audio.Error.message error)

let () =
  run "opentui-core-audio-stream"
    [
      test "owner-domain stream exposes metadata and terminal lifecycle" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
          let engine = expect_ok (Audio.Engine.create ~owner) in
          let step = ref 0 in
          let connector =
            Audio.Stream.connector
              ~connect:(fun ~attempt:_ ~cancel:_ ->
                let connection =
                  Audio.Stream.connection ~initial_metadata:(Some "initial")
                    ~next:(fun _ ->
                      let current = !step in
                      incr step;
                      match current with
                      | 0 -> Ok (Audio.Stream.Metadata (Some "next"))
                      | 1 -> Ok (Audio.Stream.Data (Bytes.of_string "abc"))
                      | _ -> Ok Audio.Stream.End)
                    ~close:(fun () -> Ok ())
                in
                Ok connection)
          in
          let options = expect_ok (Audio.Options.create ()) in
          let stream =
            expect_ok
              (Audio.Stream.open_ ~engine ~owner ~connector ~options)
          in
          let metadata = ref [] in
          let ended = ref 0 in
          ignore
            (expect_ok
               (Audio.Stream.on_metadata stream (fun event ->
                    metadata := Option.value event.value ~default:"" :: !metadata)));
          ignore
            (expect_ok
               (Audio.Stream.on_ended stream (fun _ -> incr ended)));
          let terminal = expect_ok (Audio.Stream.await_closed stream) in
          (match terminal with
          | Audio.Stream.Ended_terminal -> ()
          | Audio.Stream.Disposed_terminal -> fail "stream was disposed"
          | Audio.Stream.Errored_terminal error ->
              fail (Audio.Error.message error));
          (match List.rev !metadata with
          | [] -> fail "metadata event was not delivered"
          | values ->
              if not (List.exists (String.equal "next") values) then
                fail "latest metadata event was not delivered");
          equal int 1 !ended;
          let stats = expect_ok (Audio.Stream.get_stats stream) in
          equal int 3 stats.bytes_received;
          equal int 0 stats.attempt;
          equal int 1 stats.generation;
          (match expect_ok (Audio.Stream.metadata stream) with
          | Some value when String.equal value "next" -> ()
          | Some _ -> fail "latest metadata value was not retained"
          | None -> fail "latest metadata value was lost");
          equal bool true (expect_ok (Audio.Stream.is_exposed stream));
          ignore (expect_ok (Audio.Stream.close stream));
          ignore (expect_ok (Audio.Stream.close stream)));
      test "retry options reject invalid backoff values" (fun () ->
          match Audio.Options.create ~max_retries:(-1) () with
          | Error error ->
              (match error.Audio.Error.reason with
              | Audio.Error.Invalid_options -> ()
              | _ -> fail "invalid options returned the wrong reason")
          | Ok options ->
              ignore options;
              fail "negative retry count was accepted");
      test "source and cleanup exceptions remain structured" (fun () ->
          Eio_main.run @@ fun env ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let connect_case () =
            Eio.Switch.run @@ fun sw ->
            let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
            let engine = expect_ok (Audio.Engine.create ~owner) in
            let connector =
              Audio.Stream.connector
                ~connect:(fun ~attempt:_ ~cancel:_ -> raise Connect_raised)
            in
            let options = expect_ok (Audio.Options.create ()) in
            match Audio.Stream.open_~engine ~owner ~connector ~options with
            | Error error ->
                (match error.Audio.Error.reason with
                | Audio.Error.Retry_exhausted (Audio.Error.Exception _) -> ()
                | _ -> fail "connection exception lost its structured reason")
            | Ok stream ->
                ignore (expect_ok (Audio.Stream.close stream));
                fail "connection exception unexpectedly exposed a stream"
          in
          let read_case () =
            Eio.Switch.run @@ fun sw ->
            let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
            let engine = expect_ok (Audio.Engine.create ~owner) in
            let connector =
              Audio.Stream.connector
                ~connect:(fun ~attempt:_ ~cancel:_ ->
                  Ok
                    (Audio.Stream.connection ~initial_metadata:None
                       ~next:(fun _ -> raise Read_raised)
                       ~close:(fun () -> Ok ())))
            in
            let options = expect_ok (Audio.Options.create ()) in
            let stream =
              expect_ok
                (Audio.Stream.open_~engine ~owner ~connector ~options)
            in
            match expect_ok (Audio.Stream.await_closed stream) with
            | Audio.Stream.Errored_terminal error ->
                (match error.Audio.Error.reason with
                | Audio.Error.Retry_exhausted (Audio.Error.Exception _) -> ()
                | _ -> fail "read exception lost its structured reason")
            | Audio.Stream.Ended_terminal ->
                fail "read exception was reported as a clean end"
            | Audio.Stream.Disposed_terminal ->
                fail "read exception was reported as disposal"
          in
          let cleanup_case () =
            Eio.Switch.run @@ fun sw ->
            let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
            let engine = expect_ok (Audio.Engine.create ~owner) in
            let connector =
              Audio.Stream.connector
                ~connect:(fun ~attempt:_ ~cancel:_ ->
                  Ok
                    (Audio.Stream.connection ~initial_metadata:None
                       ~next:(fun _ -> Ok Audio.Stream.End)
                       ~close:(fun () -> raise Cleanup_raised)))
            in
            let options = expect_ok (Audio.Options.create ()) in
            let stream =
              expect_ok
                (Audio.Stream.open_~engine ~owner ~connector ~options)
            in
            match expect_ok (Audio.Stream.await_closed stream) with
            | Audio.Stream.Errored_terminal error ->
                (match error.Audio.Error.reason with
                | Audio.Error.Cleanup_failure (Audio.Error.Exception _) -> ()
                | _ -> fail "cleanup exception lost its structured reason")
            | Audio.Stream.Ended_terminal ->
                fail "cleanup exception was reported as a clean end"
            | Audio.Stream.Disposed_terminal ->
                fail "cleanup exception was reported as disposal"
          in
          let retry_policy_case () =
            Eio.Switch.run @@ fun sw ->
            let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
            let engine = expect_ok (Audio.Engine.create ~owner) in
            let connector =
              Audio.Stream.connector
                ~connect:(fun ~attempt:_ ~cancel:_ ->
                  Ok
                    (Audio.Stream.connection ~initial_metadata:None
                       ~next:(fun _ -> Error Audio.Error.Transport)
                       ~close:(fun () -> Ok ())))
            in
            let options =
              expect_ok
                (Audio.Options.create ~max_retries:1
                   ~should_retry:(fun ~retry:_ ~phase:_ ~error:_ ->
                     raise Retry_policy_raised)
                   ())
            in
            let stream =
              expect_ok
                (Audio.Stream.open_~engine ~owner ~connector ~options)
            in
            match expect_ok (Audio.Stream.await_closed stream) with
            | Audio.Stream.Errored_terminal error ->
                (match error.Audio.Error.reason with
                | Audio.Error.Retry_policy_failure _ -> ()
                | _ -> fail "retry-policy exception lost its structured reason")
            | Audio.Stream.Ended_terminal ->
                fail "retry-policy exception was reported as a clean end"
            | Audio.Stream.Disposed_terminal ->
                fail "retry-policy exception was reported as disposal"
          in
          connect_case ();
          read_case ();
          cleanup_case ();
          retry_policy_case ());
      test "retries use fresh attempts and generations" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
          let engine = expect_ok (Audio.Engine.create ~owner) in
          let connect_count = ref 0 in
          let attempts = ref [] in
          let closes = ref 0 in
          let connector =
            Audio.Stream.connector
              ~connect:(fun ~attempt ~cancel:_ ->
                let connection_index = !connect_count in
                incr connect_count;
                attempts := attempt :: !attempts;
                let next =
                  if Int.equal connection_index 0 then
                    fun _ -> Error Audio.Error.Transport
                  else fun _ -> Ok Audio.Stream.End
                in
                Ok
                  (Audio.Stream.connection ~initial_metadata:None ~next
                     ~close:(fun () -> incr closes; Ok ())))
          in
          let options =
            expect_ok (Audio.Options.create ~max_retries:1 ~initial_delay:0.0 ())
          in
          let stream =
            expect_ok
              (Audio.Stream.open_ ~engine ~owner ~connector ~options)
          in
          let retries = ref [] in
          let ended = ref 0 in
          let ended_generation = ref None in
          ignore
            (expect_ok
               (Audio.Stream.on_reconnecting stream (fun event ->
                    retries := (event.generation, event.retry) :: !retries)));
          ignore
            (expect_ok
               (Audio.Stream.on_ended stream (fun event ->
                    incr ended;
                    ended_generation := Some event.generation)));
          (match expect_ok (Audio.Stream.await_closed stream) with
          | Audio.Stream.Ended_terminal -> ()
          | Audio.Stream.Disposed_terminal -> fail "retry stream was disposed"
          | Audio.Stream.Errored_terminal error ->
              fail (Audio.Error.message error));
          (match List.rev !attempts with
          | [ 0; 0 ] -> ()
          | _ -> fail "retry connector attempts did not reset after admission");
          (match List.rev !retries with
          | [ (1, 1) ] -> ()
          | _ -> fail "accepted retry did not publish retry ordinal one");
          equal int 2 !connect_count;
          equal int 2 !closes;
          equal int 1 !ended;
          equal (option int) (Some 2) !ended_generation;
          let stats = expect_ok (Audio.Stream.get_stats stream) in
          equal int 2 stats.generation;
          equal int 0 stats.attempt;
          equal int 1 stats.reconnects);
      test "close cancels the owner attempt and waits for disposal" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
          let engine = expect_ok (Audio.Engine.create ~owner) in
          let closes = ref 0 in
          let disposed = ref 0 in
          let ended = ref 0 in
          let errors = ref 0 in
          let connector =
            Audio.Stream.connector
              ~connect:(fun ~attempt:_ ~cancel:_ ->
                Ok
                  (Audio.Stream.connection ~initial_metadata:None
                     ~next:(fun cancel ->
                       Audio.Stream.Cancellation.await cancel;
                       Ok Audio.Stream.End)
                     ~close:(fun () -> incr closes; Ok ())))
          in
          let options = expect_ok (Audio.Options.create ()) in
          let stream =
            expect_ok
              (Audio.Stream.open_ ~engine ~owner ~connector ~options)
          in
          let callback_close_succeeded = ref false in
          ignore
            (expect_ok
               (Audio.Stream.on_disposed stream (fun _ ->
                    incr disposed;
                    match Audio.Stream.close stream with
                    | Ok () -> callback_close_succeeded := true
                    | Error _ -> ())));
          ignore
            (expect_ok
               (Audio.Stream.on_ended stream (fun _ -> incr ended)));
          ignore
            (expect_ok
               (Audio.Stream.on_error stream (fun _ -> incr errors)));
          ignore (expect_ok (Audio.Stream.close stream));
          (match expect_ok (Audio.Stream.await_closed stream) with
          | Audio.Stream.Disposed_terminal -> ()
          | Audio.Stream.Ended_terminal -> fail "close was reported as ended"
          | Audio.Stream.Errored_terminal error ->
              fail (Audio.Error.message error));
          equal int 1 !closes;
          equal int 1 !disposed;
          equal int 0 !ended;
          equal int 0 !errors;
          equal bool true !callback_close_succeeded;
          let stats = expect_ok (Audio.Stream.get_stats stream) in
          equal int 2 stats.generation;
          ignore (expect_ok (Audio.Stream.close stream)));
      test "late data from a cancelled generation is ignored" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
          let engine = expect_ok (Audio.Engine.create ~owner) in
          let closes = ref 0 in
          let disposed = ref 0 in
          let ended = ref 0 in
          let connector =
            Audio.Stream.connector
              ~connect:(fun ~attempt:_ ~cancel:_ ->
                Ok
                  (Audio.Stream.connection ~initial_metadata:None
                     ~next:(fun cancel ->
                       Audio.Stream.Cancellation.await cancel;
                       Ok (Audio.Stream.Data (Bytes.of_string "late")))
                     ~close:(fun () -> incr closes; Ok ())))
          in
          let options = expect_ok (Audio.Options.create ()) in
          let stream =
            expect_ok
              (Audio.Stream.open_~engine ~owner ~connector ~options)
          in
          ignore
            (expect_ok
               (Audio.Stream.on_disposed stream (fun _ -> incr disposed)));
          ignore
            (expect_ok (Audio.Stream.on_ended stream (fun _ -> incr ended)));
          ignore (expect_ok (Audio.Stream.close stream));
          (match expect_ok (Audio.Stream.await_closed stream) with
          | Audio.Stream.Disposed_terminal -> ()
          | Audio.Stream.Ended_terminal -> fail "late data caused a clean end"
          | Audio.Stream.Errored_terminal error ->
              fail (Audio.Error.message error));
          equal int 1 !closes;
          equal int 1 !disposed;
          equal int 0 !ended;
          let stats = expect_ok (Audio.Stream.get_stats stream) in
          equal int 0 stats.bytes_received);
      test "diagnostic callbacks can close during observer failure" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
          let engine = expect_ok (Audio.Engine.create ~owner) in
          let stream_ref = ref None in
          let diagnostics = ref 0 in
          let options =
            expect_ok
              (Audio.Options.create
                 ~on_diagnostic:(fun diagnostic ->
                   match diagnostic with
                   | Audio.Observer_exception _ ->
                       incr diagnostics;
                       (match !stream_ref with
                       | Some stream -> ignore (Audio.Stream.close stream)
                       | None -> ())
                   | Audio.Unobserved_error _ | Audio.Cleanup_error _ -> ())
                 ())
          in
          let connector =
            Audio.Stream.connector
              ~connect:(fun ~attempt:_ ~cancel:_ ->
                Ok
                  (Audio.Stream.connection ~initial_metadata:None
                     ~next:(fun _ -> Ok Audio.Stream.End)
                     ~close:(fun () -> Ok ())))
          in
          let stream =
            expect_ok
              (Audio.Stream.open_~engine ~owner ~connector ~options)
          in
          stream_ref := Some stream;
          ignore
            (expect_ok
               (Audio.Stream.on_ended stream (fun _ -> raise Observer_raised)));
          (match expect_ok (Audio.Stream.await_closed stream) with
          | Audio.Stream.Ended_terminal -> ()
          | Audio.Stream.Disposed_terminal -> fail "observer changed terminal state"
          | Audio.Stream.Errored_terminal error ->
              fail (Audio.Error.message error));
          equal int 1 !diagnostics);
      test "owner switch cancellation closes the active connection" (fun () ->
          let closes = ref 0 in
          Eio_main.run @@ fun env ->
          (try
             Eio.Switch.run @@ fun sw ->
             let mono_clock = Eio.Stdenv.mono_clock env in
             let owner = expect_ok (Audio.Owner.create ~sw ~clock:mono_clock) in
             let engine = expect_ok (Audio.Engine.create ~owner) in
             let connector =
               Audio.Stream.connector
                 ~connect:(fun ~attempt:_ ~cancel:_ ->
                   Ok
                     (Audio.Stream.connection ~initial_metadata:None
                        ~next:(fun _ -> Eio.Fiber.await_cancel ())
                        ~close:(fun () -> incr closes; Ok ())))
             in
             let options = expect_ok (Audio.Options.create ()) in
             let stream =
               expect_ok
                 (Audio.Stream.open_ ~engine ~owner ~connector ~options)
             in
             equal bool true (expect_ok (Audio.Stream.is_exposed stream));
             Eio.Fiber.fork ~sw (fun () ->
                 Eio.Fiber.yield ();
                 Eio.Switch.fail sw Owner_switch_cancelled);
             Eio.Fiber.await_cancel ()
           with
          | Owner_switch_cancelled -> ());
          equal int 1 !closes);
    ]
