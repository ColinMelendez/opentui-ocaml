open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Box = Core.Renderables.Box
module Text = Core.Renderables.Text
module Text_table = Core.Renderables.Text_table

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let contains_substring value substring =
  let value_length = String.length value in
  let substring_length = String.length substring in
  if substring_length = 0 then true
  else if substring_length > value_length then false
  else
    let found = ref false in
    for index = 0 to value_length - substring_length do
      if
        not !found
        && String.equal
             (String.sub value index substring_length)
             substring
      then found := true
    done;
    !found

let first_frame_output frames =
  match frames with
  | frame :: _ -> String.concat "" (List.map Bytes.to_string frame)
  | [] -> fail "renderer did not deliver a frame"

let color_rgb ~red ~green ~blue =
  match Core.Color.rgb ~red ~green ~blue with
  | Ok color -> color
  | Error error -> fail (Core.Native.Error.message error)

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
      test "text renderables preserve chunk colors and attributes" (fun () ->
          let frames = ref [] in
          let sink =
            Renderer.Output.sink ~write_frame:(fun chunks ->
                frames := chunks :: !frames;
                Ok ())
          in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Output.Sink sink) ~width:16l
                 ~height:3l ())
          in
          let yellow = color_rgb ~red:255 ~green:255 ~blue:0 in
          let styled =
            Core.Lib.Styled_text.create
              [ Core.Lib.Styled_text.chunk ~fg:yellow
                  ~attributes:Core.Lib.Text_attributes.bold "styled" ]
          in
          let text =
            expect_ok (Text.create (Renderer.context renderer) ~content:styled ())
          in
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Text.as_renderable text)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let output = first_frame_output !frames in
          equal bool true
            (contains_substring output "38;2;255;255;0");
          equal bool true (contains_substring output "[1m");
          Text.destroy text;
          ignore (expect_ok (Renderer.close renderer)));
      test "text table cells preserve chunk colors" (fun () ->
          let frames = ref [] in
          let sink =
            Renderer.Output.sink ~write_frame:(fun chunks ->
                frames := chunks :: !frames;
                Ok ())
          in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Output.Sink sink) ~width:16l
                 ~height:3l ())
          in
          let cyan = color_rgb ~red:0 ~green:255 ~blue:255 in
          let styled =
            Core.Lib.Styled_text.create
              [ Core.Lib.Styled_text.chunk ~fg:cyan "cell" ]
          in
          let table =
            expect_ok
              (Text_table.create (Renderer.context renderer)
                 ~content:[ [ Text_table.Styled styled ] ] ())
          in
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Text_table.as_renderable table)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let output = first_frame_output !frames in
          if not (contains_substring output "38;2;0;255;255") then
            fail ("styled table output was: " ^ String.escaped output);
          Text_table.destroy table;
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
