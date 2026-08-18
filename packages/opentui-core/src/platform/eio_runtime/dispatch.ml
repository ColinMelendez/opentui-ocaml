let drain ~queue ~handle =
  let draining = ref true in
  while !draining do
    match Lib.Event_queue.read queue with
    | Some event -> handle event
    | None -> draining := false
  done

(* Keep a continuously readable terminal from monopolising the owner domain.
   The reference processes one stream data callback at a time and returns to
   its event loop between callbacks. The queue adapter has no such callback
   boundary, so impose one explicitly while retaining FIFO delivery. *)
let max_events_per_turn = 64

let run ~queue ~wakeup ~handle =
  let processed = ref 0 in
  let handle_one event =
    handle event;
    incr processed;
    if Int.compare !processed max_events_per_turn >= 0 then begin
      processed := 0;
      if Int.compare (Lib.Event_queue.length queue) 0 > 0 then
        Eio.Fiber.yield ()
    end
  in
  while true do
    match Lib.Event_queue.read queue with
    | Some event -> handle_one event
    | None ->
        let observed = Wakeup.revision wakeup in
        (match Lib.Event_queue.read queue with
        | Some event -> handle_one event
        | None -> ignore (Wakeup.wait wakeup ~since:observed))
  done
