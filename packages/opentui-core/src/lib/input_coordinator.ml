type event = Stdin_parser.event
type delivery = Accepted | Full
type push_result = Accepted_all | Full_after of int

type error = Parser_error of Stdin_parser.error

type t = {
  parser : Stdin_parser.t;
  mutable pending : event option;
  mutable deadline : int64 option;
}

let push_chunk_size = 4096

let message = function
  | Parser_error error -> "input coordinator parser: " ^ Stdin_parser.message error

let pp formatter error = Format.pp_print_string formatter (message error)

let create ?initial_capacity ?max_pending_bytes ?timeout_ms ?kitty_keyboard () =
  match
    Stdin_parser.create ?initial_capacity ?max_pending_bytes ?timeout_ms
      ?kitty_keyboard ()
  with
  | Error error -> Error (Parser_error error)
  | Ok parser ->
      Ok
        {
          parser;
          pending = None;
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

let drain coordinator ~emit =
  let status = ref Accepted in
  let running = ref true in
  while !running do
    match coordinator.pending with
    | Some event ->
        (match emit event with
        | Accepted -> coordinator.pending <- None
        | Full ->
            status := Full;
            running := false)
    | None ->
        (match Stdin_parser.read coordinator.parser with
        | None -> running := false
        | Some input ->
            coordinator.pending <- Some input)
  done;
  !status

let valid_range ~size ~off ~len =
  Int.compare off 0 >= 0
  && Int.compare len 0 >= 0
  && Int.compare off size <= 0
  && Int.compare len (size - off) <= 0

let invalid_range () =
  Error (Parser_error (Stdin_parser.Queue_error Byte_queue.Invalid_range))

let accept_push coordinator ~now_ms ~emit ~source_size ~off ~len push_operation =
  if not (valid_range ~size:source_size ~off ~len) then invalid_range ()
  else
    match drain coordinator ~emit with
    | Full ->
        Ok (Full_after 0)
    | Accepted when Int.equal len 0 ->
        (match push_operation ~off ~len:0 with
        | Error error -> Error (Parser_error error)
        | Ok () ->
            (match drain coordinator ~emit with
            | Accepted -> Ok Accepted_all
            | Full -> Ok (Full_after 0)))
    | Accepted ->
        let position = ref off in
        let end_exclusive = off + len in
        let status = ref Accepted in
        let running = ref true in
        let failure = ref None in
        while
          Int.compare !position end_exclusive < 0
          && !running
          && Option.is_none !failure
        do
          let remaining = end_exclusive - !position in
          let take =
            if Int.compare remaining push_chunk_size < 0 then remaining
            else push_chunk_size
          in
          match push_operation ~off:!position ~len:take with
          | Error error ->
              failure := Some error
          | Ok () ->
              position := !position + take;
              status := drain coordinator ~emit;
              (match !status with
              | Accepted -> ()
              | Full -> running := false)
        done;
        (match !failure with
        | Some error -> Error (Parser_error error)
        | None ->
            refresh_deadline coordinator ~now_ms;
            (match !status with
            | Accepted -> Ok Accepted_all
            | Full -> Ok (Full_after (!position - off))))

let push coordinator ~now_ms ~emit ~source ~off ~len =
  accept_push coordinator ~now_ms ~emit
    ~source_size:(Bigarray.Array1.dim source) ~off ~len
    (fun ~off ~len -> Stdin_parser.push coordinator.parser ~source ~off ~len)

let push_chars coordinator ~now_ms ~emit ~source ~off ~len =
  accept_push coordinator ~now_ms ~emit
    ~source_size:(Bigarray.Array1.dim source) ~off ~len
    (fun ~off ~len ->
      Stdin_parser.push_chars coordinator.parser ~source ~off ~len)

let push_bytes coordinator ~now_ms ~emit ~source ~off ~len =
  accept_push coordinator ~now_ms ~emit ~source_size:(Bytes.length source) ~off
    ~len
    (fun ~off ~len ->
      Stdin_parser.push_bytes coordinator.parser ~source ~off ~len)

let fire_timeout coordinator ~now_ms ~emit =
  match drain coordinator ~emit with
  | Full -> Full
  | Accepted ->
      (match coordinator.deadline with
      | Some deadline when Int64.compare now_ms deadline >= 0 ->
          Stdin_parser.flush_timeout coordinator.parser;
          let status = drain coordinator ~emit in
          refresh_deadline coordinator ~now_ms;
          status
      | Some _ | None -> Accepted)

let reset coordinator =
  Stdin_parser.reset coordinator.parser;
  coordinator.pending <- None;
  coordinator.deadline <- None
