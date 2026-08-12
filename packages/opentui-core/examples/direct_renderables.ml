module Scene = Opentui_core.Scene
module Box = Scene.Box
module Text = Scene.Text
module Node = Scene.Node

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> failwith (Opentui_core.Error.message error)

let expect_unit result = ignore (expect_ok result)

let utf8_length text index =
  let byte = Char.code text.[index] in
  if Int.equal (byte land 0x80) 0 then 1
  else if Int.equal (byte land 0xe0) 0xc0 then 2
  else if Int.equal (byte land 0xf0) 0xe0 then 3
  else 4

let print_frame ~label ~width ~height output bytes_written =
  let rendered = Bytes.sub_string output 0 (Int32.to_int bytes_written) in
  Printf.printf "%s\n" label;
  let index = ref 0 in
  let row = ref 0 in
  while !row < height do
    let cells = ref 0 in
    let line = Buffer.create width in
    while !cells < width do
      if !index >= String.length rendered then failwith "short rendered frame";
      let length = utf8_length rendered !index in
      Buffer.add_substring line rendered !index length;
      index := !index + length;
      cells := !cells + 1
    done;
    print_endline (Buffer.contents line);
    row := !row + 1
  done;
  if not (Int.equal !index (String.length rendered)) then
    failwith "long rendered frame"

let flush_and_print scene ~label ~width ~height output =
  match Scene.flush scene ~force:false ~output with
  | Error error -> failwith (Opentui_core.Error.message error)
  | Ok { status = Scene.Rendered; bytes_written } ->
      print_frame ~label ~width ~height output bytes_written
  | Ok { status = Scene.Skipped; _ } -> failwith "example frame was skipped"
  | Ok { status = Scene.Failed; _ } -> failwith "example frame failed"

let () =
  let width = 14 in
  let height = 3 in
  let scene = expect_ok (Scene.create ~width:14l ~height:3l) in
  let root = expect_ok (Scene.root scene) in
  let panel =
    expect_ok
      (Box.create ~parent:root ~width:(Float.of_int width)
         ~height:(Float.of_int height) ~border:Scene.Single ())
  in
  let status =
    expect_ok
      (Text.create ~parent:(Box.node panel) ~width:12.0 ~height:1.0
         ~text:" initial    " ())
  in
  Printf.printf "identities: panel=%d status=%d\n" (Node.id (Box.node panel))
    (Node.id (Text.node status));
  let output = Bytes.create 256 in
  flush_and_print scene ~label:"initial:" ~width ~height output;
  expect_unit (Text.set status ~content:" updated    ");
  flush_and_print scene ~label:"after text update:" ~width ~height output;
  expect_unit (Box.set_border panel ~border:Scene.Double);
  flush_and_print scene ~label:"after box update:" ~width ~height output;
  Scene.close scene
