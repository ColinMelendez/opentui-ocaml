type protocol = Csi | Ss3 | Osc | Dcs | Apc | Unknown

type event =
  | Key of {
      raw : bytes;
      key : Key_decoder.key;
      modifiers : Key_decoder.modifiers;
      metadata : Key_decoder.metadata;
    }
  | Mouse of {
      raw : bytes;
      encoding : Mouse_decoder.encoding;
      event : Mouse_decoder.event;
    }
  | Paste of bytes
  | Response of { protocol : protocol; bytes : bytes }

type protocol_context = {
  kitty_keyboard_enabled : bool;
  private_capability_replies_active : bool;
  pixel_resolution_query_active : bool;
  explicit_width_cpr_active : bool;
  startup_cursor_cpr_active : bool;
}

let default_protocol_context =
  {
    kitty_keyboard_enabled = false;
    private_capability_replies_active = false;
    pixel_resolution_query_active = false;
    explicit_width_cpr_active = false;
    startup_cursor_cpr_active = false;
  }

type error = Invalid_timeout | Queue_error of Byte_queue.error | Destroyed

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
  events : event Stdlib.Queue.t;
  mouse : Mouse_decoder.t;
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
  kitty_keyboard : bool;
  mutable protocol_context : protocol_context;
  arm_timeouts : bool;
  on_timeout_flush : (unit -> unit) option;
  clock : Clock.t option;
  mutable timeout_timer : Clock.timer option;
  mutable pending_timeout_paused : bool;
  mutable destroyed : bool;
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
  | Destroyed -> "stdin parser is destroyed"

let pp formatter error = Format.pp_print_string formatter (message error)

let queue_error error = Error (Queue_error error)

let create ?initial_capacity ?(max_pending_bytes = default_max_pending_bytes)
    ?(timeout_ms = default_timeout_ms) ?(kitty_keyboard = true)
    ?(arm_timeouts = false) ?on_timeout_flush ?clock
    ?(protocol_context = default_protocol_context) () =
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
            events = Stdlib.Queue.create ();
            mouse = Mouse_decoder.create ();
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
            kitty_keyboard;
            protocol_context;
            arm_timeouts;
            on_timeout_flush;
            clock;
            timeout_timer = None;
            pending_timeout_paused = false;
            destroyed = false;
          }

let timeout_ms parser = parser.timeout_ms
let pending_bytes parser = Byte_queue.length parser.pending
let buffer_capacity parser = Byte_queue.capacity parser.pending
let is_destroyed parser = parser.destroyed

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

let decode_key parser raw =
  let decoded =
    if parser.kitty_keyboard || parser.protocol_context.kitty_keyboard_enabled then
      match Kitty_keypress.parse raw with
      | Some value -> Some value
      | None -> Key_decoder.decode raw
    else Key_decoder.decode raw
  in
  decoded

let emit_key_bytes parser raw =
  match decode_key parser raw with
  | Some { key; modifiers; metadata } ->
      Stdlib.Queue.add (Key { raw; key; modifiers; metadata }) parser.events
  | None -> Stdlib.Queue.add (Response { protocol = Unknown; bytes = raw }) parser.events

let emit_key parser ~start ~end_exclusive =
  emit_key_bytes parser (copy_range parser ~start ~end_exclusive)

let emit_empty_key parser = emit_key_bytes parser Bytes.empty

let emit_sequence parser protocol ~start ~end_exclusive =
  let raw = copy_range parser ~start ~end_exclusive in
  match Mouse_decoder.decode parser.mouse raw with
  | Some { encoding; event } ->
      Stdlib.Queue.add (Mouse { raw; encoding; event }) parser.events
  | None ->
      (match decode_key parser raw with
      | Some { key; modifiers; metadata } ->
          Stdlib.Queue.add (Key { raw; key; modifiers; metadata }) parser.events
      | None -> Stdlib.Queue.add (Response { protocol; bytes = raw }) parser.events)

