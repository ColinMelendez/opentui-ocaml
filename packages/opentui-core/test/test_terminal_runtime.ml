open Windtrap

module Events = Opentui_core.Lib.Event_queue
module Size = Opentui_core.Lib.Terminal_size
module Input = Opentui_core.Lib.Stdin_parser
module Decoder = Opentui_core.Lib.Key_decoder
module Wakeup = Opentui_core.Platform.Eio_runtime.Wakeup
module Dispatch = Opentui_core.Platform.Eio_runtime.Dispatch
module Resize = Opentui_core.Platform.Eio_unix_runtime.Resize_source

let expect_size result =
  match result with
  | Ok size -> size
  | Error error -> fail (Size.message error)

let expect_resize result =
  match result with
  | Ok source -> source
  | Error error -> fail (Resize.message error)

let expect_push result =
  match result with
  | Ok () -> ()
  | Error error -> fail (Events.message error)

let () =
  run "opentui-core-runtime"
    [
      test "wakeup preserves notification-before-wait" (fun () ->
          Eio_main.run @@ fun _env ->
          let wakeup = Wakeup.create () in
          let before = Wakeup.revision wakeup in
          Wakeup.notify wakeup;
          let after = Wakeup.wait wakeup ~since:before in
          equal int64 (Int64.add before 1L) after);
      test "dispatch consumes a notified bounded event" (fun () ->
          Eio_main.run @@ fun _env ->
          let queue =
            match Events.create ~capacity:1 () with
            | Ok queue -> queue
            | Error error -> fail (Events.message error)
          in
          let wakeup = Wakeup.create () in
          let size = expect_size (Size.create ~columns:4 ~rows:2) in
          let handled, resolve_handled = Eio.Promise.create () in
          ignore
            (Eio.Fiber.first
               (fun () ->
                 Dispatch.run ~queue ~wakeup ~handle:(function
                   | Events.Resize received ->
                       equal int 4 (Size.columns received);
                       equal int 2 (Size.rows received);
                       Eio.Promise.resolve resolve_handled ()
                   | Events.Input _ -> fail "dispatcher received an input event"))
               (fun () ->
                 expect_push (Wakeup.push wakeup ~queue (Events.Resize size));
                 Eio.Promise.await handled)));
      test "dispatch yields before an input flood can starve owner fibers" (fun () ->
          Eio_main.run @@ fun _env ->
          Eio.Switch.run @@ fun sw ->
          let queue =
            match Events.create ~capacity:128 () with
            | Ok queue -> queue
            | Error error -> fail (Events.message error)
          in
          let wakeup = Wakeup.create () in
          let modifiers = { Decoder.shift = false; meta = false; ctrl = false } in
          let event =
            Events.Input
              (Input.Key
                 {
                   raw = Bytes.empty;
                   key = Decoder.Named Decoder.Tab;
                   modifiers;
                   metadata = Decoder.raw_metadata;
                 })
          in
          for _index = 1 to 128 do
            expect_push (Wakeup.push wakeup ~queue event)
          done;
          let handled = ref 0 in
          let probe_ran = ref false in
          let probe_seen_before_end = ref false in
          let finished, resolve_finished = Eio.Promise.create () in
          let outcome =
            Eio.Fiber.first
              (fun () ->
                Dispatch.run ~queue ~wakeup ~handle:(fun _event ->
                    incr handled;
                    if Int.equal !handled 1 then
                      ignore
                        (Eio.Fiber.fork ~sw (fun () ->
                             Eio.Fiber.yield ();
                             probe_ran := true));
                    if Int.equal !handled 127 then
                      probe_seen_before_end := !probe_ran;
                    if Int.equal !handled 128 then
                      Eio.Promise.resolve resolve_finished ()))
              (fun () -> Eio.Promise.await finished)
          in
          ignore outcome;
          equal int 128 !handled;
          equal bool true !probe_seen_before_end);
      test "resize source wakes and enforces one process owner" (fun () ->
          Eio_main.run @@ fun _env ->
          Eio.Switch.run @@ fun sw ->
          let source = expect_resize (Resize.create ~sw ()) in
          (match Resize.create ~sw () with
          | Error Resize.Already_installed -> ()
          | Error error -> fail (Resize.message error)
          | Ok second ->
              Resize.close second;
              fail "two SIGWINCH sources were installed");
          let waited, resolve_waited = Eio.Promise.create () in
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Promise.resolve resolve_waited (Resize.wait source));
          Eio.Fiber.yield ();
          Unix.kill (Unix.getpid ()) Sys.sigwinch;
          (match Eio.Promise.await waited with
          | Ok () -> ()
          | Error error -> fail (Resize.message error));
          let closed, resolve_closed = Eio.Promise.create () in
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Promise.resolve resolve_closed (Resize.wait source));
          Eio.Fiber.yield ();
          Resize.close source;
          (match Eio.Promise.await closed with
          | Error Resize.Closed -> ()
          | Error error -> fail (Resize.message error)
          | Ok () -> fail "closing the resize source did not wake its waiter");
          let replacement = expect_resize (Resize.create ~sw ()) in
          Resize.close replacement;
          let previous_handler =
            Sys.signal Sys.sigwinch
              (Sys.Signal_handle (fun _ -> ()))
          in
          Fun.protect
            (fun () ->
              match Resize.create ~sw () with
              | Error Resize.Existing_handler -> ()
              | Error error -> fail (Resize.message error)
              | Ok installed ->
                  Resize.close installed;
                  fail "a custom SIGWINCH handler was replaced")
            ~finally:(fun () -> Sys.set_signal Sys.sigwinch previous_handler))
    ]
