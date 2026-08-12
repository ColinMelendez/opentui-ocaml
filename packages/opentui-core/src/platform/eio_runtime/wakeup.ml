type t = {
  condition : Eio.Condition.t;
  mutable revision : int64;
}

let create () = { condition = Eio.Condition.create (); revision = 0L }
let revision wakeup = wakeup.revision

let notify wakeup =
  wakeup.revision <-
    if Int64.equal wakeup.revision Int64.max_int then 0L
    else Int64.add wakeup.revision 1L;
  Eio.Condition.broadcast wakeup.condition

let wait wakeup ~since =
  Eio.Condition.loop_no_mutex wakeup.condition (fun () ->
      if Int64.equal wakeup.revision since then None
      else Some wakeup.revision)

let push wakeup ~queue event =
  match Lib.Event_queue.push queue event with
  | Error error -> Error error
  | Ok () ->
      notify wakeup;
      Ok ()
