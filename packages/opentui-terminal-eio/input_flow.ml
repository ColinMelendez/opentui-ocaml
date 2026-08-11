type event = Opentui_terminal.Input_coordinator.event
type delivery = Opentui_terminal.Input_coordinator.delivery
type read_result = End_of_input | Bytes_read of int | Backpressured of int

type error =
  | Invalid_buffer_size
  | Parser_error of Opentui_terminal.Input_coordinator.error
  | Flow_error

type t = {
  coordinator : Opentui_terminal.Input_coordinator.t;
  flow_buffer : Cstruct.t;
  flow_storage : Opentui_terminal.Byte_queue.char_buffer;
  mutable read_offset : int;
  mutable read_length : int;
}

let message = function
  | Invalid_buffer_size -> "terminal Eio input buffer size must be positive"
  | Parser_error error ->
      "terminal Eio input parser: "
      ^ Opentui_terminal.Input_coordinator.message error
  | Flow_error -> "terminal Eio input flow failed"

let pp formatter error = Format.pp_print_string formatter (message error)

let default_buffer_size = 4096

let create ?(buffer_size = default_buffer_size) ?initial_capacity
    ?max_pending_bytes ?timeout_ms () =
  if Int.compare buffer_size 0 <= 0 then Error Invalid_buffer_size
  else
    match
      Opentui_terminal.Input_coordinator.create ?initial_capacity
        ?max_pending_bytes ?timeout_ms ()
    with
    | Error error -> Error (Parser_error error)
    | Ok coordinator ->
        let flow_buffer = Cstruct.create buffer_size in
        Ok
          {
            coordinator;
            flow_buffer;
            flow_storage = Cstruct.to_bigarray flow_buffer;
            read_offset = 0;
            read_length = 0;
          }

let timeout_ms input =
  Opentui_terminal.Input_coordinator.timeout_ms input.coordinator

let deadline input =
  Opentui_terminal.Input_coordinator.deadline input.coordinator

let now_ms clock =
  let nanoseconds = Mtime.to_uint64_ns (Eio.Time.Mono.now clock) in
  Int64.div nanoseconds 1_000_000L

let clear_read input =
  input.read_offset <- 0;
  input.read_length <- 0

let push_read_buffer input ~now_ms ~emit =
  if Int.equal input.read_length 0 then (
    Ok Opentui_terminal.Input_coordinator.Accepted)
  else
    match
      Opentui_terminal.Input_coordinator.push_chars input.coordinator ~now_ms
        ~emit ~source:input.flow_storage ~off:input.read_offset
        ~len:input.read_length
    with
    | Error error -> Error (Parser_error error)
    | Ok Opentui_terminal.Input_coordinator.Accepted_all ->
        clear_read input;
        Ok Opentui_terminal.Input_coordinator.Accepted
    | Ok (Opentui_terminal.Input_coordinator.Full_after consumed) ->
        input.read_offset <- input.read_offset + consumed;
        input.read_length <- input.read_length - consumed;
        if Int.equal input.read_length 0 then clear_read input;
        Ok Opentui_terminal.Input_coordinator.Full

let read_once input ~clock ~source ~emit =
  let current_now_ms = now_ms clock in
  match push_read_buffer input ~now_ms:current_now_ms ~emit with
  | Error error -> Error error
  | Ok Opentui_terminal.Input_coordinator.Full -> Ok (Backpressured 0)
  | Ok Opentui_terminal.Input_coordinator.Accepted ->
      (match
         Opentui_terminal.Input_coordinator.drain input.coordinator ~emit
       with
      | Opentui_terminal.Input_coordinator.Full -> Ok (Backpressured 0)
      | Opentui_terminal.Input_coordinator.Accepted ->
          try
            let count = Eio.Flow.single_read source input.flow_buffer in
            if Int.equal count 0 then Ok End_of_input
            else (
              input.read_offset <- 0;
              input.read_length <- count;
              let admitted_now_ms = now_ms clock in
              match push_read_buffer input ~now_ms:admitted_now_ms ~emit with
              | Error error -> Error error
              | Ok Opentui_terminal.Input_coordinator.Accepted ->
                  Ok (Bytes_read count)
              | Ok Opentui_terminal.Input_coordinator.Full ->
                  Ok (Backpressured count))
          with
          | End_of_file -> Ok End_of_input
          | Eio.Io _ -> Error Flow_error)

let fire_timeout input ~clock ~emit =
  let current_now_ms = now_ms clock in
  match push_read_buffer input ~now_ms:current_now_ms ~emit with
  | Error error -> Error error
  | Ok Opentui_terminal.Input_coordinator.Full ->
      Ok Opentui_terminal.Input_coordinator.Full
  | Ok Opentui_terminal.Input_coordinator.Accepted ->
      Ok
        (Opentui_terminal.Input_coordinator.fire_timeout input.coordinator
           ~now_ms:current_now_ms ~emit)

let reset input =
  Opentui_terminal.Input_coordinator.reset input.coordinator;
  clear_read input
