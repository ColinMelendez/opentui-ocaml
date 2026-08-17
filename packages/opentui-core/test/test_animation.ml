open Windtrap

module Animation = Opentui_core.Animation

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Animation.Error.message error)

let () =
  run "opentui-core-animation"
    [
      test "manual timeline interpolates typed bindings" (fun () ->
          let value = ref 0.0 in
          let timeline =
            expect_ok
              (Animation.Timeline.create ~duration_ms:100.0 ~autoplay:false ())
          in
          ignore
            (expect_ok
               (Animation.Timeline.add timeline
                  ~bindings:[ Animation.Property.bind_ref value ~to_:10.0 ]
                  ~duration_ms:100.0 ()));
          equal int 1 (Animation.Timeline.item_count timeline);
          ignore (expect_ok (Animation.Timeline.play timeline));
          equal bool true (Animation.Timeline.is_playing timeline);
          (match
             Animation.Timeline.update timeline ~delta_time_ms:50.0
           with
          | Ok () -> ()
          | Error fault -> fail (Animation.Error.fault_message fault));
          if not
               (Int.equal
                  (Float.compare (Animation.Timeline.current_time_ms timeline) 50.0)
                  0)
          then
            fail
              (Printf.sprintf "current time after first update: %f"
                 (Animation.Timeline.current_time_ms timeline));
          if not (Int.equal (Float.compare !value 5.0) 0) then
            fail (Printf.sprintf "value after first update: %f" !value);
          (match
             Animation.Timeline.update timeline ~delta_time_ms:50.0
           with
          | Ok () -> ()
          | Error fault -> fail (Animation.Error.fault_message fault));
          equal bool true (Int.equal (Float.compare !value 10.0) 0);
          equal bool true (Animation.Timeline.is_complete timeline));
      test "once items are removed after completion" (fun () ->
          let value = ref 0.0 in
          let timeline = expect_ok (Animation.Timeline.create ()) in
          ignore
            (expect_ok
               (Animation.Timeline.once timeline
                  ~bindings:[ Animation.Property.bind_ref value ~to_:4.0 ]
                  ~duration_ms:10.0 ()));
          ignore
            (match
               Animation.Timeline.update timeline ~delta_time_ms:1000.0
             with
            | Ok () -> ()
            | Error fault -> fail (Animation.Error.fault_message fault));
          equal int 0 (Animation.Timeline.item_count timeline);
          equal bool true (Int.equal (Float.compare !value 4.0) 0));
      test "invalid numeric endpoints are structured errors" (fun () ->
          let timeline = expect_ok (Animation.Timeline.create ()) in
          match
            Animation.Timeline.add timeline
              ~bindings:
                [ Animation.Property.bind_ref (ref 0.0) ~to_:Float.infinity ]
              ()
          with
          | Error (Animation.Error.Invalid_number _) -> ()
          | Error error -> fail (Animation.Error.message error)
          | Ok item ->
              ignore item;
              fail "non-finite binding endpoint was accepted");
    ]
