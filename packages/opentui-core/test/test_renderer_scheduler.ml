open Windtrap

module Core = Opentui_core
module Clock = Core.Lib.Clock
module Eio_clock = Core.Platform.Eio_runtime.Eio_clock
module Renderable = Core.Renderable
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

let close_clock clock =
  match Eio_clock.close clock with
  | Ok () -> ()
  | Error error -> fail (Eio_clock.message error)

let close_scheduler scheduler =
  match Scheduler.close scheduler with
  | Ok () -> ()
  | Error error -> fail (Scheduler.message error)

let rejects_invalid_argument operation =
  try
    operation ();
    false
  with Invalid_argument message -> not (String.equal message "")

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

let require_multiple_domains () =
  if Int.compare (Domain.recommended_domain_count ()) 2 < 0 then
    skip ~reason:"requires an executor domain for the affinity check" ()

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
          close_clock clock);
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
          close_clock clock);
      test "Eio clock cancellation and close suppress callbacks" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let lib_clock = Eio_clock.lib_clock clock in
          let cancelled_calls = ref 0 in
          let cancelled_timer =
            Clock.schedule lib_clock ~delay:0.02 (fun () ->
                incr cancelled_calls)
          in
          Clock.cancel lib_clock cancelled_timer;
          Clock.cancel lib_clock cancelled_timer;
          Eio.Time.Mono.sleep mono_clock 0.03;
          equal int 0 !cancelled_calls;
          let closed_calls = ref 0 in
          let closed_timer =
            Clock.schedule lib_clock ~delay:0.02 (fun () ->
                incr closed_calls)
          in
          close_clock clock;
          Clock.cancel lib_clock closed_timer;
          Eio.Time.Mono.sleep mono_clock 0.03;
          equal int 0 !closed_calls);
      test "scheduler rejects missing clocks and invalid frame rates" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer = expect_renderer (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          (match Scheduler.create ~sw ~clock ~renderer ~frames_per_second:0 () with
          | Error Scheduler.Invalid_frames_per_second -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok scheduler ->
              close_scheduler scheduler;
              fail "zero frames_per_second was accepted");
          (match Scheduler.create ~sw ~clock ~renderer () with
          | Error Scheduler.Missing_clock -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok scheduler ->
              close_scheduler scheduler;
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
          close_clock clock);
      test "scheduler close preserves clock and theme timing" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l ())
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let before_timer = ref 0 in
          let after_timer = ref 0 in
          let theme_callbacks = ref 0 in
          ignore
            (Clock.schedule (Eio_clock.lib_clock clock) ~delay:0.005 (fun () ->
                 incr before_timer));
          ignore
            (expect_renderer
               (Renderer.wait_for_theme_mode renderer ~timeout_ms:5
                  ~on_result:(fun _ -> incr theme_callbacks)));
          close_scheduler scheduler;
          ignore
            (Clock.schedule (Eio_clock.lib_clock clock) ~delay:0.005 (fun () ->
                 incr after_timer));
          ignore
            (expect_renderer
               (Renderer.wait_for_theme_mode renderer ~timeout_ms:5
                  ~on_result:(fun _ -> incr theme_callbacks)));
          Eio.Time.Mono.sleep mono_clock 0.03;
          equal int 1 !before_timer;
          equal int 1 !after_timer;
          equal int 2 !theme_callbacks;
          destroy_renderer renderer);
      test "scheduler enforces owner domain and switch affinity" (fun () ->
          require_multiple_domains ();
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun owner_sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw:owner_sw ~mono_clock in
          let uncached_clock = Eio_clock.create ~sw:owner_sw ~mono_clock in
          let lib_clock = Eio_clock.lib_clock clock in
          let timer = Clock.schedule lib_clock ~delay:1.0 (fun () -> ()) in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:lib_clock ~width:2l ~height:1l ())
          in
          Eio.Switch.run @@ fun wrong_sw ->
          (match Scheduler.create ~sw:wrong_sw ~clock ~renderer () with
          | Error Scheduler.Switch_mismatch -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok scheduler ->
              close_scheduler scheduler;
              fail "scheduler accepted a switch unrelated to its clock");
          let scheduler = expect_scheduler (Scheduler.create ~sw:owner_sw ~clock ~renderer ()) in
          let ( wrong_run,
                wrong_scheduler_close,
                wrong_clock_close,
                wrong_clock_admission,
                wrong_schedule,
                wrong_cancel,
                wrong_now,
                wrong_portable_now,
                wrong_sleep,
                wrong_cached_access,
                wrong_first_access ) =
            Eio.Domain_manager.run (Eio.Stdenv.domain_mgr env) (fun () ->
                ( Scheduler.run scheduler,
                  Scheduler.close scheduler,
                  Eio_clock.close clock,
                  Eio_clock.check_owner clock,
                  rejects_invalid_argument (fun () ->
                      ignore (Clock.schedule lib_clock ~delay:0.0 (fun () -> ()))),
                  rejects_invalid_argument (fun () -> Clock.cancel lib_clock timer),
                  rejects_invalid_argument (fun () -> ignore (Eio_clock.now clock)),
                  rejects_invalid_argument (fun () -> ignore (Clock.now lib_clock)),
                  rejects_invalid_argument (fun () ->
                      Eio_clock.sleep_until clock ~deadline:0.0),
                  rejects_invalid_argument (fun () ->
                      ignore (Eio_clock.lib_clock clock)),
                  rejects_invalid_argument (fun () ->
                      ignore (Eio_clock.lib_clock uncached_clock)) ))
          in
          (match wrong_run with
          | Error Scheduler.Wrong_domain -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok () -> fail "scheduler ran from a non-owner domain");
          (match wrong_scheduler_close with
          | Error Scheduler.Wrong_domain -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok () -> fail "scheduler closed from a non-owner domain");
          (match wrong_clock_close with
          | Error Eio_clock.Wrong_domain -> ()
          | Error error -> fail (Eio_clock.message error)
          | Ok () -> fail "Eio clock closed from a non-owner domain");
          (match wrong_clock_admission with
          | Error Eio_clock.Wrong_domain -> ()
          | Error error -> fail (Eio_clock.message error)
          | Ok () -> fail "Eio clock admitted a non-owner domain");
          equal bool true wrong_schedule;
          equal bool true wrong_cancel;
          equal bool true wrong_now;
          equal bool true wrong_portable_now;
          equal bool true wrong_sleep;
          equal bool true wrong_cached_access;
          equal bool true wrong_first_access;
          Clock.cancel lib_clock timer;
          close_scheduler scheduler;
          destroy_renderer renderer;
          close_clock clock;
          close_clock uncached_clock);
      test "requests wake an idle scheduler and coalesce" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l ())
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let frames = ref 0 in
          ignore
            (Renderer.on_frame renderer (fun event ->
                 ignore event;
                 incr frames;
                 close_scheduler scheduler));
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_render renderer));
          ignore (expect_renderer (Renderer.request_render renderer));
          expect_scheduler_success result;
          equal int 1 !frames;
          equal bool true (Renderer.is_destroyed renderer |> not);
          close_scheduler scheduler;
          destroy_renderer renderer);
      test "a request queued before the idle wait is not lost" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l ())
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let frames = ref 0 in
          ignore
            (Renderer.on_frame renderer (fun event ->
                 ignore event;
                 incr frames;
                 close_scheduler scheduler));
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
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l ())
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let requested = ref false in
          ignore
            (Renderer.on_frame renderer (fun event ->
                 ignore event;
                 if not !requested then begin
                   requested := true;
                   ignore (Renderer.request_render renderer);
                   close_scheduler scheduler
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
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:4l ~height:2l ())
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
                      close_scheduler scheduler
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
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:2l ~height:1l ())
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
                   close_scheduler scheduler
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
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:2l ~height:1l ())
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let result = start_scheduler ~sw scheduler in
          Eio.Fiber.yield ();
          Renderer.destroy renderer;
          expect_scheduler_success result;
          equal bool true (Renderer.is_destroyed renderer);
          close_scheduler scheduler;
          close_clock clock);
      test "scheduler reports frame errors and recovers at the frame cadence" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:2l ~height:1l ())
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let attempts = ref 0 in
          let attempt_times = ref [] in
          let handler_calls = ref 0 in
          ignore
            (expect_renderer
               (Renderer.on_render_error renderer (fun event ->
                    if not (Option.is_none event.renderable_num) then
                      fail "renderer invented renderable attribution";
                    Error Core.Error.Invalid_argument)));
          ignore
            (expect_renderer
               (Renderer.on_render_error renderer (fun event ->
                    (match event.error with
                    | Core.Error.Unsupported -> ()
                    | _ -> fail "renderer reported the wrong frame error");
                    incr handler_calls;
                    Ok ())));
          let behavior =
            Renderable.Private.make_behavior
              ~render_self:(fun renderable buffer delta_time ->
                ignore renderable;
                ignore buffer;
                ignore delta_time;
                incr attempts;
                attempt_times := Eio_clock.now clock :: !attempt_times;
                if Int.equal !attempts 1 then Error Core.Error.Unsupported
                else begin
                  close_scheduler scheduler;
                  Ok ()
                end)
              ()
          in
          let failing_renderable =
            expect_renderer
              (Renderable.Private.create (Renderer.context renderer) ~behavior ())
          in
          ignore
            (expect_renderer
               (Core.Layout_children.add (Renderer.children renderer)
                  failing_renderable));
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_render renderer));
          expect_scheduler_success result;
          equal int 2 !attempts;
          equal int 1 !handler_calls;
          (match List.rev !attempt_times with
          | first :: second :: _ ->
              equal bool true (Float.compare (second -. first) 0.01 >= 0)
          | _ -> fail "renderer recovery attempted too few frames");
          destroy_renderer renderer);
      test "output failure stops the scheduler without a retry loop" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let sink_calls = ref 0 in
          let sink =
            Renderer.Output.sink ~write_frame:(fun _ ->
                incr sink_calls;
                Error (Core.Error.Io "test output failure"))
          in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock
                 ~output:(Renderer.Output.Sink sink)
                 ~clock:(Eio_clock.lib_clock clock) ~width:2l ~height:1l ())
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          let result = start_scheduler ~sw scheduler in
          ignore (expect_renderer (Renderer.request_render renderer));
          (match Eio.Promise.await result with
           | Error (Scheduler.Render_error (Core.Error.Output _)) -> ()
           | Error error -> fail (Scheduler.message error)
           | Ok () -> fail "output failure did not terminate the scheduler");
          equal int 1 !sink_calls;
          close_scheduler scheduler;
          destroy_renderer renderer;
          close_clock clock);
      test "scheduler attachment and running lifecycle are idempotent" (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let renderer =
            expect_renderer
              (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock clock)
                 ~width:2l ~height:1l ())
          in
          let scheduler = expect_scheduler (Scheduler.create ~sw ~clock ~renderer ()) in
          (match Scheduler.create ~sw ~clock ~renderer () with
          | Error Scheduler.Already_attached -> ()
          | Error error -> fail (Scheduler.message error)
          | Ok second ->
              close_scheduler second;
              fail "a second scheduler attached");
          let already_running = ref None in
          ignore
            (expect_renderer
               (Renderer.add_post_process renderer (fun buffer ~delta_time ->
                    ignore buffer;
                    ignore delta_time;
                    already_running := Some (Scheduler.run scheduler);
                    close_scheduler scheduler;
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
