type event = Input_decoder.event

type error = Parser_error of Stdin_parser.error

type t = {
  parser : Stdin_parser.t;
  decoder : Input_decoder.t;
  events : event Queue.t;
  mutable deadline : int64 option;
}

let message = function
  | Parser_error error -> "input coordinator parser: " ^ Stdin_parser.message error

let pp formatter error = Format.pp_print_string formatter (message error)

let create ?initial_capacity ?max_pending_bytes ?timeout_ms () =
  match
    Stdin_parser.create ?initial_capacity ?max_pending_bytes ?timeout_ms ()
  with
  | Error error -> Error (Parser_error error)
  | Ok parser ->
      Ok
        {
          parser;
          decoder = Input_decoder.create ();
          events = Queue.create ();
          deadline = None;
        }

let timeout_ms coordinator = Stdin_parser.timeout_ms coordinator.parser
let pending_bytes coordinator = Stdin_parser.pending_bytes coordinator.parser
let deadline coordinator = coordinator.deadline

let deadline_after coordinator now_ms =
  let timeout = Int64.of_int (timeout_ms coordinator) in
  let latest = Int64.sub Int64.max_int timeout in
  if Int64.compare now_ms latest > 0 then Int64.max_int
  else Int64.add now_ms timeout

let refresh_deadline coordinator ~now_ms =
  if Int.compare (pending_bytes coordinator) 0 > 0 then
    coordinator.deadline <- Some (deadline_after coordinator now_ms)
  else coordinator.deadline <- None

let drain_parser coordinator =
  Stdin_parser.drain coordinator.parser (fun input ->
      Queue.add (Input_decoder.decode coordinator.decoder input) coordinator.events)

let accept_push coordinator ~now_ms push_operation =
  match push_operation () with
  | Error error -> Error (Parser_error error)
  | Ok () ->
      drain_parser coordinator;
      refresh_deadline coordinator ~now_ms;
      Ok ()

let push coordinator ~now_ms ~source ~off ~len =
  accept_push coordinator ~now_ms (fun () ->
      Stdin_parser.push coordinator.parser ~source ~off ~len)

let push_chars coordinator ~now_ms ~source ~off ~len =
  accept_push coordinator ~now_ms (fun () ->
      Stdin_parser.push_chars coordinator.parser ~source ~off ~len)

let push_bytes coordinator ~now_ms ~source ~off ~len =
  accept_push coordinator ~now_ms (fun () ->
      Stdin_parser.push_bytes coordinator.parser ~source ~off ~len)

let read coordinator =
  if Queue.is_empty coordinator.events then None
  else Some (Queue.take coordinator.events)

let drain coordinator callback =
  while not (Queue.is_empty coordinator.events) do
    callback (Queue.take coordinator.events)
  done

let transfer_one coordinator ~queue =
  if Queue.is_empty coordinator.events then Ok false
  else
    let event = Queue.peek coordinator.events in
    match Event_queue.push queue (Event_queue.Input event) with
    | Error error -> Error error
    | Ok () ->
        ignore (Queue.take coordinator.events);
        Ok true

let fire_timeout coordinator ~now_ms =
  match coordinator.deadline with
  | Some deadline when Int64.compare now_ms deadline >= 0 ->
      Stdin_parser.flush_timeout coordinator.parser;
      drain_parser coordinator;
      refresh_deadline coordinator ~now_ms
  | Some _ | None -> ()

let reset coordinator =
  Stdin_parser.reset coordinator.parser;
  Input_decoder.reset coordinator.decoder;
  Queue.clear coordinator.events;
  coordinator.deadline <- None
