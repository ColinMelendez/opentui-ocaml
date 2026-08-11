module Native = Opentui_native
module Renderer = Native.Renderer
module Core = Opentui_core.Scene
module Core_node = Core.Node
module Input = Opentui_terminal_eio.Input_flow
module Coordinator = Opentui_terminal.Input_coordinator
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

let retained_iterations = 64
let retained_width = 80
let retained_height = 24

let retained_row_text row =
  String.init retained_width (fun column ->
      Char.chr (Char.code 'A' + ((row + column) mod 26)))

let profile_retained_text () =
  let scene =
    expect_ok
      (Core.create ~width:(Int32.of_int retained_width)
         ~height:(Int32.of_int retained_height))
  in
  let root = expect_ok (Core.root scene) in
  let rows = Array.init retained_height retained_row_text in
  let nodes =
    Array.init retained_height (fun row ->
        expect_ok
          (Core_node.create_text ~parent:root
             ~width:(Float.of_int retained_width) ~height:1.0
             ~text:(Array.get rows row) ()))
  in
  let output = Bytes.create (retained_width * retained_height) in
  let expected_bytes = Int32.of_int (Bytes.length output) in
  let run_frame frame_number =
    let row = frame_number mod retained_height in
    expect_unit
      (Core_node.set_text (Array.get nodes row)
         ~text:(Array.get rows ((row + frame_number) mod retained_height)));
    match Core.flush scene ~force:false ~output with
    | Ok { Core.status = Core.Rendered; bytes_written } ->
        if not (Int32.equal bytes_written expected_bytes) then
          fail "profile retained scene produced an unexpected output length"
    | Ok { status = Core.Skipped; _ } ->
        fail "profile retained scene unexpectedly skipped a dirty frame"
    | Ok { status = Core.Failed; _ } ->
        fail "profile retained scene failed to render"
    | Error _ -> fail "profile retained scene operation failed"
  in
  run_frame 0;
  let sample =
    measure (fun () ->
        for frame_number = 0 to retained_iterations - 1 do
          run_frame frame_number
        done)
  in
  Core.close scene;
  print_sample "retained_text" ~iterations:retained_iterations sample

let layout_iterations = 128

let profile_retained_layout () =
  let scene =
    expect_ok
      (Core.create ~width:(Int32.of_int retained_width)
         ~height:(Int32.of_int retained_height))
  in
  let root = expect_ok (Core.root scene) in
  let nodes =
    Array.init retained_height (fun row ->
        expect_ok
          (Core_node.create_text ~parent:root
             ~width:(Float.of_int retained_width) ~height:1.0
             ~text:(retained_row_text row) ()))
  in
  let output = Bytes.create (retained_width * retained_height) in
  let expected_bytes = Int32.of_int (Bytes.length output) in
  let run_update iteration =
    let row = iteration mod retained_height in
    let width =
      if Int.equal (iteration mod 2) 0 then retained_width
      else retained_width / 2
    in
    expect_unit
      (Core_node.set_dimensions (Array.get nodes row)
         ~width:(Float.of_int width) ~height:1.0);
    match Core.flush scene ~force:false ~output with
    | Ok { Core.status = Core.Rendered; bytes_written } ->
        if not (Int32.equal bytes_written expected_bytes) then
          fail "profile retained layout produced an unexpected output length"
    | Ok { status = Core.Skipped; _ } ->
        fail "profile retained layout unexpectedly skipped a dirty frame"
    | Ok { status = Core.Failed; _ } ->
        fail "profile retained layout failed to render"
    | Error _ -> fail "profile retained layout operation failed"
  in
  run_update 1;
  let sample =
    measure (fun () ->
        for iteration = 0 to layout_iterations - 1 do
          run_update iteration
        done)
  in
  Core.close scene;
  print_sample "retained_layout" ~iterations:layout_iterations sample

let reorder_iterations = 128
let reorder_nodes = 24

