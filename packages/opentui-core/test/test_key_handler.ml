open Windtrap

module Core = Opentui_core
module Key_handler = Core.Lib.Key_handler
module Decoder = Core.Lib.Key_decoder
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Parser = Core.Lib.Stdin_parser

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let modifiers = { Decoder.shift = false; meta = false; ctrl = false }

let key_input () =
  Core.Lib.Stdin_parser.Key
    { raw = Bytes.of_string "a"; key = Decoder.Character (Bytes.of_string "a");
      modifiers; metadata = Decoder.raw_metadata }

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

let read_key parser : Parser.event =
  match Parser.read parser with
  | Some event ->
      (match event with
      | Parser.Key _ -> event
      | Parser.Mouse _ -> fail "expected a key event, got mouse"
      | Parser.Paste _ -> fail "expected a key event, got paste"
      | Parser.Response _ -> fail "expected a key event, got protocol response")
  | None -> fail "expected a key event, but parser queue was empty"

let parse_keypress sequence =
  let parser = parser_create () in
  push_string parser sequence;
  read_key parser

let () =
  run "opentui-core-key-handler"
    [
      test "global listeners run before focused listeners" (fun () ->
          let handler = Key_handler.create () in
          let calls = ref [] in
          ignore
            (Key_handler.on_keypress handler (fun _ ->
                 calls := "global" :: !calls));
          let local =
            Key_handler.on_internal_keypress handler ~owner_num:7 (fun _ ->
                calls := "local" :: !calls)
          in
          ignore
            (Key_handler.process_key handler ~raw:(Bytes.of_string "a")
               ~key:(Decoder.Character (Bytes.of_string "a")) ~modifiers ());
          equal string "global,local" (String.concat "," (List.rev !calls));
          Core.Event_subscription.cancel local;
          calls := [];
          ignore
            (Key_handler.process_key handler ~raw:(Bytes.of_string "b")
               ~key:(Decoder.Character (Bytes.of_string "b")) ~modifiers ());
          equal string "global" (String.concat "," (List.rev !calls)));
      test "prevention and propagation preserve the two dispatch phases" (fun () ->
          let handler = Key_handler.create () in
          let calls = ref [] in
          ignore
            (Key_handler.on_keypress handler (fun event ->
                 calls := "first" :: !calls;
                 Key_handler.prevent_default event));
          ignore
            (Key_handler.on_keypress handler (fun _ -> calls := "second" :: !calls));
          ignore
            (Key_handler.on_internal_keypress handler ~owner_num:4 (fun _ ->
                calls := "local" :: !calls));
          ignore
            (Key_handler.process_key handler ~raw:(Bytes.of_string "a")
               ~key:(Decoder.Character (Bytes.of_string "a")) ~modifiers ());
          equal string "first,second" (String.concat "," (List.rev !calls));
          let stopped = Key_handler.create () in
          let stopped_calls = ref [] in
          ignore
            (Key_handler.on_keypress stopped (fun event ->
                 stopped_calls := "first" :: !stopped_calls;
                 Key_handler.stop_propagation event));
          ignore
            (Key_handler.on_keypress stopped (fun _ ->
                stopped_calls := "second" :: !stopped_calls));
          ignore
            (Key_handler.on_internal_keypress stopped ~owner_num:4 (fun _ ->
                stopped_calls := "local" :: !stopped_calls));
          ignore
            (Key_handler.process_key stopped ~raw:(Bytes.of_string "a")
               ~key:(Decoder.Character (Bytes.of_string "a")) ~modifiers ());
          equal string "first" (String.concat "," (List.rev !stopped_calls)));
      test "keyboard callback failures are reported and do not abort dispatch" (fun () ->
          let failures = ref [] in
          let handler =
            Key_handler.create ~on_error:(fun error ->
                let scope =
                  match error.Key_handler.scope with
                  | Key_handler.Global -> "global"
                  | Key_handler.Renderable -> "renderable"
                in
                failures := scope :: !failures) ()
          in
          let calls = ref [] in
          ignore
            (Key_handler.on_keypress handler (fun _ ->
                 raise (Failure "handler failure")));
          ignore
            (Key_handler.on_keypress handler (fun _ -> calls := "second" :: !calls));
          ignore
            (Key_handler.process_key handler ~raw:(Bytes.of_string "a")
               ~key:(Decoder.Character (Bytes.of_string "a")) ~modifiers ());
          equal string "second" (String.concat "," (List.rev !calls));
          equal string "global" (String.concat "," (List.rev !failures)));
      test "keypress, key-release, and paste are distinct dispatch families" (fun () ->
          let handler = Key_handler.create () in
          let calls = ref [] in
          ignore
            (Key_handler.on_keypress handler (fun event ->
                 calls :=
                   (match Key_handler.key_event_kind event with
                   | Key_handler.Keypress -> "keypress"
                   | Key_handler.Keyrelease -> "wrong-release"
                   | Key_handler.Paste -> "wrong-paste")
                   :: !calls));
          ignore
            (Key_handler.on_keyrelease handler (fun event ->
                 calls :=
                   (match Key_handler.key_event_kind event with
                   | Key_handler.Keyrelease -> "keyrelease"
                   | Key_handler.Keypress -> "wrong-press"
                   | Key_handler.Paste -> "wrong-paste")
                   :: !calls));
          ignore
            (Key_handler.on_paste handler (fun event ->
                 calls := Bytes.to_string (Key_handler.paste_raw event) :: !calls));
          ignore
            (Key_handler.process_key handler ~raw:(Bytes.of_string "a")
               ~key:(Decoder.Character (Bytes.of_string "a")) ~modifiers ());
          ignore
            (Key_handler.process_keyrelease handler ~raw:(Bytes.of_string "a")
               ~key:(Decoder.Character (Bytes.of_string "a")) ~modifiers ());
          ignore (Key_handler.process_paste handler (Bytes.of_string "paste"));
          equal string "keypress,keyrelease,paste"
            (String.concat "," (List.rev !calls)));
      test "focus owns internal keyboard registrations" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:4l ~height:2l) in
          let renderable =
            expect_ok
              (Core.Renderables.Box.create (Renderer.context renderer)
                 ~focusable:true ())
          in
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Core.Renderables.Box.as_renderable renderable)));
          let calls = ref 0 in
          ignore
            (expect_ok
               (Renderable.set_on_key_down
                  (Core.Renderables.Box.as_renderable renderable)
                  (Some (fun _ -> calls := !calls + 1))));
          ignore (expect_ok (Core.Renderables.Box.focus renderable));
          ignore (expect_ok (Renderer.handle_input renderer (key_input ())));
          equal int 1 !calls;
          ignore (expect_ok (Core.Renderables.Box.blur renderable));
          ignore (expect_ok (Renderer.handle_input renderer (key_input ())));
          equal int 1 !calls;
          Renderer.destroy renderer);
      test "detaching does not blur a focused renderable" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:4l ~height:2l) in
          let renderable =
            expect_ok
              (Core.Renderables.Box.create (Renderer.context renderer)
                 ~focusable:true ())
          in
          let node = Core.Renderables.Box.as_renderable renderable in
          ignore
            (expect_ok (Core.Layout_children.add (Renderer.children renderer) node));
          let calls = ref 0 in
          ignore
            (expect_ok (Renderable.set_on_key_down node (Some (fun _ -> calls := !calls + 1))));
          ignore (expect_ok (Renderable.focus node));
          ignore (expect_ok (Core.Layout_children.remove (Renderer.children renderer) node));
          ignore (expect_ok (Renderer.handle_input renderer (key_input ())));
          equal int 1 !calls;
          Renderer.destroy renderer);
      test "kitty release events route to on_key_release handlers" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:4l ~height:2l) in
          let renderable =
            expect_ok
              (Core.Renderables.Box.create (Renderer.context renderer)
                 ~focusable:true ())
          in
          let node = Core.Renderables.Box.as_renderable renderable in
          ignore
            (expect_ok (Core.Layout_children.add (Renderer.children renderer) node));
          let keydown_calls = ref 0 in
          let keyup_calls = ref 0 in
          ignore
            (expect_ok
               (Renderable.set_on_key_down node
                  (Some (fun _ -> keydown_calls := !keydown_calls + 1))));
          ignore
            (expect_ok
               (Renderable.set_on_key_release node
                  (Some (fun _ -> keyup_calls := !keyup_calls + 1))));
          ignore (expect_ok (Core.Renderables.Box.focus renderable));
          ignore
            (expect_ok
               (Renderer.handle_input renderer (parse_keypress "\027[97;1u")));
          ignore
            (expect_ok
               (Renderer.handle_input renderer (parse_keypress "\027[97;1:3u")));
          equal int 1 !keydown_calls;
          equal int 1 !keyup_calls;
          Renderer.destroy renderer);
    ]
