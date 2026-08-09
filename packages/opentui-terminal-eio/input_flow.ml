type event = Opentui_terminal.Input_coordinator.event

type read_result = End_of_input | Bytes_read of int

type error =
  | Invalid_buffer_size
  | Parser_error of Opentui_terminal.Input_coordinator.error
  | Flow_error

type t = {
  coordinator : Opentui_terminal.Input_coordinator.t;
  flow_buffer : Cstruct.t;
  staging : bytes;
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
        Ok
          {
            coordinator;
            flow_buffer = Cstruct.create buffer_size;
            staging = Bytes.create buffer_size;
          }

let timeout_ms input =
  Opentui_terminal.Input_coordinator.timeout_ms input.coordinator

let deadline input =
  Opentui_terminal.Input_coordinator.deadline input.coordinator

let now_ms clock =
  let nanoseconds = Mtime.to_uint64_ns (Eio.Time.Mono.now clock) in
  Int64.div nanoseconds 1_000_000L

let copy_flow_bytes input count =
  for index = 0 to count - 1 do
    Bytes.set_uint8 input.staging index
      (Cstruct.get_uint8 input.flow_buffer index)
  done

let read_once input ~clock ~source =
  try
    let count = Eio.Flow.single_read source input.flow_buffer in
    if Int.equal count 0 then Ok End_of_input
    else (
      copy_flow_bytes input count;
      match
        Opentui_terminal.Input_coordinator.push_bytes input.coordinator
          ~now_ms:(now_ms clock) ~source:input.staging ~off:0 ~len:count
      with
      | Ok () -> Ok (Bytes_read count)
      | Error error -> Error (Parser_error error))
  with
  | End_of_file -> Ok End_of_input
  | Eio.Io _ -> Error Flow_error

let read input = Opentui_terminal.Input_coordinator.read input.coordinator

let drain input callback =
  Opentui_terminal.Input_coordinator.drain input.coordinator callback

let transfer_one input ~queue =
  Opentui_terminal.Input_coordinator.transfer_one input.coordinator ~queue

let fire_timeout input ~clock =
  Opentui_terminal.Input_coordinator.fire_timeout input.coordinator
    ~now_ms:(now_ms clock)

let reset input = Opentui_terminal.Input_coordinator.reset input.coordinator
