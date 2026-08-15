type timer = int

type t = {
  now_function : unit -> float;
  schedule_function : delay:float -> (unit -> unit) -> timer;
  cancel_function : timer -> unit;
}

let create ~now ~schedule ~cancel =
  { now_function = now; schedule_function = schedule; cancel_function = cancel }

let now clock = clock.now_function ()
let schedule clock ~delay callback = clock.schedule_function ~delay callback
let cancel clock timer = clock.cancel_function timer

type manual_timer = {
  id : int;
  due : float;
  callback : unit -> unit;
  mutable cancelled : bool;
}

type manual = {
  mutable current : float;
  mutable next_id : int;
  mutable timers : manual_timer list;
}

let manual () = { current = 0.0; next_id = 1; timers = [] }

let manual_clock owner =
  let schedule ~delay callback =
    let delay = if Float.compare delay 0.0 < 0 then 0.0 else delay in
    let id = owner.next_id in
    owner.next_id <- id + 1;
    owner.timers <- { id; due = owner.current +. delay; callback; cancelled = false } :: owner.timers;
    id
  in
  let cancel id =
    List.iter
      (fun timer -> if Int.equal timer.id id then timer.cancelled <- true)
      owner.timers
  in
  create ~now:(fun () -> owner.current) ~schedule ~cancel

let set owner value =
  if Float.is_finite value then owner.current <- value

let next_due owner =
  List.fold_left
    (fun best timer ->
      if timer.cancelled then best
      else
        match best with
        | None -> Some timer
        | Some current ->
            if Float.compare timer.due current.due < 0 then Some timer else best)
    None owner.timers

let remove_timer owner id =
  owner.timers <- List.filter (fun timer -> not (Int.equal timer.id id)) owner.timers

let run_due owner =
  let running = ref true in
  while !running do
    match next_due owner with
    | None -> running := false
    | Some timer when Float.compare timer.due owner.current > 0 -> running := false
    | Some timer ->
        remove_timer owner timer.id;
        if not timer.cancelled then timer.callback ()
  done

let advance owner delta =
  if Float.is_finite delta && Float.compare delta 0.0 >= 0 then begin
    owner.current <- owner.current +. delta;
    run_due owner
  end
