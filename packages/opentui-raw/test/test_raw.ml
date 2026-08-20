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
          let renderer = expect_ok (Opentui_raw.Renderer.create ~width:2l ~height:1l ()) in
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
          ignore
            (expect_ok
               (Opentui_raw.Renderer.write_out renderer
                  (Bytes.of_string "\027[2J")));
          Opentui_raw.Renderer.close renderer;
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Buffer.width current);
          expect_error Opentui_raw.Error.Closed (Opentui_raw.Buffer.height next);
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Renderer.write_out renderer Bytes.empty));
      test "renderer hit-grid capability preserves native frame ownership" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:3l ~height:2l ())
          in
          let hit_grid = Opentui_raw.Renderer.hit_grid renderer in
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Renderer.Hit_grid.add_to_hit_grid hit_grid ~x:0l ~y:0l
               ~width:(-1l) ~height:1l ~id:7l);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:(-1l) ~y:0l);
          ignore
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.add_to_hit_grid hit_grid ~x:0l
                  ~y:0l ~width:2l ~height:1l ~id:7l));
          equal int32 0l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:0l ~y:0l));
          ignore
            (expect_ok
               (Opentui_raw.Renderer.render renderer ~force:true));
          equal int32 7l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:0l ~y:0l));
          equal int32 0l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:2l ~y:0l));
          equal bool true
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.get_hit_grid_dirty hit_grid));
          equal bool true
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.get_hit_grid_dirty hit_grid));
          Opentui_raw.Renderer.Hit_grid.Private
            .hit_grid_clear_scissor_rects_unchecked hit_grid;
          Opentui_raw.Renderer.Hit_grid.Private
            .hit_grid_push_scissor_rect_unchecked hit_grid ~x:1l ~y:0l
            ~width:1l ~height:1l;
          Opentui_raw.Renderer.Hit_grid.Private.add_to_hit_grid_unchecked
            hit_grid ~x:0l ~y:0l ~width:3l ~height:2l ~id:9l;
          Opentui_raw.Renderer.Hit_grid.Private
            .hit_grid_pop_scissor_rect_unchecked hit_grid;
          ignore
            (expect_ok
               (Opentui_raw.Renderer.render renderer ~force:true));
          equal int32 0l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:0l ~y:0l));
          equal int32 9l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:1l ~y:0l));
          equal int32 0l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:1l ~y:1l));
          ignore
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.clear_current_hit_grid hit_grid));
          ignore
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.hit_grid_clear_scissor_rects
                  hit_grid));
          Opentui_raw.Renderer.Hit_grid.Private
            .add_to_current_hit_grid_clipped_unchecked hit_grid ~x:0l ~y:1l
            ~width:3l ~height:1l ~id:11l;
          equal int32 0l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:1l ~y:0l));
          equal int32 11l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:1l ~y:1l));
          ignore
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.add_to_hit_grid hit_grid ~x:0l
                  ~y:0l ~width:3l ~height:2l ~id:13l));
          Opentui_raw.Renderer.Hit_grid.Private.clear_next_hit_grid_unchecked
            hit_grid;
          equal int32 11l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:1l ~y:1l));
          ignore
            (expect_ok
               (Opentui_raw.Renderer.render renderer ~force:true));
          equal int32 0l
            (expect_ok
               (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:1l ~y:1l));
          Opentui_raw.Renderer.close renderer;
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Renderer.Hit_grid.check_hit hit_grid ~x:0l ~y:0l);
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Renderer.Hit_grid.clear_next_hit_grid hit_grid));
      test "text buffer views draw through the native buffer seam" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:6l ~height:2l ())
          in
          let buffer = expect_ok (Opentui_raw.Renderer.next_buffer renderer) in
          let text_buffer =
            expect_ok (Opentui_raw.Text_buffer.create Opentui_raw.Text_buffer.Wcwidth)
          in
          let view = expect_ok (Opentui_raw.Text_buffer_view.create text_buffer) in
          ignore
            (expect_ok
               (Opentui_raw.Text_buffer.set_text text_buffer (Bytes.of_string "AB")));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.clear buffer
                  ~background:Opentui_raw.Color.black));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.draw_text_buffer_view buffer view ~x:1l ~y:0l));
          let output = Bytes.create 12 in
          let written =
            expect_ok
              (Opentui_raw.Buffer.write_resolved_chars buffer ~output
                 ~add_line_breaks:false)
          in
          equal int32 12l written;
          equal string " AB         " (Bytes.to_string output);
          ignore
            (expect_ok
               (Opentui_raw.Buffer.clear buffer
                  ~background:Opentui_raw.Color.black));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.draw_text_buffer_view buffer view ~x:(-1l)
                  ~y:0l));
          let clipped_output = Bytes.create 12 in
          let clipped_written =
            expect_ok
              (Opentui_raw.Buffer.write_resolved_chars buffer
                 ~output:clipped_output ~add_line_breaks:false)
          in
          equal int32 12l clipped_written;
          equal string "B           " (Bytes.to_string clipped_output);
          ignore (expect_ok (Opentui_raw.Text_buffer_view.close view));
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Buffer.draw_text_buffer_view buffer view ~x:0l ~y:0l);
          ignore (expect_ok (Opentui_raw.Text_buffer.close text_buffer));
          Opentui_raw.Renderer.close renderer);
      test "boxes draw through the native buffer seam" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:6l ~height:4l ())
          in
          let buffer = expect_ok (Opentui_raw.Renderer.next_buffer renderer) in
          let border_chars =
            Array.of_list
              [
                Int32.of_int 0x250c;
                Int32.of_int 0x2510;
                Int32.of_int 0x2514;
                Int32.of_int 0x2518;
                Int32.of_int 0x2500;
                Int32.of_int 0x2502;
                Int32.of_int 0x252c;
                Int32.of_int 0x2534;
                Int32.of_int 0x251c;
                Int32.of_int 0x2524;
                Int32.of_int 0x253c;
              ]
          in
          ignore
            (expect_ok
               (Opentui_raw.Buffer.clear buffer
                  ~background:Opentui_raw.Color.black));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.draw_box buffer ~x:0l ~y:0l ~width:6l
                  ~height:4l ~border_chars ~packed_options:15l
                  ~border_color:Opentui_raw.Color.white
                  ~background_color:Opentui_raw.Color.black
                  ~title_color:Opentui_raw.Color.white ~title:None
                  ~bottom_title:None));
          let output = Bytes.create 128 in
          let written =
            expect_ok
              (Opentui_raw.Buffer.write_resolved_chars buffer ~output
                 ~add_line_breaks:false)
          in
          let rendered = Bytes.sub_string output 0 (Int32.to_int written) in
          equal string "┌────┐│    ││    │└────┘" rendered;
          ignore
            (expect_ok
               (Opentui_raw.Buffer.clear buffer
                  ~background:Opentui_raw.Color.black));
          ignore
            (expect_ok
               (Opentui_raw.Buffer.draw_box buffer ~x:(-1l) ~y:0l ~width:4l
                  ~height:4l ~border_chars ~packed_options:15l
                  ~border_color:Opentui_raw.Color.white
                  ~background_color:Opentui_raw.Color.black
                  ~title_color:Opentui_raw.Color.white ~title:None
                  ~bottom_title:None));
          let clipped_output = Bytes.create 128 in
          let clipped_written =
            expect_ok
              (Opentui_raw.Buffer.write_resolved_chars buffer
                 ~output:clipped_output ~add_line_breaks:false)
          in
          let clipped =
            Bytes.sub_string clipped_output 0 (Int32.to_int clipped_written)
          in
          equal string "──┐     │     │   ──┘   " clipped;
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Buffer.draw_box buffer ~x:0l ~y:0l ~width:1l
               ~height:1l ~border_chars:[||] ~packed_options:0l
               ~border_color:Opentui_raw.Color.white
               ~background_color:Opentui_raw.Color.black
               ~title_color:Opentui_raw.Color.white ~title:None
               ~bottom_title:None);
          Opentui_raw.Renderer.close renderer);
      test "invalid dimensions and colors are structured errors" (fun () ->
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Renderer.create ~width:0l ~height:1l ());
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Color.rgba ~red:256 ~green:0 ~blue:0 ~alpha:255));
      test "renderer resize preserves borrowed buffer handles" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:2l ~height:1l ())
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
          let renderer = expect_ok (Opentui_raw.Renderer.create ~width:1l ~height:1l ()) in
          let buffer = expect_ok (Opentui_raw.Renderer.current_buffer renderer) in
          let output = Bytes.create 0 in
          expect_error Opentui_raw.Error.Output_too_small
            (Opentui_raw.Buffer.write_resolved_chars buffer ~output
               ~add_line_breaks:false);
          Opentui_raw.Renderer.close renderer);
      test "renderer exposes typed frame status" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:1l ~height:1l ())
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
      test "renderer exposes split-footer scrollback primitives" (fun () ->
          let renderer =
            expect_ok
              (Opentui_raw.Renderer.create ~width:4l ~height:3l ())
          in
          equal int32 1l
            (expect_ok
               (Opentui_raw.Renderer.reset_split_scrollback renderer
                  ~seed_rows:1l ~pinned_render_offset:2l));
          equal int32 1l
            (expect_ok
               (Opentui_raw.Renderer.get_split_output_offset renderer
                  ~surface_offset:2l));
          ignore
            (expect_ok
               (Opentui_raw.Renderer.set_pending_split_footer_transition
                  renderer Opentui_raw.Renderer.Clear_stale_rows
                  ~source_top_line:2l ~source_height:1l ~target_top_line:2l
                  ~target_height:1l ~scroll_lines:0l));
          ignore
            (expect_ok
               (Opentui_raw.Renderer.clear_pending_split_footer_transition
                  renderer));
          (match
             expect_ok
               (Opentui_raw.Renderer.repaint_split_footer renderer
                  ~pinned_render_offset:2l ~force:true)
           with
          | _offset, Opentui_raw.Renderer.Rendered -> ()
          | _offset, Opentui_raw.Renderer.Skipped ->
              fail "split footer repaint was backpressured"
          | _offset, Opentui_raw.Renderer.Failed ->
              fail "split footer repaint failed");
          let snapshot =
            expect_ok
              (Opentui_raw.Optimized_buffer.create ~width:2l ~height:1l
                 ~respect_alpha:false ~width_method:1l ~id:"split-test")
          in
          ignore
            (expect_ok
               (Opentui_raw.Optimized_buffer.set_cell snapshot
                  (0l, 0l, 65l, Opentui_raw.Color.white,
                   Opentui_raw.Color.black, 0l)));
          (match
             expect_ok
               (Opentui_raw.Renderer.commit_split_footer_snapshot renderer
                  ~snapshot ~row_columns:2l ~start_on_new_line:true
                  ~trailing_newline:true ~pinned_render_offset:2l ~force:true
                  ~begin_frame:true ~finalize_frame:true)
           with
          | _offset, Opentui_raw.Renderer.Rendered -> ()
          | _offset, Opentui_raw.Renderer.Skipped ->
              fail "split snapshot commit was backpressured"
          | _offset, Opentui_raw.Renderer.Failed ->
              fail "split snapshot commit failed");
          Opentui_raw.Optimized_buffer.close snapshot;
          Opentui_raw.Renderer.close renderer);
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
      test "Yoga exposes native dirty and new-layout state" (fun () ->
          let node = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.calculate_layout node ~width:4.0
                  ~height:2.0 ~direction:Opentui_raw.Yoga.Ltr));
          equal bool false (expect_ok (Opentui_raw.Yoga.Node.is_dirty node));
          equal bool true
            (expect_ok (Opentui_raw.Yoga.Node.has_new_layout node));
          ignore (expect_ok (Opentui_raw.Yoga.Node.mark_layout_seen node));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.mark_dirty node);
          equal bool false
            (expect_ok (Opentui_raw.Yoga.Node.has_new_layout node));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free node));
      );
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
      test "text-buffer measurement stays native through Yoga" (fun () ->
          let buffer =
            expect_ok
              (Opentui_raw.Text_buffer.create Opentui_raw.Text_buffer.Unicode)
          in
          let view = expect_ok (Opentui_raw.Text_buffer_view.create buffer) in
          let node = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let native_renderable =
            expect_ok (Opentui_raw.Native_renderable.create ())
          in
          ignore
            (expect_ok
               (Opentui_raw.Text_buffer.set_text buffer
                  (Bytes.of_string "ABCDEFGHIJ")));
          Gc.compact ();
          ignore
            (expect_ok
               (Opentui_raw.Text_buffer_view.set_wrap_mode view
                  Opentui_raw.Text_buffer_view.Char));
          let measured =
            expect_ok
              (Opentui_raw.Text_buffer_view.measure_for_dimensions view
                 ~width:5l ~height:10l)
          in
          equal int32 2l measured.line_count;
          equal int32 5l measured.width_cols_max;
          ignore
            (expect_ok
               (Opentui_raw.Native_renderable.attach_yoga_node
                  native_renderable node));
          ignore
               (expect_ok
               (Opentui_raw.Native_renderable.set_measure_target
                  native_renderable
                  (Opentui_raw.Native_renderable.Text_buffer_view view)));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.free node);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Text_buffer_view.close view);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Text_buffer.close buffer);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Native_renderable.attach_yoga_node
               native_renderable node);
          let measured_child = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.insert_child ~parent:node
               ~child:measured_child ~index:0l);
          ignore (expect_ok (Opentui_raw.Yoga.Node.free measured_child));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.calculate_layout node ~width:5.0
                  ~height:Float.nan ~direction:Opentui_raw.Yoga.Ltr));
          let layout = expect_ok (Opentui_raw.Yoga.Node.layout node) in
          equal (float 0.0001) 5.0 layout.width;
          equal (float 0.0001) 2.0 layout.height;
          ignore
            (expect_ok
               (Opentui_raw.Native_renderable.clear_measure_target
                  native_renderable));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Yoga.Node.mark_dirty node);
          ignore
            (expect_ok
               (Opentui_raw.Native_renderable.set_measure_target
                  native_renderable
                  (Opentui_raw.Native_renderable.Text_buffer_view view)));
          ignore
            (expect_ok
               (Opentui_raw.Text_buffer.set_text buffer
                  (Bytes.of_string "ABCDE")));
          Gc.compact ();
          ignore (expect_ok (Opentui_raw.Yoga.Node.mark_dirty node));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.calculate_layout node ~width:5.0
                  ~height:Float.nan ~direction:Opentui_raw.Yoga.Ltr));
          let updated_layout = expect_ok (Opentui_raw.Yoga.Node.layout node) in
          equal (float 0.0001) 1.0 updated_layout.height;
          for _ = 1 to 300 do
            ignore
              (expect_ok
                 (Opentui_raw.Text_buffer.set_text buffer
                    (Bytes.of_string "X")))
          done;
          equal int32 1l (expect_ok (Opentui_raw.Text_buffer.length buffer));
          ignore
            (expect_ok
               (Opentui_raw.Text_buffer.set_text buffer
                  (Bytes.of_string "A\r\nB")));
          equal int32 3l (expect_ok (Opentui_raw.Text_buffer.byte_size buffer));
          ignore
            (expect_ok
               (Opentui_raw.Text_buffer.append buffer
                  (Bytes.of_string "A\r\nB")));
          expect_ok (Opentui_raw.Native_renderable.close native_renderable);
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Native_renderable.set_measure_target
               native_renderable
               (Opentui_raw.Native_renderable.Text_buffer_view view));
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.calculate_layout node ~width:5.0
                  ~height:Float.nan ~direction:Opentui_raw.Yoga.Ltr));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free node));
          expect_ok (Opentui_raw.Text_buffer_view.close view);
          expect_ok (Opentui_raw.Text_buffer.close buffer);
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Text_buffer_view.measure_for_dimensions view
               ~width:5l ~height:10l);
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Text_buffer.append buffer (Bytes.create 0));
          let closed_view_renderable =
            expect_ok (Opentui_raw.Native_renderable.create ())
          in
          expect_error Opentui_raw.Error.Closed
            (Opentui_raw.Native_renderable.set_measure_target
               closed_view_renderable
               (Opentui_raw.Native_renderable.Text_buffer_view view));
          expect_ok (Opentui_raw.Native_renderable.close closed_view_renderable));
      test "text-buffer view validates dimensions and parent lifetime" (fun () ->
          let buffer =
            expect_ok
              (Opentui_raw.Text_buffer.create Opentui_raw.Text_buffer.Wcwidth)
          in
          let view = expect_ok (Opentui_raw.Text_buffer_view.create buffer) in
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Text_buffer_view.set_wrap_width view (Some (-1l)));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Text_buffer_view.measure_for_dimensions view
               ~width:(-1l) ~height:1l);
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Text_buffer.close buffer);
          ignore
            (expect_ok
               (Opentui_raw.Text_buffer_view.set_first_line_offset view 0l));
          expect_ok (Opentui_raw.Text_buffer_view.close view);
          expect_ok (Opentui_raw.Text_buffer.close buffer));
      test "native measurement only attaches to Yoga leaves" (fun () ->
          let buffer =
            expect_ok
              (Opentui_raw.Text_buffer.create Opentui_raw.Text_buffer.Unicode)
          in
          let view = expect_ok (Opentui_raw.Text_buffer_view.create buffer) in
          let node = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let child = expect_ok (Opentui_raw.Yoga.Node.create ()) in
          let native_renderable =
            expect_ok (Opentui_raw.Native_renderable.create ())
          in
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.insert_child ~parent:node ~child
                  ~index:0l));
          ignore
            (expect_ok
               (Opentui_raw.Native_renderable.set_measure_target
                  native_renderable
                  (Opentui_raw.Native_renderable.Text_buffer_view view)));
          expect_error Opentui_raw.Error.Invalid_argument
            (Opentui_raw.Native_renderable.attach_yoga_node
               native_renderable node);
          expect_ok (Opentui_raw.Native_renderable.close native_renderable);
          ignore
            (expect_ok
               (Opentui_raw.Yoga.Node.remove_child ~parent:node ~child));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free child));
          ignore (expect_ok (Opentui_raw.Yoga.Node.free node));
          expect_ok (Opentui_raw.Text_buffer_view.close view);
          expect_ok (Opentui_raw.Text_buffer.close buffer));
      test "capability responses become typed copied snapshots" (fun () ->
          let renderer =
            expect_ok (Opentui_raw.Renderer.create ~width:2l ~height:1l ())
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
