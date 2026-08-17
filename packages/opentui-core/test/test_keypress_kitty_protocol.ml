open Windtrap

module Decoder = Opentui_core.Lib.Key_decoder
module Parser = Opentui_core.Lib.Stdin_parser

let parser_create () =
  match Parser.create () with
  | Ok value -> value
  | Error error -> fail (Parser.message error)

let push_string parser value =
  match
    Parser.push_bytes parser ~source:(Bytes.of_string value) ~off:0
      ~len:(String.length value)
  with
  | Ok () -> ()
  | Error error -> fail (Parser.message error)

let read_event parser : Parser.event =
  match Parser.read parser with
  | Some event -> event
  | None -> fail "expected a parser event, but the parser queue was empty"

let read_key parser : Parser.event =
  match Parser.read parser with
  | Some event ->
      (match event with
      | Parser.Key _ -> event
      | Parser.Mouse _ -> fail "expected a key event, got mouse"
      | Parser.Paste _ -> fail "expected a key event, got paste"
      | Parser.Response _ -> fail "expected a key event, got protocol response")
  | None -> fail "expected a key event, but the parser queue was empty"

let parse_event sequence =
  let parser = parser_create () in
  push_string parser sequence;
  read_event parser

let parse_keypress sequence =
  let parser = parser_create () in
  push_string parser sequence;
  read_key parser

let expect_metadata event callback =
  match event with
  | Parser.Key { metadata; _ } -> callback metadata
  | Parser.Mouse _ -> fail "expected a key event, got mouse"
  | Parser.Paste _ -> fail "expected a key event, got paste"
  | Parser.Response _ -> fail "expected a key event, got protocol response"

let expect_kitty event =
  expect_metadata event (fun metadata ->
      match metadata.Decoder.source with
      | Decoder.Kitty -> ()
      | Decoder.Raw -> fail "expected Kitty metadata")

let expect_event_type event expected =
  expect_metadata event (fun metadata ->
      match expected, metadata.Decoder.event_type with
      | `Press, Decoder.Press -> ()
      | `Repeat, Decoder.Repeat -> ()
      | `Release, Decoder.Release -> ()
      | `Press, Decoder.Repeat -> fail "expected press event"
      | `Press, Decoder.Release -> fail "expected press event"
      | `Repeat, Decoder.Press -> fail "expected repeat event"
      | `Repeat, Decoder.Release -> fail "expected repeat event"
      | `Release, Decoder.Press -> fail "expected release event"
      | `Release, Decoder.Repeat -> fail "expected release event")

let expect_repeated event expected =
  expect_metadata event (fun metadata ->
      equal bool expected metadata.Decoder.repeated)

let expect_character expected event =
  match event with
  | Parser.Key { key = Decoder.Character value; _ } ->
      equal string expected (Bytes.to_string value)
  | Parser.Key { key = Decoder.Named _; _ } -> fail "expected character key"
  | Parser.Mouse _ -> fail "expected character key, got mouse"
  | Parser.Paste _ -> fail "expected character key, got paste"
  | Parser.Response _ -> fail "expected character key, got protocol response"

let expect_named expected event =
  match event with
  | Parser.Key { key = Decoder.Named actual; _ } ->
      equal string expected (Decoder.named_key_name actual)
  | Parser.Key { key = Decoder.Character _; _ } -> fail "expected named key"
  | Parser.Mouse _ -> fail "expected named key, got mouse"
  | Parser.Paste _ -> fail "expected named key, got paste"
  | Parser.Response _ -> fail "expected named key, got protocol response"

let expect_text expected event =
  expect_metadata event (fun metadata ->
      match metadata.Decoder.text with
      | Some actual -> equal string expected actual
      | None -> fail "expected parsed metadata text")

let expect_base_code expected event =
  expect_metadata event (fun metadata ->
      match metadata.Decoder.base_code with
      | Some actual -> equal int expected actual
      | None -> fail "expected base code metadata")

let expect_code expected event =
  expect_metadata event (fun metadata ->
      match metadata.Decoder.code with
      | Some actual -> equal int expected actual
      | None -> fail "expected code metadata")

let expect_modifiers event ~super ~hyper ~caps_lock ~num_lock =
  expect_metadata event (fun metadata ->
      equal bool super metadata.Decoder.super;
      equal bool hyper metadata.Decoder.hyper;
      equal bool caps_lock metadata.Decoder.caps_lock;
      equal bool num_lock metadata.Decoder.num_lock)

let expect_response sequence event =
  match event with
  | Parser.Response { bytes; _ } -> equal string sequence (Bytes.to_string bytes)
  | Parser.Key _ -> fail "expected malformed Kitty frame to remain a response"
  | Parser.Mouse _ -> fail "expected malformed Kitty frame to remain a response"
  | Parser.Paste _ -> fail "expected malformed Kitty frame to remain a response"

let () =
  run "opentui-core-kitty-protocol"
    [
      test "canonical Kitty character press repeat release frames" (fun () ->
          let press = parse_keypress "\027[97;1:1u" in
          let repeat = parse_keypress "\027[97;1:2u" in
          let release = parse_keypress "\027[97;1:3u" in
          List.iter
            (fun event ->
              expect_kitty event;
              expect_character "a" event)
            [ press; repeat; release ];
          expect_event_type press `Press;
          expect_repeated press false;
          expect_event_type repeat `Repeat;
          expect_repeated repeat true;
          expect_event_type release `Release;
          expect_repeated release false);
      test "Kitty default modifier and event fields retain press behavior" (fun () ->
          List.iter
            (fun sequence ->
              let event = parse_keypress sequence in
              expect_kitty event;
              expect_character "a" event;
              expect_event_type event `Press;
              expect_repeated event false)
            [ "\027[97u"; "\027[97;1u"; "\027[97;1:u" ]);
      test "canonical Kitty functional and tilde special keys" (fun () ->
          let up_press = parse_keypress "\027[1;1:1A" in
          let up_repeat = parse_keypress "\027[1;1:2A" in
          let up_release = parse_keypress "\027[1;1:3A" in
          let page_up = parse_keypress "\027[5;1:1~" in
          List.iter
            (fun event ->
              expect_kitty event;
              expect_named "up" event)
            [ up_press; up_repeat; up_release ];
          expect_event_type up_press `Press;
          expect_event_type up_repeat `Repeat;
          expect_repeated up_repeat true;
          expect_event_type up_release `Release;
          expect_named "pageup" page_up;
          expect_event_type page_up `Press);
      test "Kitty parser records base-code metadata" (fun () ->
          let event = parse_keypress "\027[97::113u" in
          expect_character "a" event;
          expect_code 97 event;
          expect_base_code 113 event;
          expect_text "a" event);
      test "Kitty parser retains every explicit text codepoint" (fun () ->
          let event = parse_keypress "\027[97:98;1;97:98u" in
          expect_character "ab" event;
          expect_text "ab" event);
      test "Kitty parser sets extended modifier metadata bits" (fun () ->
          let event = parse_keypress "\027[97;256u" in
          expect_modifiers event ~super:true ~hyper:true ~caps_lock:true
            ~num_lock:true;
          expect_event_type event `Press);
      test "Kitty parser rejects invalid and empty modifier fields" (fun () ->
          List.iter
            (fun sequence -> expect_response sequence (parse_event sequence))
            [
              "\027[97;:1u";
              "\027[97;;1u";
              "\027[97;-1:1u";
              "\027[97;1:-1u";
              "\027[97;0u";
              "\027[1;:1A";
              "\027[5;;1~";
            ]);
    ]
