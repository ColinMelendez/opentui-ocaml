open Windtrap

external emit_event_for_test : unit -> bool =
  "opentui_raw_test_event_sink_emit"

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_raw.Error.message error)

let same_error left right =
  match left, right with
  | Opentui_raw.Error.Invalid_argument, Opentui_raw.Error.Invalid_argument -> true
  | Opentui_raw.Error.Closed, Opentui_raw.Error.Closed -> true
  | Opentui_raw.Error.Stale_handle, Opentui_raw.Error.Stale_handle -> true
  | Opentui_raw.Error.Native_failure, Opentui_raw.Error.Native_failure -> true
  | Opentui_raw.Error.Output_too_small, Opentui_raw.Error.Output_too_small -> true
  | Opentui_raw.Error.Queue_overflow, Opentui_raw.Error.Queue_overflow -> true
  | Opentui_raw.Error.No_space, Opentui_raw.Error.No_space -> true
  | Opentui_raw.Error.Max_bytes, Opentui_raw.Error.Max_bytes -> true
  | Opentui_raw.Error.Busy, Opentui_raw.Error.Busy -> true
  | _ -> false

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual -> equal bool true (same_error actual expected)

let expect_layout ~left ~top ~right ~bottom ~width ~height actual =
  equal (float 0.0001) left actual.Opentui_raw.Yoga.left;
  equal (float 0.0001) top actual.Opentui_raw.Yoga.top;
  equal (float 0.0001) right actual.Opentui_raw.Yoga.right;
  equal (float 0.0001) bottom actual.Opentui_raw.Yoga.bottom;
  equal (float 0.0001) width actual.Opentui_raw.Yoga.width;
  equal (float 0.0001) height actual.Opentui_raw.Yoga.height

