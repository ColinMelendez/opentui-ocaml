module Core = Opentui_core.Scene
module Core_node = Core.Node
module Input = Opentui_core.Platform.Eio_runtime.Input_flow
module Coordinator = Opentui_core.Lib.Input_coordinator
module Events = Opentui_core.Lib.Event_queue
module Input_event = Opentui_core.Lib.Stdin_parser
module Key = Opentui_core.Lib.Key_decoder
module Mouse = Opentui_core.Lib.Mouse_decoder
module Output = Opentui_core.Platform.Eio_runtime.Output_flow

let fail message =
  prerr_endline message;
  Stdlib.exit 1

let expect_ok result =
  match result with
  | Ok value -> value
  | Error _ -> fail "benchmark workload operation failed"

let expect_unit result =
  match result with
  | Ok () -> ()
  | Error _ -> fail "benchmark workload operation failed"

type sample = {
  elapsed_ns : int64;
  minor_words : int64;
  major_words : int64;
  minor_collections : int;
  major_collections : int;
}

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

let width = 80
let height = 24
let content_rows = height - 2
let warmup_frames = 128
let measured_frames = 512
let event_budget = 32

let fit_text text =
  let text_length = String.length text in
  String.init width (fun index ->
      if Int.compare index text_length < 0 then String.get text index else ' ')

let row_text row =
  String.init width (fun column ->
      Char.chr (Char.code 'A' + ((row + column) mod 26)))

let append_input buffer frame_number =
  let character = Char.chr (Char.code 'a' + (frame_number mod 26)) in
  let paste_row = frame_number mod content_rows in
  Buffer.add_string buffer "\027[A";
  Buffer.add_char buffer character;
  Buffer.add_string buffer "\027[1;5C";
  Buffer.add_string buffer "\027[200~query-";
  Buffer.add_string buffer (Int.to_string paste_row);
  Buffer.add_string buffer "\027[201~";
  Buffer.add_string buffer "\027[<0;10;5M";
  Buffer.add_string buffer "\027[<0;10;5m"

let input_payload frames =
  let buffer = Buffer.create (frames * 64) in
  for frame_number = 0 to frames - 1 do
    append_input buffer frame_number
  done;
  Buffer.contents buffer

let pointer_kind = function
  | Mouse.Down -> Core.Down
  | Mouse.Up -> Core.Up
  | Mouse.Move -> Core.Move
  | Mouse.Drag -> Core.Drag
  | Mouse.Scroll -> Core.Scroll

let key_text key modifiers =
  let prefix =
    if modifiers.Opentui_core.Lib.Key_decoder.ctrl then "ctrl-"
    else if modifiers.Opentui_core.Lib.Key_decoder.meta then "meta-"
    else if modifiers.Opentui_core.Lib.Key_decoder.shift then "shift-"
    else ""
  in
  match key with
  | Key.Character bytes -> prefix ^ Bytes.to_string bytes
  | Key.Named named_key -> prefix ^ Key.named_key_name named_key

