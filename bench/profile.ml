module Native = Opentui_native
module Renderer = Native.Renderer
module Input = Opentui_terminal_eio.Input_flow
module Output = Opentui_terminal_eio.Output_flow

type sample = {
  elapsed_ns : int64;
  minor_words : int64;
  major_words : int64;
  minor_collections : int;
  major_collections : int;
}

let fail message =
  prerr_endline message;
  Stdlib.exit 1

let expect_ok result =
  match result with
  | Ok value -> value
  | Error _ -> fail "profile operation failed"

let expect_unit result =
  match result with
  | Ok () -> ()
  | Error _ -> fail "profile operation failed"

let words value = Int64.of_float value

let measure operation =
  Gc.full_major ();
  let before = Gc.quick_stat () in
  let start = Mtime_clock.elapsed_ns () in
  operation ();
  let elapsed_ns = Int64.sub (Mtime_clock.elapsed_ns ()) start in
  let after = Gc.quick_stat () in
  {
    elapsed_ns;
    minor_words = Int64.sub (words after.minor_words) (words before.minor_words);
    major_words = Int64.sub (words after.major_words) (words before.major_words);
    minor_collections = after.minor_collections - before.minor_collections;
    major_collections = after.major_collections - before.major_collections;
  }

let print_sample name ~iterations sample =
  Printf.printf
    "%s iterations=%d elapsed_ns=%Ld minor_words=%Ld major_words=%Ld minor_collections=%d major_collections=%d\n%!"
    name iterations sample.elapsed_ns sample.minor_words sample.major_words
    sample.minor_collections sample.major_collections

let frame_iterations = 64
let frame_width = 80
let frame_height = 24

let profile_frames () =
  let renderer =
    expect_ok
      (Renderer.create ~width:(Int32.of_int frame_width)
         ~height:(Int32.of_int frame_height))
  in
  let output = Bytes.create (frame_width * frame_height) in
  let foreground = Native.Color.white in
  let background = Native.Color.black in
  let sample =
    measure (fun () ->
        for frame_number = 0 to frame_iterations - 1 do
          let frame = expect_ok (Renderer.begin_frame renderer) in
          for y = 0 to frame_height - 1 do
            for x = 0 to frame_width - 1 do
              let character = Int32.of_int (Char.code 'A' + ((x + y + frame_number) mod 26)) in
              expect_unit
                (Renderer.Frame.set_cell frame ~x:(Int32.of_int x)
                   ~y:(Int32.of_int y) ~character ~foreground ~background
                   ~attributes:0l)
            done
          done;
          let written =
            expect_ok
              (Renderer.Frame.write_resolved_chars frame ~output
                 ~add_line_breaks:false)
          in
          if not (Int32.equal written (Int32.of_int (Bytes.length output))) then
            fail "profile frame produced an unexpected output length";
          ignore (expect_ok (Renderer.present frame ~force:true))
        done)
  in
  Renderer.close renderer;
  print_sample "frames" ~iterations:frame_iterations sample

let input_repetitions = 32768

let input_payload () =
  let result = Bytes.create (input_repetitions * 3) in
  for index = 0 to input_repetitions - 1 do
    let offset = index * 3 in
    Bytes.set_uint8 result offset 0x1b;
    Bytes.set_uint8 result (offset + 1) 0x5b;
    Bytes.set_uint8 result (offset + 2) 0x41
  done;
  Bytes.to_string result

let profile_input env =
  let payload = input_payload () in
  let input = expect_ok (Input.create ~buffer_size:4096 ()) in
  let source = Eio.Flow.string_source payload in
  let clock = Eio.Stdenv.mono_clock env in
  let events = ref 0 in
  let sample =
    measure (fun () ->
        let finished = ref false in
        while not !finished do
          (match Input.read_once input ~clock ~source with
          | Ok Input.End_of_input -> finished := true
          | Ok (Input.Bytes_read _) -> ()
          | Error _ -> fail "profile input read failed");
          Input.drain input (fun _event -> events := !events + 1)
        done)
  in
  if not (Int.equal !events input_repetitions) then
    fail "profile input produced an unexpected event count";
  print_sample "input" ~iterations:input_repetitions sample

let output_iterations = 4096
let output_offset = 16
let output_length = 128
let output_payload = Bytes.make (output_offset + output_length) 'x'

let profile_output () =
  let sink_buffer = Buffer.create (output_iterations * output_length) in
  let sink = Eio.Flow.buffer_sink sink_buffer in
  let output = Output.create ~sink in
  let sample =
    measure (fun () ->
        for _ = 0 to output_iterations - 1 do
          expect_unit
            (Output.write_subbytes output ~bytes:output_payload
               ~off:output_offset ~len:output_length)
        done)
  in
  if not (Int.equal (Buffer.length sink_buffer) (output_iterations * output_length)) then
    fail "profile output wrote an unexpected byte count";
  print_sample "output" ~iterations:output_iterations sample

let () =
  profile_frames ();
  Eio_main.run (fun env ->
      profile_input env;
      profile_output ())
