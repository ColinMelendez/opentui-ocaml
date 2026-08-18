open Windtrap

module Renderer = Opentui_core.Renderer
module Color = Opentui_core.Color

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_core.Error.message error)

let expect_color result =
  match result with
  | Ok color -> color
  | Error error -> fail (Opentui_core.Native.Error.message error)

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual ->
      equal string (Opentui_core.Error.message expected)
        (Opentui_core.Error.message actual)

let assert_color expected actual =
  let expected_red, expected_green, expected_blue, expected_alpha = expected in
  let red, green, blue, alpha = Color.channels actual in
  equal int expected_red red;
  equal int expected_green green;
  equal int expected_blue blue;
  equal int expected_alpha alpha

let assert_background background expected =
  equal int 8 (Array.length background);
  Array.iteri
    (fun index actual ->
      let expected_channel =
        match index mod 4 with
        | 0 -> expected |> fun (red, _, _, _) -> red
        | 1 -> expected |> fun (_, green, _, _) -> green
        | 2 -> expected |> fun (_, _, blue, _) -> blue
        | _ -> expected |> fun (_, _, _, alpha) -> alpha
      in
      equal int32 (Int32.of_int expected_channel) actual)
    background

let () =
  run "opentui-core-renderer-presentation"
    [
      test "background updates the next buffer and requests one repaint" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:2l ~height:1l ()) in
          assert_color (0, 0, 0, 0) (expect_ok (Renderer.background_color renderer));
          equal bool false (expect_ok (Renderer.has_pending_render renderer));
          let background = expect_color (Color.rgb ~red:12 ~green:34 ~blue:56) in
          ignore (expect_ok (Renderer.set_background_color renderer ~color:background));
          assert_color (12, 34, 56, 255)
            (expect_ok (Renderer.background_color renderer));
          let _, _, snapshot_background, _ =
            expect_ok (Opentui_core.Buffer.snapshot (expect_ok (Renderer.next_buffer renderer)))
          in
          assert_background snapshot_background (12, 34, 56, 255);
          equal bool true (expect_ok (Renderer.has_pending_render renderer));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal bool false (expect_ok (Renderer.has_pending_render renderer));
          Renderer.destroy renderer);
      test "cursor presentation is native, persistent, and resize-clamped" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:3l ~height:2l ()) in
          let initial = expect_ok (Renderer.cursor_state renderer) in
          equal int32 1l initial.x;
          equal int32 1l initial.y;
          equal bool true initial.visible;
          let red = expect_color (Color.rgb ~red:240 ~green:20 ~blue:30) in
          ignore
            (expect_ok
               (Renderer.set_cursor_position renderer ~x:(-3l) ~y:0l
                  ~visible:false ()));
          equal bool false (expect_ok (Renderer.cursor_state renderer)).visible;
          equal bool false (expect_ok (Renderer.has_pending_render renderer));
          ignore
            (expect_ok
               (Renderer.set_cursor_style renderer
                  {
                    Renderer.style = Some Renderer.Underline;
                    blinking = Some true;
                    color = Some red;
                    cursor = None;
                  }));
          let styled = expect_ok (Renderer.cursor_state renderer) in
          (match styled.style with
          | Renderer.Underline -> ()
          | Renderer.Block | Renderer.Line | Renderer.Default ->
              fail "cursor style did not reach native renderer");
          equal bool true styled.blinking;
          assert_color (240, 20, 30, 255) styled.color;
          equal bool false (expect_ok (Renderer.has_pending_render renderer));
          ignore
            (expect_ok
               (Renderer.set_cursor_position renderer ~x:9l ~y:9l ()));
          ignore (expect_ok (Renderer.resize renderer ~width:2l ~height:1l));
          let resized = expect_ok (Renderer.cursor_state renderer) in
          equal int32 2l resized.x;
          equal int32 1l resized.y;
          equal bool true resized.visible;
          (match resized.style with
          | Renderer.Underline -> ()
          | Renderer.Block | Renderer.Line | Renderer.Default ->
              fail "resize did not preserve cursor style");
          equal bool true resized.blinking;
          assert_color (240, 20, 30, 255) resized.color;
          equal bool true (expect_ok (Renderer.has_pending_render renderer));
          Renderer.destroy renderer);
      test "context forwards cursor presentation through the renderer owner" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:3l ~height:2l ()) in
          let context = Renderer.context renderer in
          ignore
            (expect_ok
               (Opentui_core.Render_context.set_cursor_position context ~x:2l
                  ~y:2l ~visible:false ()));
          let yellow = expect_color (Color.rgb ~red:220 ~green:210 ~blue:10) in
          ignore
            (expect_ok
               (Opentui_core.Render_context.set_cursor_style context
                  {
                    Opentui_core.Render_context.style = Some Renderer.Line;
                    blinking = Some true;
                    color = None;
                    cursor = Some Renderer.Mouse_text;
                  }));
          ignore
            (expect_ok
               (Opentui_core.Render_context.set_cursor_color context
                  ~color:yellow));
          let state = expect_ok (Renderer.cursor_state renderer) in
          equal int32 2l state.x;
          equal int32 2l state.y;
          equal bool false state.visible;
          (match state.style with
          | Renderer.Line -> ()
          | Renderer.Block | Renderer.Underline | Renderer.Default ->
              fail "context cursor style did not reach renderer");
          equal bool true state.blinking;
          assert_color (220, 210, 10, 255) state.color;
          equal bool false (expect_ok (Renderer.has_pending_render renderer));
          ignore
            (expect_ok
               (Opentui_core.Render_context.set_mouse_pointer context
                  Renderer.Mouse_crosshair));
          Renderer.destroy renderer;
          expect_error Opentui_core.Error.Closed
            (Opentui_core.Render_context.set_cursor_position context ~x:1l
               ~y:1l ()));
      test "presentation APIs follow Core renderer close semantics" (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:1l ~height:1l ()) in
          Renderer.destroy renderer;
          Renderer.destroy renderer;
          expect_error Opentui_core.Error.Closed (Renderer.background_color renderer);
          expect_error Opentui_core.Error.Closed (Renderer.cursor_state renderer);
          expect_error Opentui_core.Error.Closed
            (Renderer.set_background_color renderer ~color:Color.black);
          expect_error Opentui_core.Error.Closed
            (Renderer.set_cursor_position renderer ~x:1l ~y:1l ());
          expect_error Opentui_core.Error.Closed
            (Renderer.set_cursor_style renderer
               {
                 Renderer.style = None;
                 blinking = None;
                 color = None;
                 cursor = None;
               });
          expect_error Opentui_core.Error.Closed
            (Renderer.set_cursor_color renderer ~color:Color.white);
          expect_error Opentui_core.Error.Closed
            (Renderer.resize renderer ~width:2l ~height:2l) )
    ]