let profile env =
  let scene =
    expect_ok
      (Core.create ~width:(Int32.of_int width) ~height:(Int32.of_int height))
  in
  let root = expect_ok (Core.root scene) in
  let nodes =
    Array.init height (fun row ->
        let text =
          if Int.equal row 0 then "OpenTUI warmed workload"
          else if Int.equal row (height - 1) then "status: ready"
          else row_text row
        in
        expect_ok
          (Core_node.create_text ~parent:root ~width:(Float.of_int width)
             ~height:1.0 ~text:(fit_text text) ()))
  in
  let order = Array.copy nodes in
  let output = Bytes.create (width * height) in
  let expected_bytes = Int32.of_int (Bytes.length output) in
  let sink_buffer = Buffer.create (Bytes.length output) in
  let sink = Eio.Flow.buffer_sink sink_buffer in
  let output_flow = Output.create ~sink in
  let clock = Eio.Stdenv.mono_clock env in
  let selected_row = ref 0 in
  let delivered_events = ref 0 in
  let maximum_queue_length = ref 0 in
  let pointer_handler node event =
    if Core_node.is_destroyed node then Core.Stop
    else if Int.equal event.Core.button 0 then Core.Continue
    else Core.Stop
  in
  Array.iter
    (fun node -> expect_unit (Core_node.set_pointer_handler node pointer_handler))
    nodes;
  let update_row row text =
    expect_unit
      (Core_node.set_text (Array.get nodes row) ~text:(fit_text text))
  in
  let selected_node () = Array.get nodes (1 + !selected_row) in
  let select_row row =
    if Int.compare row 0 < 0 then selected_row := 0
    else if Int.compare row content_rows >= 0 then
      selected_row := content_rows - 1
    else selected_row := row
  in
  let handle_input_event event =
    delivered_events := !delivered_events + 1;
    match event with
    | Input_event.Key { key; modifiers; _ } ->
        update_row (1 + !selected_row) (key_text key modifiers)
    | Input_event.Mouse { event; _ } ->
        select_row (event.Opentui_core.Lib.Mouse_decoder.y - 1);
        let pointer_event =
          {
            Core.kind = pointer_kind event.Opentui_core.Lib.Mouse_decoder.kind;
            button = event.Opentui_core.Lib.Mouse_decoder.button;
            x = event.Opentui_core.Lib.Mouse_decoder.x;
            y = event.Opentui_core.Lib.Mouse_decoder.y;
          }
        in
        ignore (expect_ok (Core.dispatch_pointer scene pointer_event))
    | Input_event.Response sequence ->
        update_row (1 + !selected_row) (Bytes.to_string sequence.bytes)
    | Input_event.Paste bytes ->
        update_row (1 + !selected_row) (Bytes.to_string bytes)
  in
  let run_load ~frames ~input ~source ~queue =
    let input_finished = ref false in
    let emit event =
      match Events.push queue (Events.Input event) with
      | Ok () ->
          let length = Events.length queue in
          if Int.compare length !maximum_queue_length > 0 then
            maximum_queue_length := length;
          Coordinator.Accepted
      | Error Events.Full -> Coordinator.Full
      | Error Events.Invalid_capacity ->
          fail "warmed workload event queue has invalid capacity"
    in
    let read_once () =
      if not !input_finished then
        match Input.read_once input ~clock ~source ~emit with
        | Ok Input.End_of_input -> input_finished := true
        | Ok (Input.Bytes_read _) | Ok (Input.Backpressured _) -> ()
        | Error _ -> fail "warmed workload input read failed"
    in
    let process_events () =
      let processed = ref 0 in
      let running = ref true in
      while !running && Int.compare !processed event_budget < 0 do
        match Events.read queue with
        | None -> running := false
        | Some (Events.Input event) ->
            handle_input_event event;
            processed := !processed + 1
        | Some (Events.Resize size) ->
            let columns = Opentui_core.Lib.Terminal_size.columns size in
            let rows = Opentui_core.Lib.Terminal_size.rows size in
            update_row (1 + !selected_row)
              (Printf.sprintf "resize %dx%d" columns rows);
            processed := !processed + 1
      done
    in
    let update_scene frame_number =
      let row = 1 + (frame_number mod content_rows) in
      update_row row (Printf.sprintf "frame=%d selected=%d" frame_number !selected_row);
      if Int.equal (frame_number mod 16) 0 then
        expect_unit
          (Core_node.set_dimensions (selected_node ())
             ~width:
               (Float.of_int
                  (if Int.equal (frame_number mod 32) 0 then width
                   else width - 8))
             ~height:1.0);
      if Int.equal (frame_number mod 32) 0 then (
        let source_index = frame_number mod height in
        let target_index = (source_index + 1) mod height in
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
        Array.set order target_index target);
      if Int.equal (frame_number mod 8) 0 then
        let pointer_event =
          {
            Core.kind = Core.Move;
            button = 0;
            x = frame_number mod width;
            y = 1 + (frame_number mod content_rows);
          }
        in
        ignore (expect_ok (Core.dispatch_pointer scene pointer_event))
    in
    for frame_number = 0 to frames - 1 do
      read_once ();
      read_once ();
      process_events ();
      update_scene frame_number;
      (match Core.flush scene ~force:false ~output with
      | Ok { Core.status = Core.Rendered; bytes_written } ->
          if not (Int32.equal bytes_written expected_bytes) then
            fail "warmed workload produced an unexpected scene output length"
      | Ok { status = Core.Skipped; _ } ->
          fail "warmed workload unexpectedly skipped a dirty frame"
      | Ok { status = Core.Failed; _ } ->
          fail "warmed workload scene render failed"
      | Error _ -> fail "warmed workload scene flush failed");
      expect_unit
        (Output.write_subbytes output_flow ~bytes:output ~off:0
           ~len:(Bytes.length output));
      if not (Int.equal (Buffer.length sink_buffer) (Bytes.length output)) then
        fail "warmed workload wrote an unexpected sink length";
      Buffer.clear sink_buffer
    done
  in
  let warmup_input =
    expect_ok (Input.create ~buffer_size:4096 ~initial_capacity:4096 ())
  in
  let warmup_queue = expect_ok (Events.create ~capacity:128 ()) in
  let warmup_source = Eio.Flow.string_source (input_payload warmup_frames) in
  run_load ~frames:warmup_frames ~input:warmup_input ~source:warmup_source
    ~queue:warmup_queue;
  let measured_input =
    expect_ok (Input.create ~buffer_size:4096 ~initial_capacity:4096 ())
  in
  let measured_queue = expect_ok (Events.create ~capacity:128 ()) in
  let measured_source = Eio.Flow.string_source (input_payload measured_frames) in
  delivered_events := 0;
  maximum_queue_length := 0;
  let sample =
    measure (fun () ->
        run_load ~frames:measured_frames ~input:measured_input
          ~source:measured_source ~queue:measured_queue)
  in
  Core.close scene;
  print_sample "warmed_load" ~iterations:measured_frames sample;
  Printf.printf "warmed_load input_events=%d max_queue_length=%d warmup_frames=%d\n%!"
    !delivered_events !maximum_queue_length warmup_frames

