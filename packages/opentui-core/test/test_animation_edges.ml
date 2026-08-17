open Windtrap

module Animation = Opentui_core.Animation

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Animation.Error.message error)

let expect_update result =
  match result with
  | Ok () -> ()
  | Error fault -> fail (Animation.Error.fault_message fault)

let () =
  run "opentui-core-animation-edges"
    [
      test "paused timelines do not advance" (fun () ->
          let value = ref 0.0 in
          let timeline =
            expect_ok
              (Animation.Timeline.create ~duration_ms:100.0 ~autoplay:false
                 ())
          in
          ignore
            (expect_ok
               (Animation.Timeline.add timeline
                  ~bindings:[ Animation.Property.bind_ref value ~to_:10.0 ]
                  ~duration_ms:100.0 ()));
          expect_update
            (Animation.Timeline.update timeline ~delta_time_ms:50.0);
          equal int 0
            (Int.compare (Float.compare !value 0.0) 0);
          equal int 0
            (Int.compare (Float.compare
               (Animation.Timeline.current_time_ms timeline) 0.0) 0));
      test "looping timelines preserve overshoot" (fun () ->
          let value = ref 0.0 in
          let timeline =
            expect_ok
              (Animation.Timeline.create ~duration_ms:100.0 ~loop:true ())
          in
          ignore
            (expect_ok
               (Animation.Timeline.add timeline
                  ~bindings:[ Animation.Property.bind_ref value ~to_:10.0 ]
                  ~duration_ms:100.0 ()));
          expect_update
            (Animation.Timeline.update timeline ~delta_time_ms:150.0);
          equal int 0
            (Int.compare (Float.compare !value 5.0) 0);
          equal int 0
            (Int.compare (Float.compare
               (Animation.Timeline.current_time_ms timeline) 50.0) 0));
      test "synchronized child starts at its offset" (fun () ->
          let value = ref 0.0 in
          let parent =
            expect_ok
              (Animation.Timeline.create ~duration_ms:200.0 ())
          in
          let child =
            expect_ok
              (Animation.Timeline.create ~duration_ms:100.0 ~autoplay:false
                 ())
          in
          ignore
            (expect_ok
               (Animation.Timeline.add child
                  ~bindings:[ Animation.Property.bind_ref value ~to_:10.0 ]
                  ~duration_ms:100.0 ()));
          ignore
            (expect_ok
               (Animation.Timeline.sync parent child ~start_time_ms:100.0
                  ()));
          expect_update
            (Animation.Timeline.update parent ~delta_time_ms:150.0);
          equal int 0
            (Int.compare (Float.compare !value 5.0) 0);
          equal int 0
            (Int.compare (Float.compare
               (Animation.Timeline.current_time_ms child) 50.0) 0));
      test "parent pause and resume controls a started child" (fun () ->
          let value = ref 0.0 in
          let parent =
            expect_ok
              (Animation.Timeline.create ~duration_ms:200.0 ())
          in
          let child =
            expect_ok
              (Animation.Timeline.create ~duration_ms:100.0 ~autoplay:false
                 ())
          in
          ignore
            (expect_ok
               (Animation.Timeline.add child
                  ~bindings:[ Animation.Property.bind_ref value ~to_:10.0 ]
                  ~duration_ms:100.0 ()));
          ignore (expect_ok (Animation.Timeline.sync parent child ()));
          expect_update
            (Animation.Timeline.update parent ~delta_time_ms:50.0);
          equal int 0 (Int.compare (Float.compare !value 5.0) 0);
          ignore (expect_ok (Animation.Timeline.pause parent));
          expect_update
            (Animation.Timeline.update parent ~delta_time_ms:50.0);
          equal int 0 (Int.compare (Float.compare !value 5.0) 0);
          ignore (expect_ok (Animation.Timeline.play parent));
          expect_update
            (Animation.Timeline.update parent ~delta_time_ms:50.0);
          equal int 0 (Int.compare (Float.compare !value 10.0) 0));
    ]
