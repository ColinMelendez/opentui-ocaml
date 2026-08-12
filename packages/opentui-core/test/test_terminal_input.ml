open Windtrap
module Parser = Opentui_core.Lib.Stdin_parser
module Key = Opentui_core.Lib.Key_decoder
module Mouse = Opentui_core.Lib.Mouse_decoder

let parser_create () =
  match Parser.create () with
  | Ok parser -> parser
  | Error error -> fail (Parser.message error)

let push parser text =
  let source = Bytes.of_string text in
  match Parser.push_bytes parser ~source ~off:0 ~len:(Bytes.length source) with
  | Ok () -> ()
  | Error error -> fail (Parser.message error)

let read parser =
  match Parser.read parser with
  | Some event -> event
  | None -> fail "expected a parser event"

let () =
  run "opentui-core-input"
    [
      test "the parser emits typed key and mouse events" (fun () ->
          let parser = parser_create () in
          push parser "A";
          (match read parser with
          | Parser.Key { raw; key = Key.Character bytes; modifiers } ->
              equal string "A" (Bytes.to_string raw);
              equal string "A" (Bytes.to_string bytes);
              equal bool true modifiers.Key.shift
          | _ -> fail "expected a typed character key");
          push parser "\x1b[<0;6;6M";
          (match read parser with
          | Parser.Mouse { raw; encoding = Mouse.Sgr; event } -> (
              equal string "\x1b[<0;6;6M" (Bytes.to_string raw);
              match event.Mouse.kind with
              | Mouse.Down -> ()
              | _ -> fail "expected a mouse down")
          | _ -> fail "expected a typed mouse event");
          push parser "\x1b[<32;8;6M";
          (match read parser with
          | Parser.Mouse { event; _ } -> (
              equal int 7 event.Mouse.x;
              match event.Mouse.kind with
              | Mouse.Drag -> ()
              | _ -> fail "expected a mouse drag")
          | _ -> fail "expected a typed mouse drag");
          match Parser.read parser with
          | None -> ()
          | Some _ -> fail "typed event parser retained an extra event");
      test "the parser owns opaque response payloads" (fun () ->
          let parser = parser_create () in
          let raw = Bytes.of_string "\x1b[1;1R" in
          (match
             Parser.push_bytes parser ~source:raw ~off:0 ~len:(Bytes.length raw)
           with
          | Ok () -> ()
          | Error error -> fail (Parser.message error));
          Bytes.set_uint8 raw 0 0;
          match read parser with
          | Parser.Response { bytes; _ } ->
              equal string "\x1b[1;1R" (Bytes.to_string bytes)
          | _ -> fail "expected an opaque response");
      test "unsupported key parameters remain responses" (fun () ->
          let parser = parser_create () in
          push parser "\x1b[27;1;4611686018427387904~";
          match read parser with
          | Parser.Response { protocol = Parser.Csi; bytes } ->
              equal string "\x1b[27;1;4611686018427387904~"
                (Bytes.to_string bytes)
          | _ -> fail "expected an opaque CSI response");
      test "reset clears parser-owned mouse state" (fun () ->
          let parser = parser_create () in
          push parser "\x1b[<0;6;6M";
          ignore (read parser);
          Parser.reset parser;
          push parser "\x1b[<32;8;6M";
          match read parser with
          | Parser.Mouse { event; _ } -> (
              match event.Mouse.kind with
              | Mouse.Move -> ()
              | _ -> fail "expected reset mouse state to produce motion")
          | _ -> fail "expected a mouse event after reset");
      test "the parser keeps paste events distinct" (fun () ->
          let parser = parser_create () in
          push parser "\x1b[200~";
          let payload = Bytes.of_string "paste" in
          (match
             Parser.push_bytes parser ~source:payload ~off:0
               ~len:(Bytes.length payload)
           with
          | Ok () -> ()
          | Error error -> fail (Parser.message error));
          Bytes.set_uint8 payload 0 0;
          push parser "\x1b[201~";
          match read parser with
          | Parser.Paste actual -> equal string "paste" (Bytes.to_string actual)
          | _ -> fail "expected a paste event");
    ]