let () =
  run "opentui-raw"
    [
      test "renderer and buffers preserve ownership through native calls" (fun () ->
          let renderer = expect_ok (Opentui_raw.Renderer.create ~width:2l ~height:1l) in
          let current = expect_ok (Opentui_raw.Renderer.current_buffer renderer) in
          let next = expect_ok (Opentui_raw.Renderer.next_buffer renderer) in
          let white = Opentui_raw.Color.white in
          let black = Opentui_raw.Color.black in
          ignore (expect_ok (Opentui_raw.Buffer.clear current ~background:black));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.set_cell current ~x:0l ~y:0l ~character:65l
                  ~foreground:white ~background:black ~attributes:0l));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.draw_text next ~text:"B" ~x:1l ~y:0l
                  ~foreground:white ~background:black ~attributes:0l));
          let output = Bytes.create 2 in
          let written =
            expect_ok
              (Opentui_raw.Buffer.write_resolved_chars current ~output
                 ~add_line_breaks:false)
          in
          equal int32 2l written;
          equal string "A " (Bytes.to_string output);
          Opentui_raw.Renderer.close renderer;
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Buffer.width current);
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Buffer.height next));
      test "invalid dimensions and colors are structured errors" (fun () ->
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Renderer.create ~width:0l ~height:1l);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Color.rgba ~red:256 ~green:0 ~blue:0 ~alpha:255));
      test "renderer resize preserves borrowed buffer handles" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:2l ~height:1l)
          in
          let current = expect_ok (Opentui_raw.Renderer.current_buffer renderer) in
          let next = expect_ok (Opentui_raw.Renderer.next_buffer renderer) in
          ignore
            (expect_ok
               (Opentui_raw.Renderer.resize renderer ~width:3l ~height:2l));
          equal int32 3l (expect_ok (Opentui_raw.Buffer.width current));
          equal int32 2l (expect_ok (Opentui_raw.Buffer.height current));
          equal int32 3l (expect_ok (Opentui_raw.Buffer.width next));
          equal int32 2l (expect_ok (Opentui_raw.Buffer.height next));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Renderer.resize renderer ~width:0l ~height:2l);
          equal int32 3l (expect_ok (Opentui_raw.Buffer.width current));
          Opentui_raw.Renderer.close renderer);
      test "small output is reported without raising" (fun () ->
          let renderer = expect_ok (Opentui_raw.Renderer.create ~width:1l ~height:1l) in
          let buffer = expect_ok (Opentui_raw.Renderer.current_buffer renderer) in
          let output = Bytes.create 0 in
          expect_error Opentui_raw.Error.Output_too_small
            (Opentui_raw.Buffer.write_resolved_chars buffer ~output
               ~add_line_breaks:false);
          Opentui_raw.Renderer.close renderer);
      test "renderer exposes typed frame status" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:1l ~height:1l)
          in
          let buffer = expect_ok (Opentui_raw.Renderer.next_buffer renderer) in
          ignore
            (expect_ok
               (Opentui_raw.Buffer.set_cell buffer ~x:0l ~y:0l ~character:65l
                  ~foreground:Opentui_raw.Color.white
                  ~background:Opentui_raw.Color.black ~attributes:0l));
          (match Opentui_raw.Renderer.render renderer ~force:true with
          | Ok Opentui_raw.Renderer.Rendered -> ()
          | Ok Opentui_raw.Renderer.Skipped -> fail "expected a rendered frame"
          | Ok Opentui_raw.Renderer.Failed -> fail "native frame render failed"
          | Error error -> fail (Opentui_raw.Error.message error));
          Opentui_raw.Renderer.close renderer;
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Renderer.render renderer ~force:true));
      test "event delivery is polled from an owned copy" (fun () ->
          let sink = expect_ok (Opentui_raw.Event_sink.create ()) in
          equal bool true (emit_event_for_test ());
          let first =
            match Opentui_raw.Event_sink.poll sink with
            | Ok (Some event) -> event
            | Ok None -> fail "event queue was empty"
            | Error error -> fail (Opentui_raw.Error.message error)
          in
          let second =
            match Opentui_raw.Event_sink.poll sink with
            | Ok (Some event) -> event
            | Ok None -> fail "event queue ended early"
            | Error error -> fail (Opentui_raw.Error.message error)
          in
          equal string "eb_cursor-changed"
            (Bytes.to_string (Opentui_raw.Event.name first));
          equal string "eb_content-changed"
            (Bytes.to_string (Opentui_raw.Event.name second));
          equal int 2 (Bytes.length (Opentui_raw.Event.data first));
          equal int 2 (Bytes.length (Opentui_raw.Event.data second));
          Opentui_raw.Event_sink.close sink;
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Event_sink.poll sink));
      test "event overflow preserves accepted packets before reporting loss" (fun () ->
          let sink = expect_ok (Opentui_raw.Event_sink.create ()) in
          for _ = 1 to 33 do
            equal bool true (emit_event_for_test ())
          done;
          for _ = 1 to 64 do
            match Opentui_raw.Event_sink.poll sink with
            | Ok (Some _) -> ()
            | Ok None -> fail "event queue dropped an accepted packet"
            | Error error -> fail (Opentui_raw.Error.message error)
          done;
          expect_error Opentui_raw.Error.Queue_overflow
            (Opentui_raw.Event_sink.poll sink);
          (match Opentui_raw.Event_sink.poll sink with
          | Ok None -> ()
          | Ok (Some _) -> fail "overflow remained sticky after reporting"
          | Error error -> fail (Opentui_raw.Error.message error));
          Opentui_raw.Event_sink.close sink);
      test "Yoga nodes calculate, detach, and free independently" (fun () ->
          let root = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let child = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.set_width_point child 10.0));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.set_height_point child 5.0));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.set_padding_point root
                  ~edge:Opentui_raw.Yoga.Left ~value:1.0));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:root ~child
                  ~index:0l));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.free child);
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.calculate_layout root ~width:100.0
                  ~height:40.0 ~direction:Opentui_raw.Yoga.Ltr));
          let root_layout =
            expect_ok (Opentui_raw.Yoga.Node.layout root)
          in
          expect_layout ~left:0.0 ~top:0.0 ~right:0.0 ~bottom:0.0 ~width:100.0
            ~height:40.0 root_layout;
          let child_layout =
            expect_ok (Opentui_raw.Yoga.Node.layout child)
          in
          expect_layout ~left:1.0 ~top:0.0 ~right:0.0 ~bottom:0.0 ~width:10.0
            ~height:5.0 child_layout;
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.remove_child ~parent:root ~child));
          ignore (expect_ok (Opentui_raw.Yoga.Node.layout child));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free child));
          expect_error Opentui_raw.Error.Stale_handle
            (Opentui_raw.Yoga.Node.layout child);
          ignore (expect_ok (Opentui_raw.Yoga.Node.free root)));
      test "Yoga moves children without freeing their native nodes" (fun () ->
          let root = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let first = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let second = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.set_height_point first 1.0));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.set_height_point second 2.0));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:root ~child:first
                  ~index:0l));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:root ~child:second
                  ~index:1l));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.calculate_layout root ~width:10.0
                  ~height:10.0 ~direction:Opentui_raw.Yoga.Ltr));
          equal (float 0.0001) 0.0
            (expect_ok (Opentui_raw.Yoga.Node.layout first)).Opentui_raw.Yoga.top;
          equal (float 0.0001) 1.0
            (expect_ok (Opentui_raw.Yoga.Node.layout second)).Opentui_raw.Yoga.top;
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.move_child ~parent:root ~child:second
               ~index:2l);
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.move_child ~parent:root ~child:second
                  ~index:0l));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.calculate_layout root ~width:10.0
                  ~height:10.0 ~direction:Opentui_raw.Yoga.Ltr));
          equal (float 0.0001) 2.0
            (expect_ok (Opentui_raw.Yoga.Node.layout first)).Opentui_raw.Yoga.top;
          equal (float 0.0001) 0.0
            (expect_ok (Opentui_raw.Yoga.Node.layout second)).Opentui_raw.Yoga.top;
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.remove_child ~parent:root ~child:first));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.remove_child ~parent:root ~child:second));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free first));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free second));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free root)));
      test "Yoga rejects cycles and enforces explicit subtree ownership" (fun () ->
          let parent = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let child = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent ~child ~index:0l));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.insert_child ~parent:child ~child:parent
               ~index:0l);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.free child);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.free_recursive child);
          ignore (expect_ok (Opentui_raw.Yoga.Node.free_recursive parent));
          expect_error Opentui_raw.Error.Stale_handle
            (Opentui_raw.Yoga.Node.layout child);
          let left = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let right = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let shared = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:left ~child:shared
                  ~index:0l));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.remove_child ~parent:right ~child:shared);
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.remove_child ~parent:left ~child:shared));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free shared));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free left));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free right));
          let owner = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let detached_parent = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let detached_child = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:owner
                  ~child:detached_parent ~index:0l));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:detached_parent
                  ~child:detached_child ~index:0l));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.remove_child ~parent:owner
                  ~child:detached_parent));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.free detached_parent);
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.free_recursive detached_parent));
          expect_error Opentui_raw.Error.Stale_handle
            (Opentui_raw.Yoga.Node.layout detached_child);
          ignore (expect_ok (Opentui_raw.Yoga.Node.free owner)));
      test "Yoga style groups change computed layout" (fun () ->
          let root = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let first = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let second = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let set result = ignore (expect_ok result) in
          set (Opentui_raw.Yoga.Node.set_width_point root 10.0);
          set (Opentui_raw.Yoga.Node.set_height_point root 4.0);
          set
            (Opentui_raw.Yoga.Node.set_display root
               Opentui_raw.Yoga.Display_flex);
          set
            (Opentui_raw.Yoga.Node.set_flex_direction root
               Opentui_raw.Yoga.Flex_row);
          set
            (Opentui_raw.Yoga.Node.set_gap root
               ~gutter:Opentui_raw.Yoga.Gutter_all
               (Opentui_raw.Yoga.Point 1.0));
          set
            (Opentui_raw.Yoga.Node.set_border root
               ~edge:Opentui_raw.Yoga.All ~value:(Some 1.0));
          set (Opentui_raw.Yoga.Node.set_width_point first 2.0);
          set (Opentui_raw.Yoga.Node.set_height_point first 1.0);
          set (Opentui_raw.Yoga.Node.set_height_point second 1.0);
          set (Opentui_raw.Yoga.Node.set_flex_grow second (Some 1.0));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:root ~child:first
                  ~index:0l));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:root ~child:second
                  ~index:1l));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.calculate_layout root ~width:10.0
                  ~height:4.0 ~direction:Opentui_raw.Yoga.Ltr));
          let first_layout = expect_ok (Opentui_raw.Yoga.Node.layout first) in
          let second_layout = expect_ok (Opentui_raw.Yoga.Node.layout second) in
          equal (float 0.0001) 1.0 first_layout.Opentui_raw.Yoga.left;
          equal (float 0.0001) 2.0 first_layout.Opentui_raw.Yoga.width;
          equal (float 0.0001) 4.0 second_layout.Opentui_raw.Yoga.left;
          equal (float 0.0001) 5.0 second_layout.Opentui_raw.Yoga.width;
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.remove_child ~parent:root ~child:first));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.remove_child ~parent:root ~child:second));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free first));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free second));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free root)));
      test "Yoga style calls reject invalid input and support reference groups"
        (fun () ->
          let node = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.set_width_point node Float.nan);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.set_height_point node Float.infinity);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.set_padding node
               ~edge:Opentui_raw.Yoga.Left Opentui_raw.Yoga.Auto);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.set_min_width node Opentui_raw.Yoga.Auto);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.set_gap node
               ~gutter:Opentui_raw.Yoga.Gutter_all Opentui_raw.Yoga.Auto);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.set_padding_point node
               ~edge:Opentui_raw.Yoga.Left ~value:Float.infinity);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.calculate_layout node ~width:(-1.0)
               ~height:1.0 ~direction:Opentui_raw.Yoga.Inherit);
          let set result = ignore (expect_ok result) in
          set
            (Opentui_raw.Yoga.Node.set_display node
               Opentui_raw.Yoga.Display_flex);
          set
            (Opentui_raw.Yoga.Node.set_flex_direction node
               Opentui_raw.Yoga.Flex_row);
          set (Opentui_raw.Yoga.Node.set_flex_grow node (Some 1.0));
          set (Opentui_raw.Yoga.Node.set_flex_shrink node (Some 0.0));
          set
            (Opentui_raw.Yoga.Node.set_margin node
               ~edge:Opentui_raw.Yoga.Horizontal
               (Opentui_raw.Yoga.Point 2.0));
          set
            (Opentui_raw.Yoga.Node.set_padding node
               ~edge:Opentui_raw.Yoga.All (Opentui_raw.Yoga.Point 1.0));
          set
            (Opentui_raw.Yoga.Node.set_position node
               ~edge:Opentui_raw.Yoga.Left Opentui_raw.Yoga.Auto);
          set
            (Opentui_raw.Yoga.Node.set_gap node
               ~gutter:Opentui_raw.Yoga.Gutter_all
               (Opentui_raw.Yoga.Point 1.0));
          set
            (Opentui_raw.Yoga.Node.set_border node
               ~edge:Opentui_raw.Yoga.All ~value:(Some 1.0));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free node)));
      test "Yoga recursive free invalidates a detached subtree" (fun () ->
          let root = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let child = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:root ~child
                  ~index:0l));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free_recursive root));
          expect_error Opentui_raw.Error.Stale_handle
            (Opentui_raw.Yoga.Node.layout root);
          expect_error Opentui_raw.Error.Stale_handle
            (Opentui_raw.Yoga.Node.layout child));
      test "capability responses become typed copied snapshots" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:2l ~height:1l)
          in
          ignore
            (expect_ok
               (Opentui_raw.Capabilities.process_response renderer
                  ~response:"\x1bP>|kitty(0.42.2)\x1b\\"));
          ignore
            (expect_ok
               (Opentui_raw.Capabilities.process_response renderer
                  ~response:"\x1b[?2027;2$y"));
          let capabilities =
            expect_ok (Opentui_raw.Capabilities.snapshot renderer)
          in
          equal string "kitty" capabilities.terminal.name;
          equal string "0.42.2" capabilities.terminal.version;
          equal bool true capabilities.terminal.from_xtversion;
          (match capabilities.unicode with
          | Opentui_raw.Capabilities.Unicode -> ()
          | Opentui_raw.Capabilities.Wcwidth -> fail "expected Unicode mode");
          (match capabilities.multiplexer with
          | Opentui_raw.Capabilities.No_multiplexer -> ()
          | _ -> fail "unexpected multiplexer");
          (match capabilities.image_protocol with
          | Opentui_raw.Capabilities.Auto -> ()
          | _ -> fail "unexpected image protocol");
          Opentui_raw.Renderer.close renderer;
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Capabilities.snapshot renderer);
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Capabilities.process_response renderer ~response:""));
      test "span feed copies payloads and release controls chunk reuse" (fun () ->
          let options =
            {
              Opentui_raw.Span_feed.chunk_size = 8l;
              initial_chunks = 1l;
              max_bytes = 0L;
              growth_policy = Opentui_raw.Span_feed.Block;
              auto_commit_on_full = false;
              span_queue_capacity = 8l;
            }
          in
          let feed =
            expect_ok (Opentui_raw.Span_feed.create ~options ())
          in
          ignore
            (expect_ok
               (Opentui_raw.Span_feed.write feed (Bytes.of_string "hello")));
          ignore (expect_ok (Opentui_raw.Span_feed.commit feed));
          let before_drain = expect_ok (Opentui_raw.Span_feed.stats feed) in
          equal int64 5L before_drain.bytes_written;
          equal int64 1L before_drain.spans_committed;
          let span =
            match expect_ok (Opentui_raw.Span_feed.drain feed) with
            | [ span ] -> span
            | _ -> fail "expected one output span"
          in
          equal string "hello"
            (Bytes.to_string (Opentui_raw.Span_feed.Span.bytes span));
          expect_error Opentui_raw.Error.No_space
            (Opentui_raw.Span_feed.reserve feed ~min_length:1l);
          ignore (expect_ok (Opentui_raw.Span_feed.Span.release span));
          ignore (expect_ok (Opentui_raw.Span_feed.Span.release span));
          let after_release = expect_ok (Opentui_raw.Span_feed.stats feed) in
          equal int32 0l after_release.pending_spans;
          let reservation =
            expect_ok (Opentui_raw.Span_feed.reserve feed ~min_length:1l)
          in
          ignore (expect_ok (Opentui_raw.Span_feed.Reservation.cancel reservation));
          ignore (expect_ok (Opentui_raw.Span_feed.close feed)));
      test "span feed reservations make busy state cancellable" (fun () ->
          let options =
            {
              Opentui_raw.Span_feed.chunk_size = 8l;
              initial_chunks = 1l;
              max_bytes = 0L;
              growth_policy = Opentui_raw.Span_feed.Grow;
              auto_commit_on_full = false;
              span_queue_capacity = 8l;
            }
          in
          let feed =
            expect_ok (Opentui_raw.Span_feed.create ~options ())
          in
          let cancelled =
            expect_ok (Opentui_raw.Span_feed.reserve feed ~min_length:4l)
          in
          expect_error Opentui_raw.Error.Busy
            (Opentui_raw.Span_feed.close feed);
          ignore
            (expect_ok
               (Opentui_raw.Span_feed.Reservation.cancel cancelled));
          let reservation =
            expect_ok (Opentui_raw.Span_feed.reserve feed ~min_length:4l)
          in
          Bytes.blit_string "abc" 0
            (Opentui_raw.Span_feed.Reservation.contents reservation) 0 3;
          ignore
            (expect_ok
               (Opentui_raw.Span_feed.Reservation.commit reservation
                  ~used:3l));
          let span =
            match expect_ok (Opentui_raw.Span_feed.drain feed) with
            | [ span ] -> span
            | _ -> fail "expected one reserved output span"
          in
          equal string "abc"
            (Bytes.to_string (Opentui_raw.Span_feed.Span.bytes span));
          ignore (expect_ok (Opentui_raw.Span_feed.Span.release span));
          ignore (expect_ok (Opentui_raw.Span_feed.close feed)))
    ]
