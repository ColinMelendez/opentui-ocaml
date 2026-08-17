open Windtrap

module Core = Opentui_core
module Clock = Core.Lib.Clock
module Eio_clock = Core.Platform.Eio_runtime.Eio_clock
module Renderer = Core.Renderer
module Scheduler = Core.Platform.Eio_runtime.Renderer_scheduler

let expect_renderer result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_scheduler result =
  match result with
  | Ok value -> value
  | Error error -> fail (Scheduler.message error)

let destroy_renderer renderer =
  if not (Renderer.is_destroyed renderer) then Renderer.destroy renderer

let start_scheduler ~sw scheduler =
  let result, resolve_result = Eio.Promise.create () in
  Eio.Fiber.fork ~sw (fun () ->
      let outcome = Scheduler.run scheduler in
      Eio.Promise.resolve resolve_result outcome);
  Eio.Fiber.yield ();
  result

let expect_scheduler_success result =
  match Eio.Promise.await result with
  | Ok () -> ()
  | Error error -> fail (Scheduler.message error)

let () =
  run "opentui-core-renderer-scheduler"
    [
      test "Eio clock reports relative monotonic time" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let first = Eio_clock.now clock in
          Eio.Time.Mono.sleep mono_clock 0.002;
          let second = Eio_clock.now clock in
          equal bool true (Float.compare first 0.0 >= 0);
          equal bool true (Float.compare second first >= 0);
          Eio_clock.close clock);
      test "Eio clock timers fire once and tolerate post-fire cancellation" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let fired, resolve_fired = Eio.Promise.create () in
          let calls = ref 0 in
          let timer =
            Clock.schedule (Eio_clock.lib_clock clock) ~delay:0.005 (fun () ->
                incr calls;
                Eio.Promise.resolve resolve_fired ())
          in
          Eio.Promise.await fired;
          Clock.cancel (Eio_clock.lib_clock clock) timer;
          equal int 1 !calls;
          Eio_clock.close clock);
      test "Eio clock cancellation and close suppress callbacks" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let cancelled_calls = ref 0 in
          let cancelled_timer =
            Clock.schedule (Eio_clock.lib_clock clock) ~delay:0.02 (fun () ->
                incr cancelled_calls)
          in
          Clock.cancel (Eio_clock.lib_clock clock) cancelled_timer;
          Clock.cancel (Eio_clock.lib_clock clock) cancelled_timer;
          Eio.Time.Mono.sleep mono_clock 0.03;
          equal int 0 !cancelled_calls;
          let closed_calls = ref 0 in
          let closed_timer =
            Clock.schedule (Eio_clock.lib_clock clock) ~delay:0.02 (fun () ->
                incr closed_calls)
          in
          Eio_clock.close clock;
          Clock.cancel (Eio_clock.lib_clock clock) closed_timer;
          Eio.Time.Mono.sleep mono_clock 0.03;
          equal int 0 !closed_calls);
      test "scheduler rejects missing clocks and invalid frame rates" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer = expect_renderer (Renderer.create ~width:2l ~height:1l) in
          (match Scheduler.create ~sw ~clock ~renderer ~frames_per_second:0 () with
          | Error Scheduler.Invalid_frames_per_second -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok scheduler ->
              Scheduler.close scheduler;
              fail "zero frames_per_second was accepted");
          (match Scheduler.create ~sw ~clock ~renderer () with
          | Error Scheduler.Missing_clock -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok scheduler ->
              Scheduler.close scheduler;
              fail "a clockless renderer was schedulable");
          (match Renderer.wait_for_theme_mode renderer ~timeout_ms:1 ~on_result:ignore with
          | Error Core.Error.Unsupported -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok value ->
              ignore value;
              fail "a clockless theme waiter accepted a positive timeout");
          let direct_theme =
            let queries = ref 0 in
            let theme =
              Core.Renderer_theme_mode.create_without_clock
                ~query:(fun () -> incr queries) ()
            in
            Core.Renderer_theme_mode.request theme;
            Core.Renderer_theme_mode.request theme;
            equal int 1 !queries;
            theme
          in
          let direct_result = ref None in
          let direct_waiter =
            Core.Renderer_theme_mode.wait_for direct_theme ~timeout_ms:1
              ~on_result:(fun mode -> direct_result := Some mode)
          in
          (match !direct_result with
          | Some None -> ()
          | Some (Some mode) ->
              ignore mode;
              fail "clockless direct theme wait reported a mode"
          | None -> fail "clockless direct theme wait did not complete immediately");
          Core.Renderer_theme_mode.cancel_wait direct_theme direct_waiter;
          destroy_renderer renderer;
          Eio_clock.close clock);
      test "requests wake an idle scheduler and coalesce" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l)
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let frames = ref 0 in
          ignore
            (Renderer.on_frame renderer (fun event ->
                 ignore event;
                 incr frames;
                 Scheduler.close scheduler));
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_render renderer));
          ignore (expect_renderer (Renderer.request_render renderer));
          expect_scheduler_success result;
          equal int 1 !frames;
          equal bool true (Renderer.is_destroyed renderer |> not);
          Scheduler.close scheduler;
          destroy_renderer renderer);
      test "a request queued before the idle wait is not lost" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l)
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let frames = ref 0 in
          ignore
            (Renderer.on_frame renderer (fun event ->
                 ignore event;
                 incr frames;
                 Scheduler.close scheduler));
          ignore (expect_renderer (Renderer.request_render renderer));
          let result = start_scheduler ~sw scheduler in
          expect_scheduler_success result;
          equal int 1 !frames;
          destroy_renderer renderer);
      test "a request made during a frame remains pending" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l)
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let requested = ref false in
          ignore
            (Renderer.on_frame renderer (fun event ->
                 ignore event;
                 if not !requested then begin
                   requested := true;
                   ignore (Renderer.request_render renderer);
                   Scheduler.close scheduler
                 end));
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_render renderer));
          expect_scheduler_success result;
          equal bool true !requested;
          equal bool true (expect_renderer (Renderer.has_pending_render renderer));
          destroy_renderer renderer);
      test "live ownership drives paced frames and stops after drop" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l)
          in
          let scheduler =
            expect_scheduler
              (Scheduler.create ~sw ~clock ~renderer ~frames_per_second:100 ())
          in
          let frame_times = ref [] in
          let deltas = ref [] in
          ignore
            (expect_renderer
               (Renderer.add_post_process renderer (fun buffer ~delta_time ->
                    ignore buffer;
                    frame_times := Eio_clock.now clock :: !frame_times;
                    deltas := delta_time :: !deltas;
                    if Int.equal (List.length !deltas) 3 then begin
                      ignore (Renderer.drop_live renderer);
                      Scheduler.close scheduler
                    end;
                    Eio.Time.Mono.sleep mono_clock 0.03;
                    Ok ())));
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_live renderer));
          expect_scheduler_success result;
          equal int 3 (List.length !deltas);
          (match List.rev !deltas with
          | first :: rest ->
              equal (float 0.0001) 0.0 first;
              List.iter
                (fun delta -> equal bool true (Float.compare delta 0.0 >= 0))
                rest
          | [] -> fail "live rendering produced no deltas");
          (match List.rev !frame_times with
          | first :: second :: _ ->
              equal bool true (Float.compare (second -. first) 0.02 >= 0)
          | _ -> fail "live rendering produced too few frame timestamps");
          equal int 0 (expect_renderer (Renderer.live_request_count renderer));
          destroy_renderer renderer);
      test "extreme positive frame rates do not create deadline catch-up loops" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~clock:(Eio_clock.lib_clock clock)
                 ~width:2l ~height:1l)
          in
          let scheduler =
            expect_scheduler
              (Scheduler.create ~sw ~clock ~renderer
                 ~frames_per_second:Int.max_int ())
          in
          let frames = ref 0 in
          ignore
            (Renderer.on_frame renderer (fun event ->
                 ignore event;
                 incr frames;
                 if Int.equal !frames 2 then begin
                   ignore (Renderer.drop_live renderer);
                   Scheduler.close scheduler
                 end));
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_live renderer));
          expect_scheduler_success result;
          equal int 2 !frames;
          destroy_renderer renderer);
      test "renderer destruction tears down an idle scheduler" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~clock:(Eio_clock.lib_clock clock)
                 ~width:2l ~height:1l)
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let result = start_scheduler ~sw scheduler in
          Eio.Fiber.yield ();
          Renderer.destroy renderer;
          expect_scheduler_success result;
          equal bool true (Renderer.is_destroyed renderer);
          Scheduler.close scheduler;
          Eio_clock.close clock);
      test "scheduler propagates renderer frame errors" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~clock:(Eio_clock.lib_clock clock)
                 ~width:2l ~height:1l)
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          ignore
            (expect_renderer
               (Renderer.add_post_process renderer (fun buffer ~delta_time ->
                    ignore buffer;
                    ignore delta_time;
                    Error Core.Error.Unsupported)));
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_render renderer));
          (match Eio.Promise.await result with
          | Error (Scheduler.Render_error Core.Error.Unsupported) -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok () -> fail "a renderer frame error was swallowed");
          destroy_renderer renderer);
      test "scheduler attachment and running lifecycle are idempotent" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~clock:(Eio_clock.lib_clock clock)
                 ~width:2l ~height:1l)
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          (match Scheduler.create ~sw ~clock ~renderer () with
          | Error Scheduler.Already_attached -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok second ->
              Scheduler.close second;
              fail "a second scheduler attached");
          let already_running = ref None in
          ignore
            (expect_renderer
               (Renderer.add_post_process renderer (fun buffer ~delta_time ->
                    ignore buffer;
                    ignore delta_time;
                    already_running := Some (Scheduler.run scheduler);
                    Scheduler.close scheduler;
                    Ok ())));
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_render renderer));
          expect_scheduler_success result;
          (match !already_running with
          | Some (Error Scheduler.Already_running) -> ()
          | Some (Error error) -> fail (Scheduler.message error)
          | Some (Ok ()) -> fail "reentrant scheduler run was accepted"
          | None -> fail "reentrant scheduler run was not attempted");
          equal bool true
            (match Scheduler.run scheduler with
            | Ok () -> true
            | Error error ->
                ignore error;
                false);
          destroy_renderer renderer);
    ]
