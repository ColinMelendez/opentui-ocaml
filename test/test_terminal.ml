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

let () =
  run "opentui-terminal"
    [
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
            (Parser.push parser ~source ~off:(-1) ~len:1))
    ]
