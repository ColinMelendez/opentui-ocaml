module Buffer = Opentui_core.Buffer
module Renderer = Opentui_core.Renderer

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> failwith (Opentui_core.Error.message error)

let () =
  let renderer = expect_ok (Renderer.create ~width:14l ~height:3l) in
  let buffer = expect_ok (Renderer.next_buffer renderer) in
  ignore (expect_ok (Buffer.clear buffer ~background:Opentui_core.Color.black));
  ignore
    (expect_ok
       (Buffer.draw_text buffer ~text:"hello" ~x:0l ~y:0l
          ~foreground:Opentui_core.Color.white
          ~background:Opentui_core.Color.black ~attributes:0l));
  let output = Bytes.create 42 in
  let written =
    expect_ok
      (Buffer.write_resolved_chars buffer ~output ~add_line_breaks:false)
  in
  Printf.printf "dimensions: %ldx%ld\n" (expect_ok (Buffer.width buffer))
    (expect_ok (Buffer.height buffer));
  Printf.printf "prefix: %S\n" (Bytes.sub_string output 0 5);
  Printf.printf "written: %ld\n" written;
  ignore (expect_ok (Renderer.resize renderer ~width:16l ~height:4l));
  Printf.printf "resized: %ldx%ld\n" (expect_ok (Buffer.width buffer))
    (expect_ok (Buffer.height buffer));
  Renderer.destroy renderer
