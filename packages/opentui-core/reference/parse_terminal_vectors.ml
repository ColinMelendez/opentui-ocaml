module Parser = Opentui_core.Lib.Stdin_parser

let fail message =
  prerr_endline message;
  exit 1

let hex_value value =
  let code = Char.code value in
  if code >= Char.code '0' && code <= Char.code '9' then code - Char.code '0'
  else if code >= Char.code 'a' && code <= Char.code 'f' then
    code - Char.code 'a' + 10
  else if code >= Char.code 'A' && code <= Char.code 'F' then
    code - Char.code 'A' + 10
  else fail (Printf.sprintf "invalid hexadecimal digit: %C" value)

let bytes_of_hex text =
  let length = String.length text in
  if not (Int.equal (length mod 2) 0) then
    fail (Printf.sprintf "hex input has odd length: %S" text);
  let result = Bytes.create (length / 2) in
  for index = 0 to (length / 2) - 1 do
    let high = hex_value (String.get text (index * 2)) in
    let low = hex_value (String.get text ((index * 2) + 1)) in
    Bytes.set_uint8 result index ((high lsl 4) lor low)
  done;
  result

let hex_of_bytes bytes =
  let result = Buffer.create (Bytes.length bytes * 2) in
  for index = 0 to Bytes.length bytes - 1 do
    Buffer.add_string result (Printf.sprintf "%02x" (Bytes.get_uint8 bytes index))
  done;
  Buffer.contents result

let protocol_from_escape bytes =
  if Bytes.length bytes >= 2 && Int.equal (Bytes.get_uint8 bytes 0) 0x1b then
    match Bytes.get_uint8 bytes 1 with
    | 0x5b -> "csi"
    | 0x4f -> "ss3"
    | 0x5d -> "osc"
    | 0x50 -> "dcs"
    | 0x5f -> "apc"
    | _ -> "unknown"
  else "unknown"

let protocol_name protocol bytes =
  match protocol with
  | Parser.Csi -> "csi"
  | Parser.Ss3 -> "ss3"
  | Parser.Osc -> "osc"
  | Parser.Dcs -> "dcs"
  | Parser.Apc -> "apc"
  | Parser.Unknown -> protocol_from_escape bytes

let emit name kind protocol bytes =
  Printf.printf "%s\t%s\t%s\t%s\n%!" name kind protocol (hex_of_bytes bytes)

let emit_event name = function
  | Parser.Key { raw; _ } when Bytes.length raw > 0
                               && Int.equal (Bytes.get_uint8 raw 0) 0x1b ->
      emit name "sequence" (protocol_from_escape raw) raw
  | Parser.Key { raw; _ } -> emit name "key" "ground" raw
  | Parser.Mouse { raw; _ } ->
      emit name "sequence" (protocol_from_escape raw) raw
  | Parser.Response { protocol; bytes } ->
      emit name "sequence" (protocol_name protocol bytes) bytes
  | Parser.Paste bytes -> emit name "paste" "-" bytes

let emit_events name parser =
  let count = ref 0 in
  let next () =
    match Parser.read parser with
    | None -> false
    | Some event ->
        incr count;
        emit_event name event;
        true
  in
  while next () do () done;
  if Int.equal !count 0 then emit name "empty" "-" Bytes.empty

let push_chunk parser chunk =
  let bytes = bytes_of_hex chunk in
  match Parser.push_bytes parser ~source:bytes ~off:0 ~len:(Bytes.length bytes) with
  | Ok () -> ()
  | Error error -> fail (Printf.sprintf "%s: %s" chunk (Parser.message error))

let run_case line =
  match String.split_on_char '\t' line with
  | [ name; flush; chunks ] ->
      if not (String.equal flush "0" || String.equal flush "1") then
        fail (Printf.sprintf "invalid flush flag for %s: %s" name flush);
      let parser =
        match Parser.create () with
        | Ok parser -> parser
        | Error error -> fail (Parser.message error)
      in
      List.iter (push_chunk parser) (String.split_on_char ';' chunks);
      if String.equal flush "1" then Parser.flush_timeout parser;
      emit_events name parser
  | _ -> fail (Printf.sprintf "expected three tab-separated fields: %S" line)

let () =
  try
    while true do
      let raw_line = input_line stdin in
      let line =
        if String.length raw_line > 0
           && Char.equal (String.get raw_line (String.length raw_line - 1)) '\r'
        then String.sub raw_line 0 (String.length raw_line - 1)
        else raw_line
      in
      let trimmed = String.trim line in
      if String.length trimmed > 0 && not (Char.equal (String.get trimmed 0) '#')
      then run_case trimmed
    done
  with End_of_file -> ()