let emit_sequence_with_escape parser protocol ~start ~end_exclusive =
  let raw = copy_range_with_escape parser ~start ~end_exclusive in
  match Mouse_decoder.decode parser.mouse raw with
  | Some { encoding; event } ->
      Stdlib.Queue.add (Mouse { raw; encoding; event }) parser.events
  | None ->
      (match decode_key parser raw with
      | Some { key; modifiers; metadata } ->
          Stdlib.Queue.add (Key { raw; key; modifiers; metadata }) parser.events
      | None -> Stdlib.Queue.add (Response { protocol; bytes = raw }) parser.events)

let clear_paste_storage parser =
  parser.paste_parts <- [];
  parser.paste_total <- 0;
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
  let total_length = parser.paste_total + parser.paste_chunk_length in
  let result = Bytes.create total_length in
  let offset = ref 0 in
  List.iter
    (fun part ->
      let length = Bytes.length part in
      Bytes.blit part 0 result !offset length;
      offset := !offset + length)
    (List.rev parser.paste_parts);
  if Int.compare parser.paste_chunk_length 0 > 0 then
    Bytes.blit parser.paste_chunk 0 result !offset parser.paste_chunk_length;
  Stdlib.Queue.add (Paste result) parser.events;
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

let cancel_timeout parser =
  match parser.clock, parser.timeout_timer with
  | Some clock, Some timer ->
      Clock.cancel clock timer;
      parser.timeout_timer <- None
  | Some _, None | None, _ -> parser.timeout_timer <- None

let pixel_prefix bytes =
  let length = Bytes.length bytes in
  let prefix_matches index value =
    Int.compare index length < 0 && Int.equal (Bytes.get_uint8 bytes index) value
  in
  if Int.equal length 0 then false
  else if not (prefix_matches 0 escape) then false
  else if Int.equal length 1 then true
  else if not (prefix_matches 1 0x5b) then false
  else if Int.equal length 2 then true
  else if not (prefix_matches 2 0x34) then false
  else if Int.equal length 3 then true
  else if not (prefix_matches 3 0x3b) then false
  else if Int.equal length 4 then true
  else
    let cursor = ref 4 in
    let first_digits = ref false in
    while !cursor < length
          && Int.compare (Bytes.get_uint8 bytes !cursor) 0x30 >= 0
          && Int.compare (Bytes.get_uint8 bytes !cursor) 0x39 <= 0 do
      first_digits := true;
      incr cursor
    done;
    if not !first_digits then false
    else if Int.equal !cursor length then true
    else if not (Int.equal (Bytes.get_uint8 bytes !cursor) 0x3b) then false
    else begin
      incr cursor;
      if Int.equal !cursor length then true
      else
        let second_digits = ref false in
        while !cursor < length
              && Int.compare (Bytes.get_uint8 bytes !cursor) 0x30 >= 0
              && Int.compare (Bytes.get_uint8 bytes !cursor) 0x39 <= 0 do
          second_digits := true;
          incr cursor
        done;
        if not !second_digits then false
        else if Int.equal !cursor length then true
        else Int.equal !cursor (length - 1)
             && Int.equal (Bytes.get_uint8 bytes !cursor) (Char.code 't')
    end

let pixel_response_complete bytes =
  let length = Bytes.length bytes in
  length > 0 && Int.equal (Bytes.get_uint8 bytes (length - 1)) (Char.code 't')
  && pixel_prefix bytes

let pending_pixel_prefix parser =
  let length = Byte_queue.length parser.pending in
  if Int.equal length 0 then false
  else
    let bytes = copy_range parser ~start:0 ~end_exclusive:length in
    pixel_prefix bytes && not (pixel_response_complete bytes)

let is_ascii_digit value =
  Int.compare value (Char.code '0') >= 0
  && Int.compare value (Char.code '9') <= 0

