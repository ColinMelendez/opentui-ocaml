open Windtrap

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_terminal.Byte_queue.message error)

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual ->
      let same_error left right =
        match left, right with
        | Opentui_terminal.Byte_queue.Invalid_capacity,
          Opentui_terminal.Byte_queue.Invalid_capacity -> true
        | Opentui_terminal.Byte_queue.Invalid_range,
          Opentui_terminal.Byte_queue.Invalid_range -> true
        | Opentui_terminal.Byte_queue.Max_capacity,
          Opentui_terminal.Byte_queue.Max_capacity -> true
        | _ -> false
      in
      equal bool true (same_error expected actual)

let byte_array values =
  let result =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      (List.length values)
  in
  List.iteri (fun index value -> Bigarray.Array1.set result index value) values;
  result

let queue_contents queue =
  let result = Bytes.create (Opentui_terminal.Byte_queue.length queue) in
  for index = 0 to Bytes.length result - 1 do
    match Opentui_terminal.Byte_queue.get queue index with
    | Some value -> Bytes.set_uint8 result index value
    | None -> fail "queue index disappeared"
  done;
  result

module Parser = Opentui_terminal.Stdin_parser
module Decoder = Opentui_terminal.Key_decoder
module Mouse = Opentui_terminal.Mouse_decoder
module Size = Opentui_terminal.Terminal_size
module Input = Opentui_terminal.Input_decoder
module Events = Opentui_terminal.Event_queue

let parser_create ?initial_capacity ?max_pending_bytes ?timeout_ms () =
  match Parser.create ?initial_capacity ?max_pending_bytes ?timeout_ms () with
  | Ok parser -> parser
  | Error error -> fail (Parser.message error)

let push_string parser value =
  match
    Parser.push_bytes parser ~source:(Bytes.of_string value) ~off:0
      ~len:(String.length value)
  with
  | Ok () -> ()
  | Error error -> fail (Parser.message error)

let expect_no_event parser =
  match Parser.read parser with
  | None -> ()
  | Some _ -> fail "unexpected parser event"

let expect_key parser expected =
  match Parser.read parser with
  | Some (Parser.Key actual) ->
      equal string expected (Bytes.to_string actual)
  | Some _ -> fail "expected a key event"
  | None -> fail "expected a key event, but the parser queue was empty"

let same_protocol left right =
  match left, right with
  | Parser.Csi, Parser.Csi
  | Parser.Ss3, Parser.Ss3
  | Parser.Osc, Parser.Osc
  | Parser.Dcs, Parser.Dcs
  | Parser.Apc, Parser.Apc
  | Parser.Unknown, Parser.Unknown -> true
  | _ -> false

let expect_sequence parser protocol expected =
  match Parser.read parser with
  | Some (Parser.Sequence { protocol = actual_protocol; bytes }) ->
      equal bool true (same_protocol protocol actual_protocol);
      equal string expected (Bytes.to_string bytes)
  | Some _ -> fail "expected a protocol sequence"
  | None -> fail "expected a protocol sequence, but the parser queue was empty"

let expect_paste parser expected =
  match Parser.read parser with
  | Some (Parser.Paste actual) ->
      equal string expected (Bytes.to_string actual)
  | Some _ -> fail "expected a paste event"
  | None -> fail "expected a paste event, but the parser queue was empty"

let expect_paste_bytes parser expected =
  match Parser.read parser with
  | Some (Parser.Paste actual) -> equal bool true (Bytes.equal expected actual)
  | Some _ -> fail "expected a paste event"
  | None -> fail "expected a paste event, but the parser queue was empty"

let expect_parser_error expected result =
  let same_error left right =
    match left, right with
    | Parser.Invalid_timeout, Parser.Invalid_timeout -> true
    | Parser.Queue_error Opentui_terminal.Byte_queue.Invalid_capacity,
      Parser.Queue_error Opentui_terminal.Byte_queue.Invalid_capacity -> true
    | Parser.Queue_error Opentui_terminal.Byte_queue.Invalid_range,
      Parser.Queue_error Opentui_terminal.Byte_queue.Invalid_range -> true
    | Parser.Queue_error Opentui_terminal.Byte_queue.Max_capacity,
      Parser.Queue_error Opentui_terminal.Byte_queue.Max_capacity -> true
    | _ -> false
  in
  match result with
  | Ok _ -> fail "expected a parser error"
  | Error actual -> equal bool true (same_error expected actual)

