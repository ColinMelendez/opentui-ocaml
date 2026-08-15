type ('a, 'e) t = {
  auto_process : bool;
  schedule : (unit -> unit) -> unit;
  process : 'a -> (unit, 'e) result;
  on_error : 'e -> unit;
  queue : 'a Stdlib.Queue.t;
  mutable processing : bool;
  mutable scheduled : bool;
  mutable schedule_generation : int;
}

let create ?(auto_process = true) ~schedule ~process ~on_error () =
  { auto_process; schedule; process; on_error; queue = Stdlib.Queue.create (); processing = false; scheduled = false; schedule_generation = 0 }

let run owner =
  owner.processing <- true;
  owner.scheduled <- false;
  while not (Stdlib.Queue.is_empty owner.queue) do
    let item = Stdlib.Queue.take owner.queue in
    match owner.process item with Ok () -> () | Error error -> owner.on_error error
  done;
  owner.processing <- false

let enqueue owner item =
  Stdlib.Queue.add item owner.queue;
  if owner.auto_process && not owner.processing && not owner.scheduled then begin
    owner.processing <- true;
    owner.scheduled <- true;
    owner.schedule_generation <- owner.schedule_generation + 1;
    let generation = owner.schedule_generation in
    owner.schedule (fun () ->
        if Int.equal generation owner.schedule_generation then run owner)
  end

let clear owner =
  Stdlib.Queue.clear owner.queue;
  if owner.scheduled then owner.processing <- false;
  owner.scheduled <- false;
  owner.schedule_generation <- owner.schedule_generation + 1

let is_processing owner = owner.processing
let size owner = Stdlib.Queue.length owner.queue
