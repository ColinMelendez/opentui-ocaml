open Windtrap

module Animation = Opentui_core.Animation

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Animation.Error.message error)

let expect_update result =
  match result with
  | Ok [] -> ()
  | Ok _ -> fail "animation engine returned an unexpected timeline fault"
  | Error error -> fail (Animation.Error.message error)

let expect_timeline_update result =
  match result with
  | Ok () -> ()
  | Error fault -> fail (Animation.Error.fault_message fault)

let expect_renderer result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_core.Error.message error)

let () =
  run "opentui-core-animation-engine"
    [
      test "manual engine owns and releases timeline registration" (fun () ->
          let value = ref 0.0 in
          let timeline = expect_ok (Animation.Timeline.create ~duration_ms:100.0 ()) in
          ignore
            (expect_ok
               (Animation.Timeline.add timeline
                  ~bindings:[ Animation.Property.bind_ref value ~to_:10.0 ]
                  ~duration_ms:100.0 ()));
          let engine = Animation.Engine.create () in
          let registration = expect_ok (Animation.Engine.register engine timeline) in
          expect_update (Animation.Engine.update engine ~delta_time_ms:50.0);
          equal int 0 (Int.compare (Float.compare !value 5.0) 0);
          Animation.Engine.release registration;
          expect_timeline_update
            (Animation.Timeline.update timeline ~delta_time_ms:50.0);
          equal int 0 (Int.compare (Float.compare !value 10.0) 0);
          Animation.Engine.destroy engine);
      test "renderer attachment advances before retained rendering" (fun () ->
          let renderer =
            match Opentui_core.Renderer.create ~output:Opentui_core.Renderer.Output.Memory ~width:2l ~height:1l () with
            | Ok value -> value
            | Error error -> fail (Opentui_core.Error.message error)
          in
          let value = ref 0.0 in
          let timeline = expect_ok (Animation.Timeline.create ~duration_ms:100.0 ()) in
          ignore
            (expect_ok
               (Animation.Timeline.add timeline
                  ~bindings:[ Animation.Property.bind_ref value ~to_:10.0 ]
                  ~duration_ms:100.0 ()));
          let engine = Animation.Engine.create () in
          ignore (expect_ok (Animation.Engine.register engine timeline));
          ignore (expect_ok (Animation.Engine.attach engine ~renderer));
          (match
             Opentui_core.Renderer.render ~delta_time:0.05 renderer ~force:true
           with
          | Ok _ -> ()
          | Error error -> fail (Opentui_core.Error.message error));
          equal int 0 (Int.compare (Float.compare !value 5.0) 0);
          equal int 0
            (Int.compare
               (expect_renderer (Opentui_core.Renderer.live_request_count renderer))
               1);
          (match
             Opentui_core.Renderer.render ~delta_time:0.05 renderer ~force:true
           with
          | Ok _ -> ()
          | Error error -> fail (Opentui_core.Error.message error));
          equal int 0 (Int.compare (Float.compare !value 10.0) 0);
          equal int 0
            (Int.compare
               (expect_renderer (Opentui_core.Renderer.live_request_count renderer))
               0);
          Opentui_core.Renderer.destroy renderer);
      test "run_once waits for the registered root, not a child" (fun () ->
          let parent =
            expect_ok
              (Animation.Timeline.create ~duration_ms:100.0 ~autoplay:false
                 ())
          in
          let child =
            expect_ok
              (Animation.Timeline.create ~duration_ms:50.0 ~autoplay:false
                 ())
          in
          ignore
            (expect_ok
               (Animation.Timeline.add child ~bindings:[] ~duration_ms:50.0
                  ()));
          ignore (expect_ok (Animation.Timeline.sync parent child ()));
          let engine = Animation.Engine.create () in
          ignore (expect_ok (Animation.Engine.run_once engine parent));
          expect_update (Animation.Engine.update engine ~delta_time_ms:100.0);
          ignore (expect_ok (Animation.Timeline.play parent));
          Animation.Engine.destroy engine);
    ]