(* Returns the number of semicolon-separated fields and the numeric prefix of
   the first field. A pending CSI with this shape may still become a Kitty
   Unicode key, a special key, or one of the renderer's CPR replies. *)
let parametric_prefix bytes =
  let length = Bytes.length bytes in
  if length <= 2
     || not (Int.equal (Bytes.get_uint8 bytes 0) escape)
     || not (Int.equal (Bytes.get_uint8 bytes 1) 0x5b)
  then None
  else
    let valid = ref true in
    let semicolons = ref 0 in
    let field_has_digit = ref false in
    let first_field = ref true in
    let first_component = ref true in
    let first_has_digit = ref false in
    let first_value = ref 0 in
    for index = 2 to length - 1 do
      let value = Bytes.get_uint8 bytes index in
      if is_ascii_digit value then begin
        field_has_digit := true;
        if !first_field then begin
          first_has_digit := true;
          if !first_component then ()
          else first_value := (!first_value * 10) + (value - Char.code '0')
        end
      end
      else if Int.equal value 0x3a then begin
        if not !field_has_digit then valid := false;
        field_has_digit := false;
        first_component := false
      end
      else if Int.equal value 0x3b then begin
        if not !field_has_digit || Int.compare !semicolons 2 >= 0 then valid := false;
        semicolons := !semicolons + 1;
        first_field := false;
        first_component := true;
        field_has_digit := false
      end
      else valid := false
    done;
    if !valid && !first_has_digit && Int.compare !semicolons 0 > 0 then
      Some (!semicolons, Some !first_value)
    else None

let private_reply_prefix bytes =
  let length = Bytes.length bytes in
  if length < 3
     || not (Int.equal (Bytes.get_uint8 bytes 0) escape)
     || not (Int.equal (Bytes.get_uint8 bytes 1) 0x5b)
     || not (Int.equal (Bytes.get_uint8 bytes 2) 0x3f)
  then false
  else
    let valid = ref true in
    for index = 3 to length - 1 do
      let value = Bytes.get_uint8 bytes index in
      if not (is_ascii_digit value || Int.equal value 0x3b || Int.equal value 0x24)
      then valid := false
    done;
    !valid

let pending_protocol_is_deferred parser =
  let length = Byte_queue.length parser.pending in
  if Int.equal length 0 then false
  else
    let bytes = copy_range parser ~start:0 ~end_exclusive:length in
    if parser.protocol_context.pixel_resolution_query_active
       && pending_pixel_prefix parser
    then true
    else if parser.protocol_context.private_capability_replies_active
            && private_reply_prefix bytes
    then true
    else
      match parametric_prefix bytes with
      | None -> false
      | Some (semicolons, first_value) ->
          (parser.protocol_context.kitty_keyboard_enabled
           && Int.compare semicolons 0 > 0)
          || (parser.protocol_context.explicit_width_cpr_active
             && Int.equal semicolons 1
             && Option.equal Int.equal first_value (Some 1))
          || (parser.protocol_context.startup_cursor_cpr_active
             && Int.equal semicolons 1)

let force_flush_pending parser =
  if not parser.paste_active
     && Int.compare (Byte_queue.length parser.pending) 0 > 0
     && not (pending_protocol_is_deferred parser)
  then begin
    parser.force_flush <- true;
    pump_pending parser;
    parser.force_flush <- false
  end

let cancel_and_arm_timeout parser =
  cancel_timeout parser;
  match parser.clock with
  | Some clock
    when parser.arm_timeouts
         && not parser.pending_timeout_paused
         && not parser.destroyed
         && not parser.paste_active
         && Int.compare (Byte_queue.length parser.pending) 0 > 0 ->
      let delay = float_of_int parser.timeout_ms /. 1000.0 in
      parser.timeout_timer <-
        Some
          (Clock.schedule clock ~delay (fun () ->
               parser.timeout_timer <- None;
               if not parser.destroyed && not parser.pending_timeout_paused then begin
                 if not (pending_protocol_is_deferred parser)
                 then force_flush_pending parser;
                 Option.iter (fun callback -> callback ()) parser.on_timeout_flush
               end))
  | Some _ | None -> ()

let protocol_context parser = parser.protocol_context

let update_protocol_context parser value =
  if not parser.destroyed then begin
    parser.protocol_context <- value;
    if Int.compare (Byte_queue.length parser.pending) 0 > 0
       && not (pending_protocol_is_deferred parser)
    then force_flush_pending parser;
    cancel_and_arm_timeout parser
  end

let has_pending_pixel_resolution_response parser =
  not parser.destroyed
  && parser.protocol_context.pixel_resolution_query_active
  && pending_pixel_prefix parser

let pause_pending_timeout parser =
  if not parser.destroyed then begin
    parser.pending_timeout_paused <- true;
    cancel_timeout parser
  end

let resume_pending_timeout parser =
  if not parser.destroyed then begin
    parser.pending_timeout_paused <- false;
    cancel_and_arm_timeout parser
  end

let reset_mouse_state parser =
  if not parser.destroyed then Mouse_decoder.reset parser.mouse

let looks_like_cursor_cpr bytes =
  let length = Bytes.length bytes in
  if length < 3 || not (Int.equal (Bytes.get_uint8 bytes 0) escape)
     || not (Int.equal (Bytes.get_uint8 bytes 1) 0x5b)
  then false
  else
    let valid = ref true in
    for index = 2 to length - 1 do
      let value = Bytes.get_uint8 bytes index in
      if not ((Int.compare value 0x30 >= 0 && Int.compare value 0x39 <= 0)
              || Int.equal value 0x3b || Int.equal value (Char.code 'R'))
      then valid := false
    done;
    !valid

let abort_pending_startup_cursor_cpr parser =
  if not parser.destroyed && parser.protocol_context.startup_cursor_cpr_active then begin
    let length = Byte_queue.length parser.pending in
    if Int.compare length 0 > 0 then begin
      let bytes = copy_range parser ~start:0 ~end_exclusive:length in
      if looks_like_cursor_cpr bytes then begin
        Byte_queue.clear parser.pending;
        parser.state <- Ground;
        parser.just_flushed_esc <- false;
        reset_unit parser
      end
    end;
    cancel_and_arm_timeout parser
  end

let push_with parser ~source_size ~get ~append ~off ~len =
  if parser.destroyed then Error Destroyed
  else if not (valid_range ~size:source_size ~off ~len) then
    queue_error Byte_queue.Invalid_range
  else if Int.equal len 0 then (
    emit_empty_key parser;
    Ok ())
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
    cancel_and_arm_timeout parser;
    match !failure with
    | None -> Ok ()
    | Some error -> queue_error error

let push parser ~source ~off ~len =
  push_with parser ~source_size:(Bigarray.Array1.dim source)
    ~get:(Bigarray.Array1.get source)
    ~append:(fun ~off ~len -> Byte_queue.append parser.pending ~source ~off ~len)
    ~off ~len

let push_chars parser ~source ~off ~len =
  push_with parser ~source_size:(Bigarray.Array1.dim source)
    ~get:(fun index -> Char.code (Bigarray.Array1.get source index))
    ~append:(fun ~off ~len ->
      Byte_queue.append_chars parser.pending ~source ~off ~len)
    ~off ~len

let push_bytes parser ~source ~off ~len =
  push_with parser ~source_size:(Bytes.length source) ~get:(Bytes.get_uint8 source)
    ~append:(fun ~off ~len ->
      Byte_queue.append_bytes parser.pending ~source ~off ~len)
    ~off ~len

let read parser =
  if parser.destroyed || Stdlib.Queue.is_empty parser.events then None
  else Some (Stdlib.Queue.take parser.events)

let drain parser callback =
  while not parser.destroyed && not (Stdlib.Queue.is_empty parser.events) do
    callback (Stdlib.Queue.take parser.events)
  done

let flush_timeout parser =
  if not parser.destroyed && not parser.pending_timeout_paused
     && not (pending_protocol_is_deferred parser)
  then begin
    cancel_timeout parser;
    force_flush_pending parser
  end

let reset parser =
  if not parser.destroyed then begin
    cancel_timeout parser;
    Byte_queue.clear parser.pending;
    Stdlib.Queue.clear parser.events;
    parser.state <- Ground;
    parser.just_flushed_esc <- false;
    parser.paste_active <- false;
    parser.pending_timeout_paused <- false;
    Mouse_decoder.reset parser.mouse;
    clear_paste_storage parser;
    reset_unit parser
  end

let destroy parser =
  if not parser.destroyed then begin
    cancel_timeout parser;
    parser.destroyed <- true;
    Byte_queue.clear parser.pending;
    Stdlib.Queue.clear parser.events;
    parser.state <- Ground;
    parser.just_flushed_esc <- false;
    parser.paste_active <- false;
    Mouse_decoder.reset parser.mouse;
    clear_paste_storage parser;
    reset_unit parser
  end
