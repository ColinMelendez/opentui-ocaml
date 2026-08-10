open Windtrap

module Native_renderer = Opentui_native.Renderer
module Output = Opentui_terminal_eio.Output_flow

let expect_renderer_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_native.Error.message error)

let expect_output_ok result =
  match result with
  | Ok () -> ()
  | Error error -> fail (Output.message error)

let () =
  run "opentui-native-terminal"
    [
      test "composes a native frame with an Eio output sink" (fun () ->
          Eio_main.run @@ fun _env ->
          let sink_buffer = Buffer.create 32 in
          let sink = Eio.Flow.buffer_sink sink_buffer in
          let output = Output.create ~sink in
          let renderer =
            expect_renderer_ok (Native_renderer.create ~width:2l ~height:1l)
          in
          let frame = expect_renderer_ok (Native_renderer.begin_frame renderer) in
          ignore
            (expect_renderer_ok
               (Native_renderer.Frame.clear frame
                  ~background:Opentui_native.Color.black));
          ignore
            (expect_renderer_ok
               (Native_renderer.Frame.set_cell frame ~x:0l ~y:0l ~character:65l
                  ~foreground:Opentui_native.Color.white
                  ~background:Opentui_native.Color.black ~attributes:0l));
          ignore
            (expect_renderer_ok
               (Native_renderer.Frame.set_cell frame ~x:1l ~y:0l ~character:66l
                  ~foreground:Opentui_native.Color.white
                  ~background:Opentui_native.Color.black ~attributes:0l));
          let resolved = Bytes.create 4 in
          let written =
            expect_renderer_ok
              (Native_renderer.Frame.write_resolved_chars frame ~output:resolved
                 ~add_line_breaks:false)
          in
          equal int32 2l written;
          expect_output_ok (Output.set_cursor_visible output false);
          expect_output_ok
            (Output.write_subbytes output ~bytes:resolved ~off:0
               ~len:(Int32.to_int written));
          (match
             expect_renderer_ok (Native_renderer.present frame ~force:true)
           with
          | Native_renderer.Rendered -> ()
          | Native_renderer.Skipped -> fail "expected a rendered frame"
          | Native_renderer.Failed -> fail "the native frame failed");
          equal string "\x1b[?25lAB" (Buffer.contents sink_buffer);
          Native_renderer.close renderer)
    ]
