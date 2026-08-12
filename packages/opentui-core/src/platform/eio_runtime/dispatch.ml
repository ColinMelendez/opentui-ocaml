let drain ~queue ~handle =
  let draining = ref true in
  while !draining do
    match Lib.Event_queue.read queue with
    | Some event -> handle event
    | None -> draining := false
  done

let run ~queue ~wakeup ~handle =
  while true do
    match Lib.Event_queue.read queue with
    | Some event -> handle event
    | None ->
        let observed = Wakeup.revision wakeup in
        (match Lib.Event_queue.read queue with
        | Some event -> handle event
        | None -> ignore (Wakeup.wait wakeup ~since:observed))
  done