let expect_modifiers ~shift ~meta ~ctrl actual =
  equal bool shift actual.Decoder.shift;
  equal bool meta actual.Decoder.meta;
  equal bool ctrl actual.Decoder.ctrl

let expect_named event expected_name ~shift ~meta ~ctrl =
  match event with
  | Decoder.Key { key = Decoder.Named actual; modifiers } ->
      equal string expected_name (Decoder.named_key_name actual);
      expect_modifiers ~shift ~meta ~ctrl modifiers
  | Decoder.Key { key = Decoder.Character _; modifiers = _ } ->
      fail "expected a named key"
  | Decoder.Sequence _ -> fail "expected a semantic key, got a sequence"
  | Decoder.Paste _ -> fail "expected a semantic key, got paste"

let expect_character event expected_text ~shift ~meta ~ctrl =
  match event with
  | Decoder.Key { key = Decoder.Character actual; modifiers } ->
      equal string expected_text (Bytes.to_string actual);
      expect_modifiers ~shift ~meta ~ctrl modifiers
  | Decoder.Key { key = Decoder.Named _; modifiers = _ } ->
      fail "expected a character key"
  | Decoder.Sequence _ -> fail "expected a semantic key, got a sequence"
  | Decoder.Paste _ -> fail "expected a semantic key, got paste"

let expect_decoded_sequence event protocol expected =
  match event with
  | Decoder.Sequence { protocol = actual_protocol; bytes } ->
      equal bool true (same_protocol protocol actual_protocol);
      equal string expected (Bytes.to_string bytes)
  | Decoder.Key _ -> fail "expected an undecoded sequence"
  | Decoder.Paste _ -> fail "expected an undecoded sequence, got paste"

let read_parser_event parser =
  match Parser.read parser with
  | Some event -> event
  | None -> fail "expected a parser event"

let mouse_sequence text =
  Parser.Sequence { protocol = Parser.Csi; bytes = Bytes.of_string text }

let x10_sequence ~button_code ~x ~y =
  let bytes = Bytes.create 6 in
  Bytes.set_uint8 bytes 0 0x1b;
  Bytes.set_uint8 bytes 1 0x5b;
  Bytes.set_uint8 bytes 2 0x4d;
  Bytes.set_uint8 bytes 3 (button_code + 0x20);
  Bytes.set_uint8 bytes 4 (x + 0x21);
  Bytes.set_uint8 bytes 5 (y + 0x21);
  Parser.Sequence { protocol = Parser.Csi; bytes }

let read_mouse decoder text =
  match Mouse.decode decoder (mouse_sequence text) with
  | Some event -> event
  | None -> fail "expected a mouse event"

let same_mouse_kind left right =
  match left, right with
  | Mouse.Down, Mouse.Down
  | Mouse.Up, Mouse.Up
  | Mouse.Move, Mouse.Move
  | Mouse.Drag, Mouse.Drag
  | Mouse.Scroll, Mouse.Scroll -> true
  | _ -> false

let expect_mouse event ~kind ~button ~x ~y ~shift ~alt ~ctrl =
  equal bool true (same_mouse_kind kind event.Mouse.kind);
  equal int button event.Mouse.button;
  equal int x event.Mouse.x;
  equal int y event.Mouse.y;
  equal bool shift event.Mouse.modifiers.Mouse.shift;
  equal bool alt event.Mouse.modifiers.Mouse.alt;
  equal bool ctrl event.Mouse.modifiers.Mouse.ctrl

let expect_scroll event direction delta =
  match event.Mouse.scroll with
  | Some scroll ->
      let same_direction left right =
        match left, right with
        | Mouse.Scroll_up, Mouse.Scroll_up
        | Mouse.Scroll_down, Mouse.Scroll_down
        | Mouse.Scroll_left, Mouse.Scroll_left
        | Mouse.Scroll_right, Mouse.Scroll_right -> true
        | _ -> false
      in
      equal bool true (same_direction direction scroll.Mouse.direction);
      equal int delta scroll.Mouse.delta
  | None -> fail "expected mouse scroll details"

