open Windtrap

module Renderer = Opentui_core.Renderer
module Core_buffer = Opentui_core.Buffer
module Output = Opentui_core.Platform.Eio_runtime.Output_flow

let expect_renderer_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_core.Error.message error)

let expect_output_ok result =
  match result with
  | Ok () -> ()
  | Error error -> fail (Output.message error)

let () =
  run "opentui-core-renderer-terminal"
    [
      test "composes a native frame with an Eio output sink" (fun () ->
          Eio_main.run @@ fun _env ->
          let sink_buffer = Buffer.create 32 in
          let sink = Eio.Flow.buffer_sink sink_buffer in
          let output = Output.create ~sink in
          let renderer =
            expect_renderer_ok (Renderer.create ~width:2l ~height:1l)
          in
          let buffer = expect_renderer_ok (Renderer.next_buffer renderer) in
          ignore
            (expect_renderer_ok
               (Core_buffer.clear buffer
                  ~background:Opentui_core.Color.black));
          ignore
            (expect_renderer_ok
               (Core_buffer.set_cell buffer ~x:0l ~y:0l ~character:65l
                  ~foreground:Opentui_core.Color.white
                  ~background:Opentui_core.Color.black ~attributes:0l));
          ignore
            (expect_renderer_ok
               (Core_buffer.set_cell buffer ~x:1l ~y:0l ~character:66l
                  ~foreground:Opentui_core.Color.white
                  ~background:Opentui_core.Color.black ~attributes:0l));
          let resolved = Bytes.create 4 in
          let written =
            expect_renderer_ok
              (Core_buffer.write_resolved_chars buffer ~output:resolved
                 ~add_line_breaks:false)
          in
          equal int32 2l written;
          expect_output_ok (Output.set_cursor_visible output false);
          expect_output_ok
            (Output.write_subbytes output ~bytes:resolved ~off:0
               ~len:(Int32.to_int written));
          (match
             expect_renderer_ok (Renderer.render renderer ~force:true)
           with
          | Renderer.Rendered -> ()
          | Renderer.Skipped -> fail "expected a rendered frame"
          | Renderer.Failed -> fail "the native frame failed");
          equal string "\x1b[?25lAB" (Buffer.contents sink_buffer);
          Renderer.destroy renderer)
    ]
