module Parser = Opentui_core.Lib.Stdin_parser

type workload = {
  name : string;
  workload_version : int;
  pattern_name : string;
  pattern_hex : string;
  events_per_period : int;
  payload_bytes : int;
  chunk_bytes : int;
  expected_events : int;
  chunks : bytes array;
}

type measurement = {
  batch_elapsed_ns : int64 array;
  minor_words : float;
  promoted_words : float;
  major_words : float;
  minor_collections : int;
  major_collections : int;
}

let warmup_batches = 5
let measured_batches = 20
let batch_iterations = 8

let fail message =
  prerr_endline message;
  Stdlib.exit 1

let failf format_string = Printf.ksprintf fail format_string

let int_of_field ~label text =
  match int_of_string_opt text with
  | Some value when Int.compare value 0 > 0 -> value
  | _ -> failf "%s must be a positive integer: %S" label text

let hex_value value =
  let code = Char.code value in
  if code >= Char.code '0' && code <= Char.code '9' then code - Char.code '0'
  else if code >= Char.code 'a' && code <= Char.code 'f' then
    code - Char.code 'a' + 10
  else if code >= Char.code 'A' && code <= Char.code 'F' then
    code - Char.code 'A' + 10
  else failf "invalid hexadecimal digit: %C" value

let bytes_of_hex text =
  let length = String.length text in
  if Int.equal length 0 || not (Int.equal (length mod 2) 0) then
    failf "pattern hex must have a positive even length: %S" text;
  let result = Array.make (length / 2) 0 in
  for index = 0 to Array.length result - 1 do
    let high = hex_value (String.get text (index * 2)) in
    let low = hex_value (String.get text ((index * 2) + 1)) in
    Array.set result index ((high lsl 4) lor low)
  done;
  result

let make_payload bytes length =
  let period = Array.length bytes in
  if not (Int.equal (length mod period) 0) then
    failf "payload length %d is not a multiple of pattern period %d" length period;
  let result = Bytes.create length in
  for offset = 0 to length - 1 do
    Bytes.set_uint8 result offset (Array.get bytes (offset mod period))
  done;
  result

let make_chunks payload ~chunk_bytes =
  let payload_bytes = Bytes.length payload in
  let count = (payload_bytes + chunk_bytes - 1) / chunk_bytes in
  Array.init count (fun chunk_index ->
      let offset = chunk_index * chunk_bytes in
      let length = min chunk_bytes (payload_bytes - offset) in
      Bytes.sub payload offset length)

let workload_of_fields fields =
  match fields with
  | [
      name;
      version;
      pattern_name;
      pattern_hex;
      events;
      payload;
      chunk;
      expected;
    ] ->
      if String.length name = 0 || String.contains name '\t' then
        failf "invalid benchmark name: %S" name;
      let workload_version = int_of_field ~label:"workload version" version in
      if String.length pattern_name = 0 || String.contains pattern_name '\t' then
        failf "invalid benchmark pattern: %S" pattern_name;
      let pattern_bytes = bytes_of_hex pattern_hex in
      let period = Array.length pattern_bytes in
      let events_per_period = int_of_field ~label:"events per period" events in
      let payload_bytes = int_of_field ~label:"payload bytes" payload in
      let chunk_bytes = int_of_field ~label:"chunk bytes" chunk in
      let expected_events = int_of_field ~label:"expected events" expected in
      if not (Int.equal (payload_bytes mod period) 0) then
        failf "%s payload is not aligned to pattern %s" name pattern_name;
      let computed_events = (payload_bytes / period) * events_per_period in
      if not (Int.equal expected_events computed_events) then
        failf "%s expected %d events, pattern produces %d" name expected_events
          computed_events;
      let payload = make_payload pattern_bytes payload_bytes in
      {
        name;
        workload_version;
        pattern_name;
        pattern_hex;
        events_per_period;
        payload_bytes;
        chunk_bytes;
        expected_events;
        chunks = make_chunks payload ~chunk_bytes;
      }
  | _ -> failf "expected eight tab-separated benchmark fields"

let strip_cr line =
  let length = String.length line in
  if Int.compare length 0 > 0 && Char.equal (String.get line (length - 1)) '\r'
  then String.sub line 0 (length - 1)
  else line

let read_manifest path =
  let input = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in input)
    (fun () ->
      let workloads = ref [] in
      (try
         while true do
           let line = String.trim (strip_cr (input_line input)) in
           if String.length line > 0 && not (Char.equal (String.get line 0) '#')
           then workloads := workload_of_fields (String.split_on_char '\t' line) :: !workloads
         done
       with End_of_file -> ());
      List.rev !workloads)

let parser_for_workload workload =
  match Parser.create ~initial_capacity:256 () with
  | Ok parser -> parser
  | Error error ->
      failf "%s: parser construction failed: %s" workload.name
        (Parser.message error)

let run_operation parser workload consume_event =
  for index = 0 to Array.length workload.chunks - 1 do
    let chunk = Array.get workload.chunks index in
    match
      Parser.push_bytes parser ~source:chunk ~off:0 ~len:(Bytes.length chunk)
    with
    | Ok () -> ()
    | Error error ->
        failf "%s: parser push failed: %s" workload.name (Parser.message error)
  done;
  Parser.drain parser consume_event;
  Parser.reset parser

