type protocol = Csi | Ss3 | Osc | Dcs | Apc | Unknown

type event =
  | Key of bytes
  | Sequence of { protocol : protocol; bytes : bytes }
  | Paste of bytes

type error = Invalid_timeout | Queue_error of Byte_queue.error

type state =
  | Ground
  | Esc
  | Utf8
  | Csi
  | Ss3
  | Osc
  | Dcs
  | Apc
  | Esc_recovery
  | Esc_less_mouse
  | Esc_less_x10_mouse

type t = {
  pending : Byte_queue.t;
  max_pending_bytes : int;
  timeout_ms : int;
  events : event Queue.t;
  mutable state : state;
  mutable cursor : int;
  mutable unit_start : int;
  mutable utf8_expected : int;
  mutable utf8_seen : int;
  mutable saw_esc : bool;
  mutable force_flush : bool;
  mutable just_flushed_esc : bool;
  mutable paste_active : bool;
  mutable paste_parts : bytes list;
  mutable paste_total : int;
  mutable paste_chunk : bytes;
  mutable paste_chunk_length : int;
  paste_tail : int array;
  mutable paste_tail_length : int;
}

let default_max_pending_bytes = 64 * 1024
let default_timeout_ms = 20
let paste_chunk_size = 4096
let escape = 0x1b
let bell = 0x07
let backslash = 0x5c

let bracketed_paste_start = [| escape; 0x5b; 0x32; 0x30; 0x30; 0x7e |]
let bracketed_paste_end = [| escape; 0x5b; 0x32; 0x30; 0x31; 0x7e |]

let message = function
  | Invalid_timeout -> "stdin parser timeout must be positive"
  | Queue_error error -> "stdin parser queue: " ^ Byte_queue.message error

let pp formatter error = Format.pp_print_string formatter (message error)

let queue_error error = Error (Queue_error error)

let create ?initial_capacity ?(max_pending_bytes = default_max_pending_bytes)
    ?(timeout_ms = default_timeout_ms) () =
  if Int.compare timeout_ms 0 <= 0 then Error Invalid_timeout
  else
    match
      Byte_queue.create ?initial_capacity ~max_capacity:max_pending_bytes ()
    with
    | Error error -> queue_error error
    | Ok pending ->
        Ok
          {
            pending;
            max_pending_bytes = Byte_queue.max_capacity pending;
            timeout_ms;
            events = Queue.create ();
            state = Ground;
            cursor = 0;
            unit_start = 0;
            utf8_expected = 0;
            utf8_seen = 0;
            saw_esc = false;
            force_flush = false;
            just_flushed_esc = false;
            paste_active = false;
            paste_parts = [];
            paste_total = 0;
            paste_chunk = Bytes.create paste_chunk_size;
            paste_chunk_length = 0;
            paste_tail = Array.make (Array.length bracketed_paste_end) 0;
            paste_tail_length = 0;
          }

let timeout_ms parser = parser.timeout_ms
let pending_bytes parser = Byte_queue.length parser.pending
let buffer_capacity parser = Byte_queue.capacity parser.pending

let valid_range ~size ~off ~len =
  Int.compare off 0 >= 0
  && Int.compare len 0 >= 0
  && Int.compare off size <= 0
  && Int.compare len (size - off) <= 0

let byte_at parser index =
  match Byte_queue.get parser.pending index with
  | Some value -> value
  | None -> failwith "stdin parser cursor escaped its byte queue"

let copy_range parser ~start ~end_exclusive =
  let length = end_exclusive - start in
  let result = Bytes.create length in
  for index = 0 to length - 1 do
    Bytes.set_uint8 result index (byte_at parser (start + index))
  done;
  result

let copy_range_with_escape parser ~start ~end_exclusive =
  let length = end_exclusive - start in
  let result = Bytes.create (length + 1) in
  Bytes.set_uint8 result 0 escape;
  for index = 0 to length - 1 do
    Bytes.set_uint8 result (index + 1) (byte_at parser (start + index))
  done;
  result

let range_matches parser ~start ~end_exclusive marker =
  let marker_length = Array.length marker in
  if not (Int.equal (end_exclusive - start) marker_length) then false
  else
    let matches = ref true in
    for index = 0 to marker_length - 1 do
      if not (Int.equal (byte_at parser (start + index)) marker.(index)) then
        matches := false
    done;
    !matches

let reset_unit parser =
  parser.cursor <- 0;
  parser.unit_start <- 0;
  parser.utf8_expected <- 0;
  parser.utf8_seen <- 0;
  parser.saw_esc <- false;
  parser.force_flush <- false

