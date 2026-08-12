type event =
  | Input of Input_decoder.event
  | Resize of Terminal_size.t

type error =
  | Invalid_capacity
  | Full

type t = {
  slots : event option array;
  mutable head : int;
  mutable tail : int;
  mutable length : int;
}

let default_capacity = 64

let message = function
  | Invalid_capacity -> "terminal event queue capacity must be positive"
  | Full -> "terminal event queue is full"

let pp formatter error = Format.pp_print_string formatter (message error)

let create ?(capacity = default_capacity) () =
  if Int.compare capacity 0 <= 0
     || Int.compare capacity Sys.max_array_length > 0
  then Error Invalid_capacity
  else
    Ok
      {
        slots = Array.make capacity None;
        head = 0;
        tail = 0;
        length = 0;
      }

let capacity queue = Array.length queue.slots
let length queue = queue.length

let advance queue index =
  let next = index + 1 in
  if Int.equal next (capacity queue) then 0 else next

let is_resize = function
  | Resize _ -> true
  | Input _ -> false

let is_mouse_motion = function
  | Input (Input_decoder.Mouse mouse) ->
      (match mouse.Mouse_decoder.kind with
      | Mouse_decoder.Move
      | Mouse_decoder.Drag -> true
      | Mouse_decoder.Down
      | Mouse_decoder.Up
      | Mouse_decoder.Scroll -> false)
  | Input (Input_decoder.Key _)
  | Input (Input_decoder.Sequence _)
  | Input (Input_decoder.Paste _)
  | Resize _ -> false

let replace_pending queue matches replacement =
  let index = ref queue.head in
  let remaining = ref queue.length in
  let replaced = ref false in
  while Int.compare !remaining 0 > 0 && not !replaced do
    (match queue.slots.(!index) with
    | Some event when matches event ->
        queue.slots.(!index) <- Some replacement;
        replaced := true
    | Some _ | None -> ());
    index := advance queue !index;
    remaining := !remaining - 1
  done;
  !replaced

let enqueue queue event =
  if Int.equal queue.length (capacity queue) then Error Full
  else (
    queue.slots.(queue.tail) <- Some event;
    queue.tail <- advance queue queue.tail;
    queue.length <- queue.length + 1;
    Ok ())

let push queue event =
  if is_resize event then
    if replace_pending queue is_resize event then Ok () else enqueue queue event
  else if is_mouse_motion event then
    if replace_pending queue is_mouse_motion event then Ok ()
    else enqueue queue event
  else enqueue queue event

let read queue =
  if Int.equal queue.length 0 then None
  else
    let event = queue.slots.(queue.head) in
    queue.slots.(queue.head) <- None;
    queue.head <- advance queue queue.head;
    queue.length <- queue.length - 1;
    event

let clear queue =
  Array.fill queue.slots 0 (capacity queue) None;
  queue.head <- 0;
  queue.tail <- 0;
  queue.length <- 0