let profile_retained_reorder () =
  let scene =
    expect_ok
      (Core.create ~width:(Int32.of_int retained_width)
         ~height:(Int32.of_int retained_height))
  in
  let root = expect_ok (Core.root scene) in
  let nodes =
    Array.init reorder_nodes (fun row ->
        expect_ok
          (Core_node.create_text ~parent:root
             ~width:(Float.of_int retained_width) ~height:1.0
             ~text:(retained_row_text row) ()))
  in
  let output = Bytes.create (retained_width * retained_height) in
  let expected_bytes = Int32.of_int (Bytes.length output) in
  let order = Array.init reorder_nodes (fun index -> Array.get nodes index) in
  let run_update iteration =
    let source_index = iteration mod reorder_nodes in
    let target_index = (source_index + 1) mod reorder_nodes in
    let target = Array.get order source_index in
    expect_unit (Core_node.move_to_index target ~index:target_index);
    if Int.compare source_index target_index < 0 then
      for index = source_index to target_index - 1 do
        Array.set order index (Array.get order (index + 1))
      done
    else
      for index = source_index downto target_index + 1 do
        Array.set order index (Array.get order (index - 1))
      done;
    Array.set order target_index target;
    match Core.flush scene ~force:false ~output with
    | Ok { Core.status = Core.Rendered; bytes_written } ->
        if not (Int32.equal bytes_written expected_bytes) then
          fail "profile retained reorder produced an unexpected output length"
    | Ok { status = Core.Skipped; _ } ->
        fail "profile retained reorder unexpectedly skipped a dirty frame"
    | Ok { status = Core.Failed; _ } ->
        fail "profile retained reorder failed to render"
    | Error _ -> fail "profile retained reorder operation failed"
  in
  run_update 1;
  let sample =
    measure (fun () ->
        for iteration = 0 to reorder_iterations - 1 do
          run_update iteration
        done)
  in
  Core.close scene;
  print_sample "retained_reorder" ~iterations:reorder_iterations sample

let teardown_iterations = 64

let profile_retained_teardown () =
  let scene =
    expect_ok
      (Core.create ~width:(Int32.of_int retained_width)
         ~height:(Int32.of_int retained_height))
  in
  let root = expect_ok (Core.root scene) in
  let output = Bytes.create (retained_width * retained_height) in
  let expected_bytes = Int32.of_int (Bytes.length output) in
  let flush_after_change message =
    match Core.flush scene ~force:false ~output with
    | Ok { Core.status = Core.Rendered; bytes_written } ->
        if not (Int32.equal bytes_written expected_bytes) then fail message
    | Ok { status = Core.Skipped; _ } -> fail message
    | Ok { status = Core.Failed; _ } -> fail message
    | Error _ -> fail message
  in
  flush_after_change "profile retained teardown initial flush failed";
  let run_update iteration =
    let child =
      expect_ok
        (Core_node.create_text ~parent:root
           ~width:(Float.of_int retained_width) ~height:1.0
           ~text:(retained_row_text (iteration mod retained_height)) ())
    in
    flush_after_change "profile retained teardown create flush failed";
    expect_unit (Core_node.destroy child);
    flush_after_change "profile retained teardown destroy flush failed"
  in
  let sample =
    measure (fun () ->
        for iteration = 0 to teardown_iterations - 1 do
          run_update iteration
        done)
  in
  Core.close scene;
  print_sample "retained_teardown" ~iterations:teardown_iterations sample

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
  let emit _event =
    events := !events + 1;
    Coordinator.Accepted
  in
  let sample =
    measure (fun () ->
        let finished = ref false in
        while not !finished do
          (match Input.read_once input ~clock ~source ~emit with
          | Ok Input.End_of_input -> finished := true
          | Ok (Input.Bytes_read _) -> ()
          | Ok (Input.Backpressured _) -> fail "profile input unexpectedly blocked"
          | Error _ -> fail "profile input read failed");
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
  profile_retained_text ();
  profile_retained_layout ();
  profile_retained_reorder ();
  profile_retained_teardown ();
  profile_frames ();
  Eio_main.run (fun env ->
      profile_input env;
      profile_output ())
