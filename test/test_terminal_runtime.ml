open Windtrap

module Events = Opentui_terminal.Event_queue
module Size = Opentui_terminal.Terminal_size
module Wakeup = Opentui_terminal_eio.Wakeup
module Dispatch = Opentui_terminal_eio.Dispatch
module Resize = Opentui_terminal_eio_unix.Resize_source

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
  run "opentui-terminal-runtime"
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
