open Windtrap

module Renderer = Opentui_raw.Renderer

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_raw.Error.message error)

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual ->
      equal string (Opentui_raw.Error.message expected)
        (Opentui_raw.Error.message actual)

let assert_color expected actual =
  let expected_red, expected_green, expected_blue, expected_alpha = expected in
  let red, green, blue, alpha = Opentui_raw.Color.channels actual in
  equal int expected_red red;
  equal int expected_green green;
  equal int expected_blue blue;
  equal int expected_alpha alpha

let contains_substring ~needle haystack =
  let needle_length = String.length needle in
  let haystack_length = String.length haystack in
  let found = ref false in
  if Int.equal needle_length 0 then found := true
  else if Int.compare needle_length haystack_length <= 0 then
    for offset = 0 to haystack_length - needle_length do
      if String.equal
           (String.sub haystack offset needle_length)
           needle
      then found := true
    done;
  !found

let collect_spans spans =
  let output = Buffer.create 256 in
  List.iter
    (fun span ->
      Buffer.add_bytes output (Opentui_raw.Span_feed.Span.bytes span);
      ignore (Opentui_raw.Span_feed.Span.release span))
    spans;
  Buffer.contents output

let () =
  run "opentui-raw-renderer-presentation"
    [
      test "background and cursor state are native renderer-owned" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:3l ~height:2l ()) in
          ignore
            (expect_ok
               (Renderer.set_background_color renderer
                  ~color:Opentui_raw.Color.black));
          let initial = expect_ok (Renderer.cursor_state renderer) in
          equal int32 1l initial.x;
          equal int32 1l initial.y;
          equal bool true initial.visible;
          equal bool false initial.blinking;
          (match initial.style with
          | Renderer.Default -> ()
          | Renderer.Block | Renderer.Line | Renderer.Underline ->
              fail "expected the default terminal cursor style");
          assert_color (255, 255, 255, 255) initial.color;
          ignore
            (expect_ok
               (Renderer.set_cursor_position renderer ~x:(-4l) ~y:0l
                  ~visible:false ()));
          let hidden = expect_ok (Renderer.cursor_state renderer) in
          equal int32 1l hidden.x;
          equal int32 1l hidden.y;
          equal bool false hidden.visible;
          let red = expect_ok (Opentui_raw.Color.rgb ~red:200 ~green:10 ~blue:30) in
          ignore
            (expect_ok
               (Renderer.set_cursor_style renderer
                  {
                    Renderer.style = Some Renderer.Line;
                    blinking = Some true;
                    color = Some red;
                    cursor = None;
                  }));
          let styled = expect_ok (Renderer.cursor_state renderer) in
          (match styled.style with
          | Renderer.Line -> ()
          | Renderer.Block | Renderer.Underline | Renderer.Default ->
              fail "cursor style did not reach native renderer");
          equal bool true styled.blinking;
          assert_color (200, 10, 30, 255) styled.color;
          let blue = expect_ok (Opentui_raw.Color.rgb ~red:1 ~green:2 ~blue:250) in
          ignore
            (expect_ok
               (Renderer.set_cursor_style renderer
                  {
                    Renderer.style = None;
                    blinking = None;
                    color = Some blue;
                    cursor = Some Renderer.Mouse_pointer;
                  }));
          let partially_updated = expect_ok (Renderer.cursor_state renderer) in
          (match partially_updated.style with
          | Renderer.Line -> ()
          | Renderer.Block | Renderer.Underline | Renderer.Default ->
              fail "unspecified cursor style was not preserved");
          equal bool true partially_updated.blinking;
          assert_color (1, 2, 250, 255) partially_updated.color;
          let green = expect_ok (Opentui_raw.Color.rgb ~red:3 ~green:240 ~blue:4) in
          ignore (expect_ok (Renderer.set_cursor_color renderer ~color:green));
          assert_color (3, 240, 4, 255)
            (expect_ok (Renderer.cursor_state renderer)).color;
          ignore
            (expect_ok
               (Renderer.set_cursor_position renderer ~x:9l ~y:9l ())) ;
          ignore
            (expect_ok (Renderer.resize renderer ~width:2l ~height:1l));
          let resized = expect_ok (Renderer.cursor_state renderer) in
          equal int32 2l resized.x;
          equal int32 1l resized.y;
          equal bool true resized.visible;
          Opentui_raw.Renderer.close renderer);
      test "presentation operations report closed ownership" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l ()) in
          equal bool false
            (expect_ok
               (Renderer.trigger_notification renderer
                  ~message:(Bytes.of_string "notification test") ~title:None));
          Renderer.close renderer;
          Renderer.close renderer;
          expect_error Opentui_raw.Error.Closed (Renderer.cursor_state renderer);
          expect_error Opentui_raw.Error.Closed
            (Renderer.set_background_color renderer ~color:Opentui_raw.Color.black);
          expect_error Opentui_raw.Error.Closed
            (Renderer.set_cursor_position renderer ~x:1l ~y:1l ());
          expect_error Opentui_raw.Error.Closed
            (Renderer.set_cursor_style renderer
               {
                 Renderer.style = None;
                 blinking = None;
                 color = None;
                 cursor = None;
               });
          expect_error Opentui_raw.Error.Closed
            (Renderer.set_cursor_color renderer ~color:Opentui_raw.Color.white);
          expect_error Opentui_raw.Error.Closed
            (Renderer.trigger_notification renderer
               ~message:(Bytes.of_string "notification test") ~title:None);
          expect_error Opentui_raw.Error.Closed
            (Renderer.resize renderer ~width:2l ~height:2l))
      ;
      test "capability detection delegates probe construction to native" (fun () ->
          let feed = expect_ok (Opentui_raw.Span_feed.create ()) in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Feed feed)
                 ~remote_mode:Renderer.Remote ~width:3l ~height:1l ())
          in
          ignore (expect_ok (Renderer.query_terminal_capabilities renderer));
          let output = collect_spans (expect_ok (Renderer.drain_output renderer)) in
          equal bool true (contains_substring ~needle:"\027[>0q" output);
          equal bool true
            (contains_substring
               ~needle:"\027]99;i=opentui-notifications:p=?;" output);
          equal bool true (contains_substring ~needle:"\027[14t" output);
          equal bool false (contains_substring ~needle:"\027[?1049h" output);
          Renderer.close renderer;
          let teardown = expect_ok (Renderer.drain_output renderer) in
          List.iter
            (fun span -> ignore (Opentui_raw.Span_feed.Span.release span))
            teardown;
          ignore (expect_ok (Opentui_raw.Span_feed.close feed)))
      ;
      test "feed output preserves styled native frames through teardown" (fun () ->
          let feed = expect_ok (Opentui_raw.Span_feed.create ()) in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Feed feed)
                 ~remote_mode:Renderer.Remote ~width:3l ~height:1l ())
          in
          let buffer = expect_ok (Renderer.next_buffer renderer) in
          ignore
            (expect_ok
               (Opentui_raw.Buffer.draw_text buffer ~text:"A" ~x:0l ~y:0l
                  ~foreground:Opentui_raw.Color.white
                  ~background:Opentui_raw.Color.black ~attributes:0l));
          (match expect_ok (Renderer.render renderer ~force:true) with
           | Renderer.Rendered -> ()
           | Renderer.Skipped -> fail "feed renderer unexpectedly skipped"
           | Renderer.Failed -> fail "feed renderer failed");
          let spans = expect_ok (Renderer.drain_output renderer) in
          (match spans with
           | [] -> fail "feed renderer produced no frame output"
           | first :: _ ->
               equal bool true
                 (String.contains
                    (Bytes.to_string (Opentui_raw.Span_feed.Span.bytes first))
                    '\027'));
          List.iter
            (fun span -> ignore (Opentui_raw.Span_feed.Span.release span))
            spans;
          Renderer.close renderer;
          let teardown = expect_ok (Renderer.drain_output renderer) in
          List.iter
            (fun span -> ignore (Opentui_raw.Span_feed.Span.release span))
            teardown;
          ignore (expect_ok (Opentui_raw.Span_feed.close feed)))
    ]