let run_batch parser workload consume_event completed_events =
  let events_before = !completed_events in
  let start = Mtime_clock.elapsed_ns () in
  for _ = 1 to batch_iterations do
    run_operation parser workload consume_event
  done;
  let elapsed = Int64.sub (Mtime_clock.elapsed_ns ()) start in
  let events = !completed_events - events_before in
  let expected = batch_iterations * workload.expected_events in
  if not (Int.equal events expected) then
    failf "%s produced %d events, expected %d" workload.name events expected;
  elapsed

let words_delta before after selector = selector after -. selector before

let measure workload =
  let parser = parser_for_workload workload in
  let completed_events = ref 0 in
  let consume_event = function
    | Parser.Key _ | Parser.Sequence _ | Parser.Paste _ -> incr completed_events
  in
  for _ = 1 to warmup_batches do
    ignore (run_batch parser workload consume_event completed_events)
  done;
  Gc.full_major ();
  let before = Gc.quick_stat () in
  let batch_elapsed_ns =
    Array.init measured_batches (fun _ ->
        run_batch parser workload consume_event completed_events)
  in
  let after = Gc.quick_stat () in
  {
    batch_elapsed_ns;
    minor_words = words_delta before after (fun stat -> stat.Gc.minor_words);
    promoted_words = words_delta before after (fun stat -> stat.Gc.promoted_words);
    major_words = words_delta before after (fun stat -> stat.Gc.major_words);
    minor_collections = after.Gc.minor_collections - before.Gc.minor_collections;
    major_collections = after.Gc.major_collections - before.Gc.major_collections;
  }

let sorted_samples samples =
  let sorted = Array.copy samples in
  Array.sort Int64.compare sorted;
  sorted

let percentile_ns samples percentile =
  let sorted = sorted_samples samples in
  let count = Array.length sorted in
  let rank = ((percentile * count) + 99) / 100 in
  Array.get sorted (max 0 (rank - 1))

let median_ns samples =
  let sorted = sorted_samples samples in
  let count = Array.length sorted in
  let middle = count / 2 in
  if Int.equal (count mod 2) 1 then Int64.to_float (Array.get sorted middle)
  else
    (Int64.to_float (Array.get sorted (middle - 1))
    +. Int64.to_float (Array.get sorted middle))
    /. 2.0

let rsd_ppm samples =
  let count = Array.length samples in
  let total = ref 0.0 in
  Array.iter (fun value -> total := !total +. Int64.to_float value) samples;
  let mean = !total /. float_of_int count in
  let squared = ref 0.0 in
  Array.iter
    (fun value ->
      let delta = Int64.to_float value -. mean in
      squared := !squared +. (delta *. delta))
    samples;
  let standard_deviation = sqrt (!squared /. float_of_int (count - 1)) in
  int_of_float (Float.round ((standard_deviation /. mean) *. 1_000_000.0))

let ns_per_operation value = value /. float_of_int batch_iterations

let words_per_operation words =
  words /. float_of_int (batch_iterations * measured_batches)

let print_header () =
  print_endline "# schema_version=1";
  print_endline "# runner=ocaml";
  Printf.printf "# runtime_version=%s\n%!" Sys.ocaml_version;
  Printf.printf "# warmup_batches=%d measured_batches=%d batch_iterations=%d\n%!"
    warmup_batches measured_batches batch_iterations;
  print_endline
    "case\tworkload_version\tpattern\tpattern_hex\tevents_per_period\tpayload_bytes\tchunk_bytes\texpected_events\tmedian_ns_per_op\tp95_ns_per_op\trsd_ppm\tminor_words_per_op\tpromoted_words_per_op\tmajor_words_per_op\tminor_collections\tmajor_collections"

let print_workload workload measurement =
  let median = ns_per_operation (median_ns measurement.batch_elapsed_ns) in
  let p95 =
    ns_per_operation
      (Int64.to_float (percentile_ns measurement.batch_elapsed_ns 95))
  in
  Printf.printf
    "%s\t%d\t%s\t%s\t%d\t%d\t%d\t%d\t%.3f\t%.3f\t%d\t%.3f\t%.3f\t%.3f\t%d\t%d\n%!"
    workload.name workload.workload_version workload.pattern_name
    workload.pattern_hex workload.events_per_period workload.payload_bytes
    workload.chunk_bytes workload.expected_events median p95
    (rsd_ppm measurement.batch_elapsed_ns)
    (words_per_operation measurement.minor_words)
    (words_per_operation measurement.promoted_words)
    (words_per_operation measurement.major_words)
    measurement.minor_collections measurement.major_collections

let () =
  let manifest =
    match Array.to_list Sys.argv with
    | [ _; path ] -> path
    | _ -> fail "usage: benchmark_terminal.exe MANIFEST"
  in
  let workloads = read_manifest manifest in
  match workloads with
  | [] -> fail "terminal performance manifest contains no workloads"
  | _ ->
      print_header ();
      List.iter (fun workload -> print_workload workload (measure workload)) workloads