let consume_prefix parser end_exclusive =
  let preserve_force_flush = parser.force_flush in
  match Byte_queue.consume parser.pending end_exclusive with
  | Ok () ->
      reset_unit parser;
      parser.force_flush <- preserve_force_flush
  | Error _ -> failwith "stdin parser consumed outside its byte queue"

let set_ground parser =
  parser.state <- Ground;
  parser.saw_esc <- false

let emit_key parser ~start ~end_exclusive =
  Queue.add (Key (copy_range parser ~start ~end_exclusive)) parser.events

let emit_sequence parser protocol ~start ~end_exclusive =
  Queue.add
    (Sequence { protocol; bytes = copy_range parser ~start ~end_exclusive })
    parser.events

let emit_sequence_with_escape parser protocol ~start ~end_exclusive =
  Queue.add
    (Sequence
       {
         protocol;
         bytes = copy_range_with_escape parser ~start ~end_exclusive;
       })
    parser.events

let clear_paste_storage parser =
  parser.paste_parts <- [];
  parser.paste_total <- 0;
  parser.paste_chunk <- Bytes.create paste_chunk_size;
  parser.paste_chunk_length <- 0;
  parser.paste_tail_length <- 0

let start_paste parser =
  clear_paste_storage parser;
  parser.force_flush <- false;
  parser.just_flushed_esc <- false;
  parser.paste_active <- true

let add_paste_stable_byte parser value =
  Bytes.set_uint8 parser.paste_chunk parser.paste_chunk_length value;
  parser.paste_chunk_length <- parser.paste_chunk_length + 1;
  if Int.equal parser.paste_chunk_length paste_chunk_size then (
    parser.paste_parts <- parser.paste_chunk :: parser.paste_parts;
    parser.paste_total <- parser.paste_total + paste_chunk_size;
    parser.paste_chunk <- Bytes.create paste_chunk_size;
    parser.paste_chunk_length <- 0)

let paste_tail_matches_end parser =
  let matches = ref true in
  for index = 0 to Array.length bracketed_paste_end - 1 do
    if not (Int.equal parser.paste_tail.(index) bracketed_paste_end.(index))
    then matches := false
  done;
  !matches

let finish_paste parser =
  let parts =
    if Int.equal parser.paste_chunk_length 0 then parser.paste_parts
    else
      Bytes.sub parser.paste_chunk 0 parser.paste_chunk_length
      :: parser.paste_parts
  in
  let total_length = parser.paste_total + parser.paste_chunk_length in
  let result = Bytes.create total_length in
  let offset = ref 0 in
  List.iter
    (fun part ->
      let length = Bytes.length part in
      Bytes.blit part 0 result !offset length;
      offset := !offset + length)
    (List.rev parts);
  Queue.add (Paste result) parser.events;
  parser.paste_active <- false;
  parser.force_flush <- false;
  clear_paste_storage parser

let add_paste_byte parser value =
  let tail_index = parser.paste_tail_length in
  parser.paste_tail.(tail_index) <- value;
  parser.paste_tail_length <- parser.paste_tail_length + 1;
  if Int.equal parser.paste_tail_length (Array.length bracketed_paste_end) then
    if paste_tail_matches_end parser then (
      parser.paste_tail_length <- 0;
      finish_paste parser)
    else (
      add_paste_stable_byte parser parser.paste_tail.(0);
      for index = 1 to Array.length bracketed_paste_end - 1 do
        parser.paste_tail.(index - 1) <- parser.paste_tail.(index)
      done;
      parser.paste_tail_length <- Array.length bracketed_paste_end - 1)

let is_utf8_continuation value = Int.equal (value land 0xc0) 0x80

let delayed_sgr_mouse_shape parser ~start ~end_exclusive =
  let length = end_exclusive - start in
  if Int.compare length 8 < 0 then false
  else if
    not
      (Int.equal (byte_at parser start) 0x5b
      && Int.equal (byte_at parser (start + 1)) 0x3c)
  then false
  else
    let final = byte_at parser (end_exclusive - 1) in
    if not (Int.equal final 0x4d || Int.equal final 0x6d) then false
    else
      let part = ref 0 in
      let has_digit = ref false in
      let valid = ref true in
      let index = ref (start + 2) in
      while !valid && Int.compare !index (end_exclusive - 1) < 0 do
        let value = byte_at parser !index in
        if Int.compare value 0x30 >= 0 && Int.compare value 0x39 <= 0 then
          has_digit := true
        else if Int.equal value 0x3b then
          if not !has_digit || Int.compare !part 2 >= 0 then valid := false
          else (
            part := !part + 1;
            has_digit := false)
        else valid := false;
        index := !index + 1
      done;
      !valid && Int.equal !part 2 && !has_digit

