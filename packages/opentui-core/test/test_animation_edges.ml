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

let expect_busy_fault result =
  match result with
  | Error fault ->
      (match fault.Animation.Error.cause with
      | Animation.Error.Structured Animation.Error.Busy -> ()
      | _ -> fail "re-entrant update did not return Busy")
  | Ok () -> fail "re-entrant update was accepted"

let test_callback_mutations_stage_and_survive_fault () =
  let timeline_ref = ref None in
  let child =
    expect_ok
      (Animation.Timeline.create ~duration_ms:100.0 ~autoplay:false ())
  in
  let staged_value = ref 0.0 in
  let staged_calls = ref 0 in
  let stage_once = ref true in
  let fault_once = ref true in
  let stage_mutations _update =
    if !stage_once then begin
      stage_once := false;
      match !timeline_ref with
      | None -> fail "timeline callback ran before its timeline was assigned"
      | Some timeline ->
          ignore
            (expect_ok
               (Animation.Timeline.add timeline ~bindings:[] ~duration_ms:100.0
                  ()));
          ignore
            (expect_ok
               (Animation.Timeline.once timeline
                  ~bindings:[ Animation.Property.bind_ref staged_value ~to_:10.0 ]
                  ~duration_ms:100.0 ()));
          ignore
            (expect_ok
               (Animation.Timeline.call timeline (fun () -> incr staged_calls)));
          ignore (expect_ok (Animation.Timeline.sync timeline child ()));
          expect_busy_fault
            (Animation.Timeline.update timeline ~delta_time_ms:1.0);
          (match Animation.Timeline.restart timeline with
          | Error Animation.Error.Busy -> ()
          | Error error -> fail (Animation.Error.message error)
          | Ok () -> fail "re-entrant restart was accepted")
    end
  in
  let fault_later _update =
    if !fault_once then begin
      fault_once := false;
      raise (Failure "later animation callback")
    end
  in
  let timeline = expect_ok (Animation.Timeline.create ~duration_ms:100.0 ()) in
  timeline_ref := Some timeline;
  ignore
    (expect_ok
       (Animation.Timeline.add timeline ~bindings:[] ~duration_ms:100.0
          ~on_update:stage_mutations ()));
  ignore
    (expect_ok
       (Animation.Timeline.add timeline ~bindings:[] ~duration_ms:100.0
          ~on_update:fault_later ()));
  (match Animation.Timeline.update timeline ~delta_time_ms:10.0 with
  | Error _ -> ()
  | Ok () -> fail "later callback fault was not returned");
  equal int 5 (Animation.Timeline.item_count timeline);
  equal int 1
    (List.length (Animation.Timeline.Private.subtree timeline));
  equal int 0 (Int.compare (Float.compare !staged_value 0.0) 0);
  equal int 0 !staged_calls;
  (match Animation.Timeline.state timeline with
  | Animation.Timeline.Faulted -> ()
  | Animation.Timeline.Idle | Animation.Timeline.Playing
  | Animation.Timeline.Paused | Animation.Timeline.Completed ->
      fail "callback fault did not fault the timeline");
  (match Animation.Timeline.restart timeline with
  | Ok () -> ()
  | Error error -> fail (Animation.Error.message error));
  expect_update (Animation.Timeline.update timeline ~delta_time_ms:100.0);
  equal int 1 !staged_calls;
  equal int 0 (Int.compare (Float.compare !staged_value 10.0) 0)

let test_callback_mutations_run_on_the_next_update () =
  let timeline_ref = ref None in
  let first_update = ref true in
  let staged_calls = ref 0 in
  let child =
    expect_ok
      (Animation.Timeline.create ~duration_ms:100.0 ~autoplay:false ())
  in
  let stage _update =
    if !first_update then begin
      first_update := false;
      match !timeline_ref with
      | None -> fail "timeline callback ran before its timeline was assigned"
      | Some timeline ->
          ignore
            (expect_ok
               (Animation.Timeline.add timeline ~bindings:[]
                  ~duration_ms:100.0 ()));
          ignore
            (expect_ok
               (Animation.Timeline.once timeline ~bindings:[]
                  ~duration_ms:0.0 ()));
          ignore
            (expect_ok
               (Animation.Timeline.call timeline (fun () -> incr staged_calls)));
          ignore (expect_ok (Animation.Timeline.sync timeline child ()))
    end
  in
  let timeline = expect_ok (Animation.Timeline.create ~duration_ms:100.0 ()) in
  timeline_ref := Some timeline;
  ignore
    (expect_ok
       (Animation.Timeline.add timeline ~bindings:[] ~duration_ms:100.0
          ~on_update:stage ()));
  expect_update (Animation.Timeline.update timeline ~delta_time_ms:10.0);
  equal int 4 (Animation.Timeline.item_count timeline);
  equal int 0 !staged_calls;
  expect_update (Animation.Timeline.update timeline ~delta_time_ms:10.0);
  equal int 1 !staged_calls;
  equal int 2 (Animation.Timeline.item_count timeline)

let test_negative_delta_rewinds_direct_and_synchronized_timelines () =
  let direct_value = ref 0.0 in
  let direct = expect_ok (Animation.Timeline.create ~duration_ms:100.0 ()) in
  ignore
    (expect_ok
       (Animation.Timeline.add direct
          ~bindings:[ Animation.Property.bind_ref direct_value ~to_:10.0 ]
          ~duration_ms:100.0 ()));
  expect_update (Animation.Timeline.update direct ~delta_time_ms:50.0);
  expect_update (Animation.Timeline.update direct ~delta_time_ms:(-20.0));
  equal int 0
    (Int.compare
       (Float.compare (Animation.Timeline.current_time_ms direct) 30.0)
       0);
  equal int 0 (Int.compare (Float.compare !direct_value 3.0) 0);
  let child_value = ref 0.0 in
  let child_delta = ref 0.0 in
  let child = expect_ok (Animation.Timeline.create ~duration_ms:100.0 ()) in
  ignore
    (expect_ok
       (Animation.Timeline.add child
          ~bindings:[ Animation.Property.bind_ref child_value ~to_:10.0 ]
          ~duration_ms:100.0
          ~on_update:(fun update -> child_delta := update.delta_time_ms) ()));
  let parent = expect_ok (Animation.Timeline.create ~duration_ms:100.0 ()) in
  ignore (expect_ok (Animation.Timeline.sync parent child ()));
  expect_update (Animation.Timeline.update parent ~delta_time_ms:50.0);
  expect_update (Animation.Timeline.update parent ~delta_time_ms:(-20.0));
  equal int 0
    (Int.compare
       (Float.compare (Animation.Timeline.current_time_ms parent) 30.0)
       0);
  equal int 0
    (Int.compare
       (Float.compare (Animation.Timeline.current_time_ms child) 30.0)
       0);
  equal int 0 (Int.compare (Float.compare !child_value 3.0) 0);
  equal int 0 (Int.compare (Float.compare !child_delta (-20.0)) 0)

let () =
  run "opentui-core-animation-edges"
    [
      test "callback mutations stage and survive a later fault"
        test_callback_mutations_stage_and_survive_fault;
      test "callback mutations commit for the next update"
        test_callback_mutations_run_on_the_next_update;
      test "negative deltas rewind direct and synchronized timelines"
        test_negative_delta_rewinds_direct_and_synchronized_timelines;
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