module Input_burst = struct
  type counters = {
    mutable key_events : int;
    mutable paste_events : int;
    mutable paste_bytes : int;
    mutable sequence_events : int;
    mutable mouse_events : int;
  }

  type t = {
    coordinator : Coordinator.t;
    queue : Events.t;
    payload : bytes;
    payload_length : int;
    pattern_length : int;
    mutable offset : int;
    mutable draining : bool;
    counters : counters;
    emit : Input_event.event -> Coordinator.delivery;
  }

  let burst_events = 64
  let queue_capacity = 8

  let create () =
    let coordinator = expect_ok (Coordinator.create ~initial_capacity:256 ()) in
    let queue = expect_ok (Events.create ~capacity:queue_capacity ()) in
    let pattern = "\027[A\027[200~user-paste\027[201~" in
    let pattern_length = String.length pattern in
    let payload = Bytes.create (burst_events * pattern_length) in
    for index = 0 to burst_events - 1 do
      Bytes.blit_string pattern 0 payload (index * pattern_length) pattern_length
    done;
    let counters =
      {
        key_events = 0;
        paste_events = 0;
        paste_bytes = 0;
        sequence_events = 0;
        mouse_events = 0;
      }
    in
    let emit event =
      match Events.push queue (Events.Input event) with
      | Ok () ->
          (match event with
          | Input_event.Key _ -> counters.key_events <- counters.key_events + 1
          | Input_event.Paste bytes ->
              counters.paste_events <- counters.paste_events + 1;
              counters.paste_bytes <- counters.paste_bytes + Bytes.length bytes
          | Input_event.Response _ ->
              counters.sequence_events <- counters.sequence_events + 1
          | Input_event.Mouse _ ->
              counters.mouse_events <- counters.mouse_events + 1);
          Coordinator.Accepted
      | Error Events.Full -> Coordinator.Full
      | Error Events.Invalid_capacity ->
          fail "input burst benchmark queue capacity became invalid"
    in
    {
      coordinator;
      queue;
      payload;
      payload_length = Bytes.length payload;
      pattern_length;
      offset = 0;
      draining = false;
      counters;
      emit;
    }

  let drain fixture =
    fixture.draining <- true;
    while fixture.draining do
      match Events.read fixture.queue with
      | None -> fixture.draining <- false
      | Some event -> ignore event
    done

  let drain_all fixture =
    fixture.draining <- true;
    while fixture.draining do
      drain fixture;
      match Coordinator.drain fixture.coordinator ~emit:fixture.emit with
      | Coordinator.Accepted -> fixture.draining <- false
      | Coordinator.Full -> ()
    done;
    drain fixture

  let run fixture =
    Coordinator.reset fixture.coordinator;
    Events.clear fixture.queue;
    fixture.offset <- 0;
    fixture.counters.key_events <- 0;
    fixture.counters.paste_events <- 0;
    fixture.counters.paste_bytes <- 0;
    fixture.counters.sequence_events <- 0;
    fixture.counters.mouse_events <- 0;
    while Int.compare fixture.offset fixture.payload_length < 0 do
      let pattern_offset = fixture.offset mod fixture.pattern_length in
      let chunk_length =
        if Int.equal pattern_offset 0 then 3 else fixture.pattern_length - 3
      in
      match
        Coordinator.push_bytes fixture.coordinator ~now_ms:0L ~emit:fixture.emit
          ~source:fixture.payload ~off:fixture.offset
          ~len:chunk_length
      with
      | Ok Coordinator.Accepted_all ->
          fixture.offset <- fixture.offset + chunk_length
      | Ok (Coordinator.Full_after consumed) ->
          fixture.offset <- fixture.offset + consumed;
          drain_all fixture
      | Error _ -> fail "input burst benchmark parser operation failed"
    done;
    drain_all fixture;
    if
      not (Int.equal fixture.counters.key_events burst_events)
      || not (Int.equal fixture.counters.paste_events burst_events)
      || not
           (Int.equal fixture.counters.paste_bytes
              (burst_events * String.length "user-paste"))
    then
      fail
        (Printf.sprintf
           "input burst benchmark lost a decoded input event (keys=%d pastes=%d bytes=%d sequences=%d mouse=%d offset=%d/%d pending=%d queue=%d)"
           fixture.counters.key_events fixture.counters.paste_events
           fixture.counters.paste_bytes fixture.counters.sequence_events
           fixture.counters.mouse_events fixture.offset fixture.payload_length
           (Coordinator.pending_bytes fixture.coordinator)
           (Events.length fixture.queue))
end

module Output_write = struct
  type t = {
    output : Output.t;
    sink_buffer : Buffer.t;
    bytes : bytes;
    off : int;
    len : int;
  }

  let off = 16
  let len = 128

  let create () =
    let bytes = Bytes.make (off + len) 'x' in
    let sink_buffer = Buffer.create (len * 2) in
    let sink = Eio.Flow.buffer_sink sink_buffer in
    { output = Output.create ~sink; sink_buffer; bytes; off; len }

  let run fixture =
    expect_unit
      (Output.write_subbytes fixture.output ~bytes:fixture.bytes ~off:fixture.off
         ~len:fixture.len);
    if not (Int.equal (Buffer.length fixture.sink_buffer) fixture.len) then
      fail "output write benchmark wrote an unexpected byte count";
    Buffer.clear fixture.sink_buffer
end
