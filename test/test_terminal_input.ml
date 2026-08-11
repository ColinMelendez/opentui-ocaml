open Windtrap

module Parser = Opentui_terminal.Stdin_parser
module Input = Opentui_terminal.Input_decoder

let sequence text =
  Parser.Sequence { protocol = Parser.Csi; bytes = Bytes.of_string text }

let same_key_kind left right =
  match left, right with
  | Input.Key _, Input.Key _ -> true
  | Input.Mouse _, Input.Mouse _ -> true
  | Input.Sequence _, Input.Sequence _ -> true
  | Input.Paste _, Input.Paste _ -> true
  | _ -> false

let () =
  run "opentui-terminal-input"
    [
      test "composition decodes keys and mouse events" (fun () ->
          let decoder = Input.create () in
          let payload = Bytes.of_string "A" in
          let decoded = Input.decode decoder (Parser.Key payload) in
          Bytes.set_uint8 payload 0 0;
          (match decoded with
          | Input.Key { key = Opentui_terminal.Key_decoder.Character bytes; modifiers } ->
              equal string "A" (Bytes.to_string bytes);
              equal bool true modifiers.Opentui_terminal.Key_decoder.shift
          | _ -> fail "expected a composed character key");
          (match Input.decode decoder (sequence "\x1b[<0;6;6M") with
          | Input.Mouse event ->
              (match event.Opentui_terminal.Mouse_decoder.kind with
              | Opentui_terminal.Mouse_decoder.Down -> ()
              | _ -> fail "expected a mouse down")
          | _ -> fail "expected a composed mouse event");
          (match Input.decode decoder (sequence "\x1b[<32;8;6M") with
          | Input.Mouse event ->
              equal int 7 event.Opentui_terminal.Mouse_decoder.x;
              (match event.Opentui_terminal.Mouse_decoder.kind with
              | Opentui_terminal.Mouse_decoder.Drag -> ()
              | _ -> fail "expected a composed drag")
          | _ -> fail "expected a composed mouse drag"));
      test "composition preserves unknown sequence ownership" (fun () ->
          let decoder = Input.create () in
          let raw = Bytes.of_string "\x1b[1;1R" in
          let decoded =
            Input.decode decoder
              (Parser.Sequence { protocol = Parser.Csi; bytes = raw })
          in
          Bytes.set_uint8 raw 0 0;
          (match decoded with
          | Input.Sequence { bytes; _ } -> equal string "\x1b[1;1R" (Bytes.to_string bytes)
          | _ -> fail "expected an opaque composed sequence"));
      test "rejects overflowing modifyOtherKeys parameters" (fun () ->
          let decoder = Input.create () in
          match
            Input.decode decoder
              (sequence "\x1b[27;1;4611686018427387904~")
          with
          | Input.Sequence { protocol = Parser.Csi; bytes } ->
              equal string "\x1b[27;1;4611686018427387904~"
                (Bytes.to_string bytes)
          | _ -> fail "expected an opaque sequence");
      test "reset clears mouse state for the next composition" (fun () ->
          let decoder = Input.create () in
          ignore (Input.decode decoder (sequence "\x1b[<0;6;6M"));
          Input.reset decoder;
          match Input.decode decoder (sequence "\x1b[<32;8;6M") with
          | Input.Mouse event ->
              (match event.Opentui_terminal.Mouse_decoder.kind with
              | Opentui_terminal.Mouse_decoder.Move -> ()
              | _ -> fail "expected reset mouse state to produce motion")
          | _ -> fail "expected a composed mouse event after reset");
      test "composition keeps paste events distinct" (fun () ->
          let decoder = Input.create () in
          let payload = Bytes.of_string "paste" in
          match Input.decode decoder (Parser.Paste payload) with
          | Input.Paste actual ->
              Bytes.set_uint8 payload 0 0;
              equal string "paste" (Bytes.to_string actual)
          | actual ->
              equal bool true (same_key_kind (Input.Paste Bytes.empty) actual))
    ]
