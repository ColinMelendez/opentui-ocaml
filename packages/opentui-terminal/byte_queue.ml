type buffer =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type char_buffer =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type t = {
  mutable storage : buffer;
  mutable start : int;
  mutable finish : int;
  max_capacity : int;
}

type error = Invalid_capacity | Invalid_range | Max_capacity

let default_initial_capacity = 256
let default_max_capacity = 64 * 1024

let message = function
  | Invalid_capacity -> "byte queue capacity must be positive and ordered"
  | Invalid_range -> "byte queue source or consume range is invalid"
  | Max_capacity -> "byte queue maximum capacity exceeded"

let pp formatter error = Format.pp_print_string formatter (message error)

let valid_capacity value = Int.compare value 0 > 0

let create ?(initial_capacity = default_initial_capacity)
    ?(max_capacity = default_max_capacity) () =
  if
    not (valid_capacity initial_capacity)
    || not (valid_capacity max_capacity)
    || Int.compare initial_capacity max_capacity > 0
  then Error Invalid_capacity
  else
    Ok
      {
        storage =
          Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
            initial_capacity;
        start = 0;
        finish = 0;
        max_capacity;
      }

let length queue = queue.finish - queue.start
let capacity queue = Bigarray.Array1.dim queue.storage
let max_capacity queue = queue.max_capacity

let valid_range ~size ~off ~len =
  Int.compare off 0 >= 0
  && Int.compare len 0 >= 0
  && Int.compare off size <= 0
  && Int.compare len (size - off) <= 0

let compact queue =
  let live_length = length queue in
  if Int.equal live_length 0 then (
    queue.start <- 0;
    queue.finish <- 0)
  else if not (Int.equal queue.start 0) then (
    for index = 0 to live_length - 1 do
      let value = Bigarray.Array1.get queue.storage (queue.start + index) in
      Bigarray.Array1.set queue.storage index value
    done;
    queue.start <- 0;
    queue.finish <- live_length)

let grow queue required_length =
  let next_capacity = ref (capacity queue) in
  while Int.compare !next_capacity required_length < 0 do
    if Int.compare !next_capacity (queue.max_capacity / 2) > 0 then
      next_capacity := queue.max_capacity
    else next_capacity := !next_capacity * 2
  done;
  let next_storage =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      !next_capacity
  in
  let live_length = length queue in
  for index = 0 to live_length - 1 do
    let value = Bigarray.Array1.get queue.storage (queue.start + index) in
    Bigarray.Array1.set next_storage index value
  done;
  queue.storage <- next_storage;
  queue.start <- 0;
  queue.finish <- live_length

let ensure_space queue additional_length =
  let current_length = length queue in
  if Int.compare additional_length (queue.max_capacity - current_length) > 0
  then Error Max_capacity
  else (
    let required_length = current_length + additional_length in
    if Int.compare (capacity queue - queue.finish) additional_length < 0 then
      compact queue;
    if Int.compare (capacity queue - queue.finish) additional_length < 0 then
      grow queue required_length;
    Ok ())

let append_with queue ~source_size ~get ~off ~len =
  if not (valid_range ~size:source_size ~off ~len) then Error Invalid_range
  else if Int.equal len 0 then Ok ()
  else
    match ensure_space queue len with
    | Error error -> Error error
    | Ok () ->
        for index = 0 to len - 1 do
          Bigarray.Array1.set queue.storage (queue.finish + index)
            (get (off + index))
        done;
        queue.finish <- queue.finish + len;
        Ok ()

let append queue ~source ~off ~len =
  append_with queue ~source_size:(Bigarray.Array1.dim source)
    ~get:(Bigarray.Array1.get source) ~off ~len

let append_chars queue ~source ~off ~len =
  append_with queue ~source_size:(Bigarray.Array1.dim source)
    ~get:(fun index -> Char.code (Bigarray.Array1.get source index)) ~off ~len

let append_bytes queue ~source ~off ~len =
  append_with queue ~source_size:(Bytes.length source)
    ~get:(Bytes.get_uint8 source) ~off ~len

let get queue index =
  if Int.compare index 0 < 0 || Int.compare index (length queue) >= 0 then None
  else Some (Bigarray.Array1.get queue.storage (queue.start + index))

let consume queue count =
  if Int.compare count 0 < 0 || Int.compare count (length queue) > 0 then
    Error Invalid_range
  else if Int.equal count 0 then Ok ()
  else (
    queue.start <- queue.start + count;
    if Int.equal queue.start queue.finish then (
      queue.start <- 0;
      queue.finish <- 0)
    else if Int.compare queue.start (capacity queue / 2) >= 0 then compact queue;
    Ok ())

let clear queue =
  queue.start <- 0;
  queue.finish <- 0