let utf8_sequence_length value =
  if Int.compare value 0x80 < 0 then 1
  else if Int.compare value 0xc2 >= 0 && Int.compare value 0xdf <= 0 then 2
  else if Int.compare value 0xe0 >= 0 && Int.compare value 0xef <= 0 then 3
  else if Int.compare value 0xf0 >= 0 && Int.compare value 0xf4 <= 0 then 4
  else 0

let flush_pending_as_unknown parser =
  let length = Byte_queue.length parser.pending in
  if Int.compare length 0 > 0 then (
    emit_sequence parser Unknown ~start:0 ~end_exclusive:length;
    set_ground parser;
    consume_prefix parser length)
  else (
    set_ground parser;
    reset_unit parser)

let scan parser =
  let scanning = ref true in
  while !scanning && not parser.paste_active do
    let pending_length = Byte_queue.length parser.pending in
    match parser.state with
    | Ground when Int.compare parser.cursor pending_length >= 0 ->
        reset_unit parser;
        scanning := false
    | Ground ->
        parser.unit_start <- parser.cursor;
        let value = byte_at parser parser.cursor in
        let just_flushed_esc = parser.just_flushed_esc in
        parser.just_flushed_esc <- false;
        if just_flushed_esc && Int.equal value 0x5b then (
          parser.cursor <- parser.cursor + 1;
          parser.state <- Esc_recovery)
        else if Int.equal value escape then (
          parser.cursor <- parser.cursor + 1;
          parser.state <- Esc)
        else if Int.compare value 0x80 < 0 then (
          emit_key parser ~start:parser.cursor ~end_exclusive:(parser.cursor + 1);
          consume_prefix parser (parser.cursor + 1))
        else
          let expected = utf8_sequence_length value in
          if Int.equal expected 0 then
            if
              not parser.force_flush
              && Int.equal (parser.cursor + 1) pending_length
            then scanning := false
            else (
              emit_key parser ~start:parser.cursor
                ~end_exclusive:(parser.cursor + 1);
              consume_prefix parser (parser.cursor + 1))
          else (
            parser.cursor <- parser.cursor + 1;
            parser.utf8_expected <- expected;
            parser.utf8_seen <- 1;
            parser.state <- Utf8)
    | Utf8 ->
        if Int.compare parser.cursor pending_length >= 0 then
          if not parser.force_flush then scanning := false
          else (
            emit_key parser ~start:parser.unit_start
              ~end_exclusive:(parser.unit_start + 1);
            set_ground parser;
            consume_prefix parser (parser.unit_start + 1))
        else
          let value = byte_at parser parser.cursor in
          if not (is_utf8_continuation value) then (
            emit_key parser ~start:parser.unit_start
              ~end_exclusive:(parser.unit_start + 1);
            set_ground parser;
            consume_prefix parser (parser.unit_start + 1))
          else (
            parser.cursor <- parser.cursor + 1;
            parser.utf8_seen <- parser.utf8_seen + 1;
            if Int.equal parser.utf8_seen parser.utf8_expected then (
              emit_key parser ~start:parser.unit_start
                ~end_exclusive:parser.cursor;
              set_ground parser;
              consume_prefix parser parser.cursor))
    | Esc ->
        if Int.compare parser.cursor pending_length >= 0 then
          if not parser.force_flush then scanning := false
          else (
            let flushed_lone_esc =
              Int.equal (parser.cursor - parser.unit_start) 1
            in
            if flushed_lone_esc then
              emit_key parser ~start:parser.unit_start ~end_exclusive:parser.cursor
            else
              emit_sequence parser Unknown ~start:parser.unit_start
                ~end_exclusive:parser.cursor;
            parser.just_flushed_esc <- flushed_lone_esc;
            set_ground parser;
            consume_prefix parser parser.cursor)
        else (
          let value = byte_at parser parser.cursor in
          match value with
          | _ when Int.equal value 0x5b ->
              parser.cursor <- parser.cursor + 1;
              parser.state <- Csi
          | _ when Int.equal value 0x4f ->
              parser.cursor <- parser.cursor + 1;
              parser.state <- Ss3
          | _ when Int.equal value 0x5d ->
              parser.cursor <- parser.cursor + 1;
              parser.state <- Osc;
              parser.saw_esc <- false
          | _ when Int.equal value 0x50 ->
              parser.cursor <- parser.cursor + 1;
              parser.state <- Dcs;
              parser.saw_esc <- false
          | _ when Int.equal value 0x5f ->
              parser.cursor <- parser.cursor + 1;
              parser.state <- Apc;
              parser.saw_esc <- false
          | _ when Int.equal value escape ->
              parser.cursor <- parser.cursor + 1
          | _ ->
              parser.cursor <- parser.cursor + 1;
              emit_sequence parser Unknown ~start:parser.unit_start
                ~end_exclusive:parser.cursor;
              set_ground parser;
              consume_prefix parser parser.cursor)
    | Esc_recovery ->
        if Int.compare parser.cursor pending_length >= 0 then
          if not parser.force_flush then scanning := false
          else (
            emit_key parser ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
        else
          let value = byte_at parser parser.cursor in
          if Int.equal value 0x3c then (
            parser.cursor <- parser.cursor + 1;
            parser.state <- Esc_less_mouse)
          else if Int.equal value 0x4d then (
            parser.cursor <- parser.cursor + 1;
            parser.state <- Esc_less_x10_mouse)
          else (
            emit_key parser ~start:parser.unit_start
              ~end_exclusive:(parser.unit_start + 1);
            set_ground parser;
            consume_prefix parser (parser.unit_start + 1))
    | Esc_less_mouse ->
        if Int.compare parser.cursor pending_length >= 0 then
          if not parser.force_flush then scanning := false
          else (
            emit_sequence_with_escape parser Unknown ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
        else
          let value = byte_at parser parser.cursor in
          if Int.compare value 0x30 >= 0 && Int.compare value 0x39 <= 0 then
            parser.cursor <- parser.cursor + 1
          else if Int.equal value 0x3b then parser.cursor <- parser.cursor + 1
          else if Int.equal value 0x4d || Int.equal value 0x6d then (
            let end_exclusive = parser.cursor + 1 in
            if delayed_sgr_mouse_shape parser ~start:parser.unit_start
                ~end_exclusive
            then emit_sequence_with_escape parser Csi ~start:parser.unit_start
                   ~end_exclusive
            else emit_sequence_with_escape parser Unknown ~start:parser.unit_start
                   ~end_exclusive;
            set_ground parser;
            consume_prefix parser end_exclusive)
          else (
            emit_sequence_with_escape parser Unknown ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
    | Esc_less_x10_mouse ->
        let end_exclusive = parser.unit_start + 5 in
        if Int.compare pending_length end_exclusive < 0 then
          if not parser.force_flush then scanning := false
          else (
            emit_sequence_with_escape parser Unknown ~start:parser.unit_start
              ~end_exclusive:pending_length;
            set_ground parser;
            consume_prefix parser pending_length)
        else (
          emit_sequence_with_escape parser Csi ~start:parser.unit_start
            ~end_exclusive;
          set_ground parser;
          consume_prefix parser end_exclusive)
    | Ss3 ->
        if Int.compare parser.cursor pending_length >= 0 then
          if not parser.force_flush then scanning := false
          else (
            emit_sequence parser Unknown ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
        else
          let value = byte_at parser parser.cursor in
          if Int.equal value escape then (
            emit_sequence parser Unknown ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
          else (
            parser.cursor <- parser.cursor + 1;
            emit_sequence parser Ss3 ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
    | Csi ->
        if Int.compare parser.cursor pending_length >= 0 then
          if not parser.force_flush then scanning := false
          else (
            emit_sequence parser Unknown ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
        else
          let value = byte_at parser parser.cursor in
          if Int.equal value escape then (
            emit_sequence parser Unknown ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
          else if
            Int.equal value 0x4d
            && Int.equal parser.cursor (parser.unit_start + 2)
          then
            let end_exclusive = parser.cursor + 4 in
            if Int.compare pending_length end_exclusive < 0 then
              if not parser.force_flush then scanning := false
              else (
                emit_sequence parser Unknown ~start:parser.unit_start
                  ~end_exclusive:pending_length;
                set_ground parser;
                consume_prefix parser pending_length)
            else (
              parser.cursor <- end_exclusive;
              emit_sequence parser Csi ~start:parser.unit_start
                ~end_exclusive:parser.cursor;
              set_ground parser;
              consume_prefix parser parser.cursor)
          else if
            Int.equal value 0x5b
            && Int.equal parser.cursor (parser.unit_start + 2)
          then parser.cursor <- parser.cursor + 1
          else if Int.compare value 0x40 >= 0 && Int.compare value 0x7e <= 0 then
            let end_exclusive = parser.cursor + 1 in
            if
              range_matches parser ~start:parser.unit_start ~end_exclusive
                bracketed_paste_start
            then (
              set_ground parser;
              consume_prefix parser end_exclusive;
              start_paste parser)
            else (
              emit_sequence parser Csi ~start:parser.unit_start
                ~end_exclusive;
              set_ground parser;
              consume_prefix parser end_exclusive)
          else parser.cursor <- parser.cursor + 1
    | (Osc | Dcs | Apc) as state ->
        if Int.compare parser.cursor pending_length >= 0 then
          if not parser.force_flush then scanning := false
          else (
            emit_sequence parser Unknown ~start:parser.unit_start
              ~end_exclusive:parser.cursor;
            set_ground parser;
            consume_prefix parser parser.cursor)
        else
          let value = byte_at parser parser.cursor in
          if parser.saw_esc then
            if Int.equal value backslash then (
              parser.cursor <- parser.cursor + 1;
              let protocol : protocol =
                match state with
                | Osc -> Osc
                | Dcs -> Dcs
                | Apc -> Apc
                | _ -> Unknown
              in
              emit_sequence parser protocol ~start:parser.unit_start
                ~end_exclusive:parser.cursor;
              set_ground parser;
              consume_prefix parser parser.cursor)
            else parser.saw_esc <- false
          else
            let is_osc =
              match state with
              | Osc -> true
              | Dcs | Apc -> false
              | _ -> false
            in
            if is_osc && Int.equal value bell then (
              parser.cursor <- parser.cursor + 1;
              emit_sequence parser Osc ~start:parser.unit_start
                ~end_exclusive:parser.cursor;
              set_ground parser;
              consume_prefix parser parser.cursor)
            else if Int.equal value escape then (
              parser.cursor <- parser.cursor + 1;
              parser.saw_esc <- true)
            else parser.cursor <- parser.cursor + 1
  done

let pump_pending parser =
  let pumping = ref true in
  while !pumping do
    if parser.paste_active then
      if Int.equal (Byte_queue.length parser.pending) 0 then pumping := false
      else (
        let value = byte_at parser 0 in
        ignore (Byte_queue.consume parser.pending 1);
        add_paste_byte parser value)
    else if Int.equal (Byte_queue.length parser.pending) 0 then
      pumping := false
    else (
      scan parser;
      if not parser.paste_active then pumping := false)
  done

let push_with parser ~source_size ~get ~append ~off ~len =
  if not (valid_range ~size:source_size ~off ~len) then
    queue_error Byte_queue.Invalid_range
  else
    let position = ref off in
    let end_exclusive = off + len in
    let running = ref true in
    let failure = ref None in
    while !running && Int.compare !position end_exclusive < 0 do
      if parser.paste_active then (
        add_paste_byte parser (get !position);
        position := !position + 1)
      else
        let available =
          parser.max_pending_bytes - Byte_queue.length parser.pending
        in
        if Int.equal available 0 then flush_pending_as_unknown parser
        else
          let remaining = end_exclusive - !position in
          let take = if Int.compare remaining available < 0 then remaining else available in
          match append ~off:!position ~len:take with
          | Error error ->
              failure := Some error;
              running := false
          | Ok () ->
              position := !position + take;
              pump_pending parser
    done;
    match !failure with
    | None -> Ok ()
    | Some error -> queue_error error

let push parser ~source ~off ~len =
  push_with parser ~source_size:(Bigarray.Array1.dim source)
    ~get:(Bigarray.Array1.get source)
    ~append:(fun ~off ~len -> Byte_queue.append parser.pending ~source ~off ~len)
    ~off ~len

let push_bytes parser ~source ~off ~len =
  push_with parser ~source_size:(Bytes.length source) ~get:(Bytes.get_uint8 source)
    ~append:(fun ~off ~len ->
      Byte_queue.append_bytes parser.pending ~source ~off ~len)
    ~off ~len

let read parser =
  if Queue.is_empty parser.events then None else Some (Queue.take parser.events)

let drain parser callback =
  while not (Queue.is_empty parser.events) do
    callback (Queue.take parser.events)
  done

let flush_timeout parser =
  if not parser.paste_active && Int.compare (Byte_queue.length parser.pending) 0 > 0 then (
    parser.force_flush <- true;
    pump_pending parser;
    parser.force_flush <- false)

let reset parser =
  Byte_queue.clear parser.pending;
  Queue.clear parser.events;
  parser.state <- Ground;
  parser.just_flushed_esc <- false;
  parser.paste_active <- false;
  clear_paste_storage parser;
  reset_unit parser