let () =
  run "opentui-terminal"
    [
      test "terminal size validates positive columns and rows" (fun () ->
          let size =
            match Size.create ~columns:80 ~rows:24 with
            | Ok value -> value
            | Error error -> fail (Size.message error)
          in
          equal int 80 (Size.columns size);
          equal int 24 (Size.rows size);
          let same_size =
            match Size.create ~columns:80 ~rows:24 with
            | Ok value -> value
            | Error error -> fail (Size.message error)
          in
          equal bool true (Size.equal size same_size);
          (match Size.create ~columns:0 ~rows:24 with
          | Error Size.Invalid_dimensions -> ()
          | Ok _ -> fail "zero columns were accepted");
          match Size.create ~columns:80 ~rows:(-1) with
          | Error Size.Invalid_dimensions -> ()
          | Ok _ -> fail "negative rows were accepted");
      test "event handoff preserves input order and latest resize" (fun () ->
          let queue =
            match Events.create ~capacity:2 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let modifiers =
            { Decoder.shift = false; meta = false; ctrl = false }
          in
          let input =
            Events.Input
              (Input.Key { key = Decoder.Named Decoder.Return; modifiers })
          in
          let first_size =
            match Size.create ~columns:80 ~rows:24 with
            | Ok value -> value
            | Error error -> fail (Size.message error)
          in
          let latest_size =
            match Size.create ~columns:100 ~rows:40 with
            | Ok value -> value
            | Error error -> fail (Size.message error)
          in
          (match Events.push queue input with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          (match Events.push queue (Events.Resize first_size) with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          (match Events.push queue (Events.Resize latest_size) with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          equal int 2 (Events.length queue);
          (match Events.read queue with
          | Some
              (Events.Input
                (Input.Key
                  {
                    key = Decoder.Named Decoder.Return;
                    modifiers = actual;
                  })) ->
              expect_modifiers ~shift:false ~meta:false ~ctrl:false actual
          | Some _ -> fail "resize coalescing changed input order"
          | None -> fail "input event was lost");
          (match Events.read queue with
          | Some (Events.Resize actual) ->
              equal bool true (Size.equal latest_size actual)
          | Some _ -> fail "expected the coalesced resize event"
          | None -> fail "resize event was lost");
          match Events.read queue with
          | None -> ()
          | Some _ -> fail "event handoff contained an extra event");
      test "event handoff reports lossless overflow and coalesces motion" (fun () ->
          let queue =
            match Events.create ~capacity:1 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let modifiers =
            { Decoder.shift = false; meta = false; ctrl = false }
          in
          let key key = Events.Input (Input.Key { key; modifiers }) in
          (match Events.push queue (key (Decoder.Named Decoder.Return)) with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          (match Events.push queue (key (Decoder.Named Decoder.Tab)) with
          | Error Events.Full -> ()
          | Error Events.Invalid_capacity -> fail "unexpected capacity error"
          | Ok () -> fail "lossless input overflow was accepted");
          equal int 1 (Events.length queue);
          let motion_queue =
            match Events.create ~capacity:2 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let first_motion =
            {
              Mouse.kind = Mouse.Drag;
              button = 0;
              x = 1;
              y = 2;
              modifiers =
                { Mouse.shift = false; alt = false; ctrl = false };
              scroll = None;
            }
          in
          let latest_motion =
            {
              Mouse.kind = Mouse.Move;
              button = 0;
              x = 9;
              y = 10;
              modifiers = { Mouse.shift = true; alt = false; ctrl = false };
              scroll = None;
            }
          in
          (match
             Events.push motion_queue (Events.Input (Input.Mouse first_motion))
           with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          (match
             Events.push motion_queue (key (Decoder.Named Decoder.Tab))
           with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          let second_drag =
            {
              first_motion with
              x = 4;
              y = 5;
            }
          in
          (match
             Events.push motion_queue (Events.Input (Input.Mouse second_drag))
           with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          (match
             Events.push motion_queue (Events.Input (Input.Mouse latest_motion))
           with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          equal int 2 (Events.length motion_queue);
          (match Events.read motion_queue with
          | Some (Events.Input (Input.Mouse actual)) ->
              expect_mouse actual ~kind:Mouse.Move ~button:0 ~x:9 ~y:10
                ~shift:true ~alt:false ~ctrl:false
          | Some _ -> fail "expected the coalesced motion event"
          | None -> fail "motion event was lost");
          match Events.read motion_queue with
          | Some
              (Events.Input
                (Input.Key
                  { key = Decoder.Named Decoder.Tab; modifiers = actual })) ->
              expect_modifiers ~shift:false ~meta:false ~ctrl:false actual
          | Some _ -> fail "motion coalescing changed the following event"
          | None -> fail "following input event was lost");
      test "event handoff clear releases every pending event" (fun () ->
          let queue =
            match Events.create ~capacity:2 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let size =
            match Size.create ~columns:80 ~rows:24 with
            | Ok value -> value
            | Error error -> fail (Size.message error)
          in
          (match Events.push queue (Events.Resize size) with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          equal int 1 (Events.length queue);
          Events.clear queue;
          equal int 0 (Events.length queue);
          match Events.read queue with
          | None -> ()
          | Some _ -> fail "clear left a pending event");
      test "event handoff validates capacity and wraps FIFO order" (fun () ->
          (match Events.create ~capacity:0 () with
          | Error Events.Invalid_capacity -> ()
          | Error Events.Full -> fail "zero capacity reported as full"
          | Ok _ -> fail "zero capacity was accepted");
          (match Events.create ~capacity:(-1) () with
          | Error Events.Invalid_capacity -> ()
          | Error Events.Full -> fail "negative capacity reported as full"
          | Ok _ -> fail "negative capacity was accepted");
          let queue =
            match Events.create ~capacity:2 () with
            | Ok value -> value
            | Error error -> fail (Events.message error)
          in
          let modifiers =
            { Decoder.shift = false; meta = false; ctrl = false }
          in
          let key named =
            Events.Input (Input.Key { key = Decoder.Named named; modifiers })
          in
          equal int 2 (Events.capacity queue);
          (match Events.push queue (key Decoder.Return) with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          (match Events.push queue (key Decoder.Tab) with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          (match Events.read queue with
          | Some
              (Events.Input
                (Input.Key
                  { key = Decoder.Named Decoder.Return; modifiers = actual })) ->
              expect_modifiers ~shift:false ~meta:false ~ctrl:false actual
          | Some _ -> fail "unexpected first wrapped event"
          | None -> fail "first wrapped event was lost");
          (match Events.push queue (key Decoder.Backspace) with
          | Ok () -> ()
          | Error error -> fail (Events.message error));
          (match Events.read queue with
          | Some
              (Events.Input
                (Input.Key
                  { key = Decoder.Named Decoder.Tab; modifiers = actual })) ->
              expect_modifiers ~shift:false ~meta:false ~ctrl:false actual
          | Some _ -> fail "ring wrap changed FIFO order"
          | None -> fail "second wrapped event was lost");
          match Events.read queue with
          | Some
              (Events.Input
                (Input.Key
                  {
                    key = Decoder.Named Decoder.Backspace;
                    modifiers = actual;
                  })) ->
              expect_modifiers ~shift:false ~meta:false ~ctrl:false actual
          | Some _ -> fail "ring wrap lost the newest event"
          | None -> fail "newest wrapped event was lost");
      test "bigarray input, consume, and compaction preserve byte order" (fun () ->
          let module Queue = Opentui_terminal.Byte_queue in
          let queue =
            expect_ok (Queue.create ~initial_capacity:4 ~max_capacity:8 ())
          in
          ignore
            (expect_ok
               (Queue.append queue ~source:(byte_array [ 48; 49; 50; 51 ]) ~off:0
                  ~len:4));
          equal int 4 (Queue.length queue);
          equal int 4 (Queue.capacity queue);
          ignore (expect_ok (Queue.consume queue 2));
          ignore
            (expect_ok
               (Queue.append_bytes queue ~source:(Bytes.of_string "45") ~off:0
                  ~len:2));
          equal string "2345" (Bytes.to_string (queue_contents queue));
          equal int 4 (Queue.capacity queue);
          (match Queue.get queue (-1), Queue.get queue 4 with
          | None, None -> ()
          | _ -> fail "out-of-range reads were accepted"));
      test "growth is bounded and a rejected append is atomic" (fun () ->
          let module Queue = Opentui_terminal.Byte_queue in
          let queue =
            expect_ok (Queue.create ~initial_capacity:2 ~max_capacity:8 ())
          in
          ignore
            (expect_ok
               (Queue.append_bytes queue ~source:(Bytes.of_string "abcde")
                  ~off:0 ~len:5));
          equal int 8 (Queue.capacity queue);
          equal string "abcde" (Bytes.to_string (queue_contents queue));
          expect_error Queue.Max_capacity
            (Queue.append_bytes queue ~source:(Bytes.of_string "fghi") ~off:0
               ~len:4);
          equal string "abcde" (Bytes.to_string (queue_contents queue));
          equal int 5 (Queue.length queue));
      test "partial consumption compacts to reuse a leading hole" (fun () ->
          let module Queue = Opentui_terminal.Byte_queue in
          let queue =
            expect_ok (Queue.create ~initial_capacity:4 ~max_capacity:8 ())
          in
          ignore
            (expect_ok
               (Queue.append_bytes queue ~source:(Bytes.of_string "abcd")
                  ~off:0 ~len:4));
          ignore (expect_ok (Queue.consume queue 1));
          ignore
            (expect_ok
               (Queue.append_bytes queue ~source:(Bytes.of_string "e") ~off:0
                  ~len:1));
          equal string "bcde" (Bytes.to_string (queue_contents queue));
          equal int 4 (Queue.capacity queue));
      test "invalid capacities and ranges are structured errors" (fun () ->
          let module Queue = Opentui_terminal.Byte_queue in
          expect_error Queue.Invalid_capacity
            (Queue.create ~initial_capacity:0 ());
          expect_error Queue.Invalid_capacity
            (Queue.create ~initial_capacity:9 ~max_capacity:8 ());
          let queue = expect_ok (Queue.create ()) in
          let source = byte_array [ 1; 2; 3 ] in
          expect_error Queue.Invalid_range
            (Queue.append queue ~source ~off:(-1) ~len:1);
          expect_error Queue.Invalid_range
            (Queue.append queue ~source ~off:2 ~len:2);
          expect_error Queue.Invalid_range (Queue.consume queue 1);
          equal int 0 (Queue.length queue);
          ignore (expect_ok (Queue.append queue ~source ~off:0 ~len:0));
          equal int 0 (Queue.length queue));
      test "stdin framing preserves split UTF-8 and protocol boundaries" (fun () ->
          let parser = parser_create () in
          push_string parser "a";
          expect_key parser "a";
          push_string parser "\xc3";
          expect_no_event parser;
          push_string parser "\xa9";
          expect_key parser "é";
          push_string parser "\x1b[";
          expect_no_event parser;
          push_string parser "A";
          expect_sequence parser Parser.Csi "\x1b[A";
          push_string parser "\x1b[";
          push_string parser "[";
          expect_no_event parser;
          push_string parser "A";
          expect_sequence parser Parser.Csi "\x1b[[A";
          push_string parser "\x1bO";
          expect_no_event parser;
          push_string parser "P";
          expect_sequence parser Parser.Ss3 "\x1bOP");
      test "semantic key decoding stays above framing" (fun () ->
          let parser = parser_create () in
          push_string parser "A";
          expect_character (Decoder.decode (read_parser_event parser)) "A"
            ~shift:true ~meta:false ~ctrl:false;
          push_string parser "\x01";
          expect_character (Decoder.decode (read_parser_event parser)) "a"
            ~shift:false ~meta:false ~ctrl:true;
          push_string parser "\r";
          expect_named (Decoder.decode (read_parser_event parser)) "return"
            ~shift:false ~meta:false ~ctrl:false;
          push_string parser "\x1b[1;5A";
          expect_named (Decoder.decode (read_parser_event parser)) "up"
            ~shift:false ~meta:false ~ctrl:true;
          push_string parser "\x1b[27;5;13~";
          expect_named (Decoder.decode (read_parser_event parser)) "return"
            ~shift:false ~meta:false ~ctrl:true;
          push_string parser "\x1b[27;5;65~";
          expect_character (Decoder.decode (read_parser_event parser)) "A"
            ~shift:false ~meta:false ~ctrl:true;
          push_string parser "\x1b[3~";
          expect_named (Decoder.decode (read_parser_event parser)) "delete"
            ~shift:false ~meta:false ~ctrl:false;
          push_string parser "\x1b[Z";
          expect_named (Decoder.decode (read_parser_event parser)) "tab"
            ~shift:true ~meta:false ~ctrl:false;
          push_string parser "\x1bOP";
          expect_named (Decoder.decode (read_parser_event parser)) "f1"
            ~shift:false ~meta:false ~ctrl:false;
          push_string parser "\x1b[[5~";
          expect_named (Decoder.decode (read_parser_event parser)) "pageup"
            ~shift:false ~meta:false ~ctrl:false;
          push_string parser "\x1b[1;1R";
          expect_decoded_sequence (Decoder.decode (read_parser_event parser))
            Parser.Csi "\x1b[1;1R";
          push_string parser "\x1bf";
          expect_character (Decoder.decode (read_parser_event parser)) "f"
            ~shift:false ~meta:true ~ctrl:false;
          push_string parser "\x1b\x1b[A";
          expect_named (Decoder.decode (read_parser_event parser)) "up"
            ~shift:false ~meta:true ~ctrl:false;
          push_string parser "\x1b\x1bOA";
          expect_named (Decoder.decode (read_parser_event parser)) "up"
            ~shift:false ~meta:true ~ctrl:false;
          push_string parser "\x1b[1;9A";
          expect_decoded_sequence (Decoder.decode (read_parser_event parser))
            Parser.Csi "\x1b[1;9A");
      test "semantic decoding preserves unknown protocol ownership" (fun () ->
          let raw = Bytes.of_string "\x1b[M !\"" in
          let decoded =
            Decoder.decode
              (Parser.Sequence { protocol = Parser.Csi; bytes = raw })
          in
          Bytes.set_uint8 raw 0 0;
          expect_decoded_sequence decoded Parser.Csi "\x1b[M !\"";
          let paste = Bytes.of_string "paste" in
          let decoded_paste = Decoder.decode (Parser.Paste paste) in
          Bytes.set_uint8 paste 0 0;
          match decoded_paste with
          | Decoder.Paste actual -> equal string "paste" (Bytes.to_string actual)
          | Decoder.Key _ -> fail "expected decoded paste"
          | Decoder.Sequence _ -> fail "expected decoded paste");
      test "stdin framing recognizes split opaque responses" (fun () ->
          let parser = parser_create () in
          push_string parser "\x1b]title";
          expect_no_event parser;
          push_string parser "\x07";
          expect_sequence parser Parser.Osc "\x1b]title\x07";
          push_string parser "\x1bPpayload\x1b";
          expect_no_event parser;
          push_string parser "\\";
          expect_sequence parser Parser.Dcs "\x1bPpayload\x1b\\";
          push_string parser "\x1b]title\x1b";
          expect_no_event parser;
          push_string parser "\\";
          expect_sequence parser Parser.Osc "\x1b]title\x1b\\";
          push_string parser "\x1b_payload\x1b\\";
          expect_sequence parser Parser.Apc "\x1b_payload\x1b\\");
      test "X10 mouse bytes stay in one CSI frame" (fun () ->
          let parser = parser_create () in
          let first = byte_array [ 0x1b; 0x5b; 0x4d ] in
          let second = byte_array [ 0x20; 0x21; 0x22 ] in
          (match Parser.push parser ~source:first ~off:0 ~len:3 with
          | Ok () -> ()
          | Error error -> fail (Parser.message error));
          expect_no_event parser;
          (match Parser.push parser ~source:second ~off:0 ~len:3 with
          | Ok () -> ()
          | Error error -> fail (Parser.message error));
          match Parser.read parser with
          | Some (Parser.Sequence { protocol = Parser.Csi; bytes }) ->
              equal bool true
                (Bytes.equal bytes (Bytes.of_string "\x1b[M !\""))
          | Some _ -> fail "expected a CSI sequence"
          | None -> fail "expected an X10 CSI sequence");
      test "timeout flushes a lone escape and an incomplete sequence" (fun () ->
          let parser = parser_create () in
          push_string parser "\x1b";
          expect_no_event parser;
          Parser.flush_timeout parser;
          expect_key parser "\x1b";
          push_string parser "\x1b[12";
          expect_no_event parser;
          Parser.flush_timeout parser;
          expect_sequence parser Parser.Unknown "\x1b[12");
      test "timeout state does not leak through bracketed paste" (fun () ->
          let parser = parser_create () in
          push_string parser "\x1b[";
          Parser.flush_timeout parser;
          expect_sequence parser Parser.Unknown "\x1b[";
          push_string parser "\x1b[200~body\x1b[201~\x1b[";
          expect_paste parser "body";
          expect_no_event parser;
          Parser.flush_timeout parser;
          expect_sequence parser Parser.Unknown "\x1b[");
      test "delayed mouse continuations recover a timed-out escape" (fun () ->
          let parser = parser_create () in
          push_string parser "\x1b";
          Parser.flush_timeout parser;
          expect_key parser "\x1b";
          push_string parser "[<0;1;2";
          expect_no_event parser;
          push_string parser "M";
          expect_sequence parser Parser.Csi "\x1b[<0;1;2M";
          push_string parser "\x1b";
          Parser.flush_timeout parser;
          expect_key parser "\x1b";
          push_string parser "[M !\"";
          expect_sequence parser Parser.Csi "\x1b[M !\"";
          push_string parser "\x1b";
          Parser.flush_timeout parser;
          expect_key parser "\x1b";
          push_string parser "[A";
          expect_key parser "[";
          expect_key parser "A";
          expect_no_event parser);
      test "timeout drains buffered UTF-8 continuation bytes" (fun () ->
          let parser = parser_create () in
          push_string parser "\xe0\x80";
          expect_no_event parser;
          Parser.flush_timeout parser;
          expect_key parser "\xe0";
          expect_key parser "\x80";
          expect_no_event parser);
      test "bracketed paste is split-safe and returns trailing input" (fun () ->
          let parser = parser_create () in
          push_string parser "\x1b[2";
          expect_no_event parser;
          push_string parser "00~hello\x1b[20";
          expect_no_event parser;
          push_string parser "1~z";
          expect_paste parser "hello";
          expect_key parser "z";
          expect_no_event parser);
      test "paste body does not retain caller byte storage" (fun () ->
          let parser = parser_create () in
          push_string parser "\x1b[200~";
          let source = Bytes.of_string "hello" in
          (match Parser.push_bytes parser ~source ~off:0 ~len:5 with
          | Ok () -> ()
          | Error error -> fail (Parser.message error));
          Bytes.fill source 0 5 'x';
          push_string parser "\x1b[201~";
          expect_paste parser "hello");
      test "large paste bypasses the bounded protocol prefix queue" (fun () ->
          let parser =
            parser_create ~initial_capacity:8 ~max_pending_bytes:32 ()
          in
          let payload = Bytes.make 10000 'x' in
          push_string parser "\x1b[200~";
          (match Parser.push_bytes parser ~source:payload ~off:0 ~len:10000 with
          | Ok () -> ()
          | Error error -> fail (Parser.message error));
          push_string parser "\x1b[201~";
          expect_paste_bytes parser payload;
          equal int 8 (Parser.buffer_capacity parser));
      test "pending overflow becomes an owned opaque sequence" (fun () ->
          let parser =
            parser_create ~initial_capacity:2 ~max_pending_bytes:4 ()
          in
          push_string parser "\x1b[12";
          equal int 4 (Parser.pending_bytes parser);
          push_string parser "3";
          expect_sequence parser Parser.Unknown "\x1b[12";
          expect_key parser "3";
          expect_no_event parser);
      test "parser options and source ranges fail structurally" (fun () ->
          expect_parser_error Parser.Invalid_timeout
            (Parser.create ~timeout_ms:0 ());
          expect_parser_error
            (Parser.Queue_error
               Opentui_terminal.Byte_queue.Invalid_capacity)
            (Parser.create ~initial_capacity:8 ~max_pending_bytes:4 ());
          let parser = parser_create () in
          let source = byte_array [ 1; 2 ] in
          expect_parser_error
            (Parser.Queue_error Opentui_terminal.Byte_queue.Invalid_range)
            (Parser.push parser ~source ~off:(-1) ~len:1));
      test "SGR mouse decoding preserves modifiers and coordinates" (fun () ->
          let decoder = Mouse.create () in
          let event = read_mouse decoder "\x1b[<28;11;6M" in
          expect_mouse event ~kind:Mouse.Down ~button:0 ~x:10 ~y:5 ~shift:true
            ~alt:true ~ctrl:true);
      test "SGR mouse state classifies drag and reset release" (fun () ->
          let decoder = Mouse.create () in
          ignore (read_mouse decoder "\x1b[<0;6;6M");
          let drag = read_mouse decoder "\x1b[<32;8;6M" in
          expect_mouse drag ~kind:Mouse.Drag ~button:0 ~x:7 ~y:5 ~shift:false
            ~alt:false ~ctrl:false;
          let release = read_mouse decoder "\x1b[<0;8;6m" in
          expect_mouse release ~kind:Mouse.Up ~button:0 ~x:7 ~y:5 ~shift:false
            ~alt:false ~ctrl:false;
          let move = read_mouse decoder "\x1b[<35;9;6M" in
          expect_mouse move ~kind:Mouse.Move ~button:0 ~x:8 ~y:5 ~shift:false
            ~alt:false ~ctrl:false;
          Mouse.reset decoder;
          let reset_move = read_mouse decoder "\x1b[<32;9;6M" in
          expect_mouse reset_move ~kind:Mouse.Move ~button:0 ~x:8 ~y:5
            ~shift:false ~alt:false ~ctrl:false);
      test "SGR release clears every pressed button" (fun () ->
          let decoder = Mouse.create () in
          ignore (read_mouse decoder "\x1b[<0;6;6M");
          ignore (read_mouse decoder "\x1b[<2;6;6M");
          ignore (read_mouse decoder "\x1b[<0;6;6m");
          let move = read_mouse decoder "\x1b[<32;9;6M" in
          expect_mouse move ~kind:Mouse.Move ~button:0 ~x:8 ~y:5 ~shift:false
            ~alt:false ~ctrl:false);
      test "SGR mouse scroll keeps direction and motion precedence" (fun () ->
          let decoder = Mouse.create () in
          let scroll = read_mouse decoder "\x1b[<65;11;6M" in
          expect_mouse scroll ~kind:Mouse.Scroll ~button:1 ~x:10 ~y:5
            ~shift:false ~alt:false ~ctrl:false;
          expect_scroll scroll Mouse.Scroll_down 1;
          let motion = read_mouse decoder "\x1b[<96;11;6M" in
          expect_mouse motion ~kind:Mouse.Move ~button:0 ~x:10 ~y:5
            ~shift:false ~alt:false ~ctrl:false;
          (match motion.Mouse.scroll with
          | None -> ()
          | Some _ -> fail "motion must not carry scroll details");
          let release = read_mouse decoder "\x1b[<64;11;6m" in
          expect_mouse release ~kind:Mouse.Up ~button:0 ~x:10 ~y:5
            ~shift:false ~alt:false ~ctrl:false;
          (match release.Mouse.scroll with
          | None -> ()
          | Some _ -> fail "scroll release must not carry scroll details"));
      test "X10 mouse press, scroll, and motion precedence" (fun () ->
          let decoder = Mouse.create () in
          let down =
            match Mouse.decode decoder (x10_sequence ~button_code:0 ~x:2 ~y:3) with
            | Some event -> event
            | None -> fail "expected an X10 press"
          in
          expect_mouse down ~kind:Mouse.Down ~button:0 ~x:2 ~y:3 ~shift:false
            ~alt:false ~ctrl:false;
          let scroll =
            match Mouse.decode decoder
                    (x10_sequence ~button_code:64 ~x:2 ~y:3) with
            | Some event -> event
            | None -> fail "expected an X10 scroll"
          in
          expect_mouse scroll ~kind:Mouse.Scroll ~button:0 ~x:2 ~y:3
            ~shift:false ~alt:false ~ctrl:false;
          expect_scroll scroll Mouse.Scroll_up 1;
          let motion =
            match Mouse.decode decoder
                    (x10_sequence ~button_code:96 ~x:2 ~y:3) with
            | Some event -> event
            | None -> fail "expected an X10 motion"
          in
          expect_mouse motion ~kind:Mouse.Move ~button:0 ~x:2 ~y:3
            ~shift:false ~alt:false ~ctrl:false;
          (match motion.Mouse.scroll with
          | None -> ()
          | Some _ -> fail "X10 motion must not carry scroll details"));
      test "X10 mouse high coordinates survive framing" (fun () ->
          let decoder = Mouse.create () in
          let parser = parser_create () in
          let source = Bytes.create 6 in
          Bytes.set_uint8 source 0 0x1b;
          Bytes.set_uint8 source 1 0x5b;
          Bytes.set_uint8 source 2 0x4d;
          Bytes.set_uint8 source 3 64;
          Bytes.set_uint8 source 4 128;
          Bytes.set_uint8 source 5 34;
          (match Parser.push_bytes parser ~source ~off:0 ~len:6 with
          | Ok () -> ()
          | Error error -> fail (Parser.message error));
          let event =
            match Parser.read parser with
            | Some parser_event ->
                (match Mouse.decode decoder parser_event with
                | Some event -> event
                | None -> fail "expected an X10 mouse event")
            | None -> fail "expected a framed X10 mouse event"
          in
          expect_mouse event ~kind:Mouse.Move ~button:0 ~x:95 ~y:1
            ~shift:false ~alt:false ~ctrl:false);
      test "non-mouse sequences remain available to other decoders" (fun () ->
          let decoder = Mouse.create () in
          match Mouse.decode decoder (mouse_sequence "\x1b[1;5A") with
          | None -> ()
          | Some _ -> fail "a keyboard CSI sequence was decoded as mouse")
    ]
