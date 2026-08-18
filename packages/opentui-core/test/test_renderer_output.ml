open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Box = Core.Renderables.Box

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let () =
  run "opentui-core-renderer-output"
    [
      test "sink output receives complete styled native frames" (fun () ->
          let frames = ref [] in
          let sink =
            Renderer.Output.sink ~write_frame:(fun chunks ->
                frames := chunks :: !frames;
                Ok ())
          in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Output.Sink sink) ~width:3l
                 ~height:1l ())
          in
          let box =
            expect_ok
              (Box.create (Renderer.context renderer)
                 ~background_color:Core.Color.black ~should_fill:true ())
          in
          ignore (expect_ok (Box.set_width box (Core.Yoga.Point 3.0)));
          ignore (expect_ok (Box.set_height box (Core.Yoga.Point 1.0)));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Box.as_renderable box)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          (match !frames with
           | [] -> fail "renderer did not deliver a frame"
           | chunks :: _ ->
               equal bool true (Int.compare (List.length chunks) 0 > 0);
               equal bool true
                 (List.exists
                    (fun bytes -> String.contains (Bytes.to_string bytes) '\027')
                    chunks));
          ignore (expect_ok (Renderer.close renderer)));
      test "a failed sink poisons the renderer output path" (fun () ->
          let sink =
            Renderer.Output.sink ~write_frame:(fun _ ->
                Error (Core.Error.Io "test sink failure"))
          in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Output.Sink sink) ~width:1l
                 ~height:1l ())
          in
          (match Renderer.render renderer ~force:true with
           | Error (Core.Error.Output _) -> ()
           | Error error ->
               fail ("unexpected renderer error: " ^ Core.Error.message error)
           | Ok _ -> fail "a failed output sink did not fail the frame");
          (match Renderer.render renderer ~force:true with
           | Error (Core.Error.Output _) -> ()
           | Error error ->
               fail ("unexpected repeated renderer error: " ^
                     Core.Error.message error)
           | Ok _ -> fail "a poisoned output path rendered again");
          match Renderer.close renderer with
          | Error (Core.Error.Output _) -> ()
          | Ok () -> ()
          | Error error ->
              fail ("unexpected close error: " ^ Core.Error.message error))
    ]
