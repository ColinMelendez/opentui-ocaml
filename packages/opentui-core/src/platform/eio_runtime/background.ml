type error =
  | Invalid_worker_count of int
  | Closed
  | Wrong_domain

type t = {
  pool : Eio.Executor_pool.t;
  switch : Eio.Switch.t;
  closed : bool Atomic.t;
}

type submitter = {
  background : t;
  switch : Eio.Switch.t;
  domain_id : int;
  closed : bool Atomic.t;
}

type job = {
  state : int Atomic.t;
  cancellation : unit Eio.Promise.t;
  cancellation_resolver : unit Eio.Promise.u;
}

let pending = 0
let cancelled = 1
let delivering = 2
let delivered = 3

let message = function
  | Invalid_worker_count count ->
      Printf.sprintf
        "background worker count %d is invalid for the recommended domain limit"
        count
  | Closed -> "background application or submission switch is closed"
  | Wrong_domain ->
      "background submitter must be used from its binding Eio domain"

let pp formatter error = Format.pp_print_string formatter (message error)

let switch_is_open switch =
  match Eio.Switch.get_error switch with None -> true | Some _ -> false

let background_is_open (background : t) =
  not (Atomic.get background.closed) && switch_is_open background.switch

let submitter_is_open (submitter : submitter) =
  not (Atomic.get submitter.closed)
  && background_is_open submitter.background
  && switch_is_open submitter.switch

let current_domain_id () = (Domain.self () :> int)

let max_worker_count () =
  let recommended = Domain.recommended_domain_count () in
  if Int.compare recommended 1 <= 0 then 0 else recommended - 1

let create ~sw ~domain_mgr ~worker_count =
  if Int.compare worker_count 0 <= 0
     || Int.compare worker_count (max_worker_count ()) > 0
  then Error (Invalid_worker_count worker_count)
  else if not (switch_is_open sw) then Error Closed
  else
    let pool =
      Eio.Executor_pool.create ~sw ~domain_count:worker_count domain_mgr
    in
    let background =
      { pool; switch = sw; closed = Atomic.make false }
    in
    Eio.Switch.on_release sw (fun () -> Atomic.set background.closed true);
    Ok background

let bind background ~sw =
  if not (background_is_open background) || not (switch_is_open sw) then
    Error Closed
  else
    let submitter =
      {
        background;
        switch = sw;
        domain_id = current_domain_id ();
        closed = Atomic.make false;
      }
    in
    (try
       Eio.Switch.on_release sw (fun () -> Atomic.set submitter.closed true);
       Ok submitter
     with
     | Invalid_argument _ -> Error Closed)

let cancel job =
  if Atomic.compare_and_set job.state pending cancelled then
    ignore (Eio.Promise.try_resolve job.cancellation_resolver ())

let submit submitter ~work ~on_complete =
  if not (submitter_is_open submitter) then Error Closed
  else if not (Int.equal (current_domain_id ()) submitter.domain_id) then
    Error Wrong_domain
  else
    let cancellation, cancellation_resolver = Eio.Promise.create () in
    let job =
      {
        state = Atomic.make pending;
        cancellation;
        cancellation_resolver;
      }
    in
    let result, result_resolver = Eio.Promise.create () in
    let start_fibers () =
      Eio.Fiber.fork ~sw:submitter.switch (fun () ->
          match
            Eio.Executor_pool.submit submitter.background.pool ~weight:1.0 work
          with
          | Ok value -> Eio.Promise.resolve result_resolver value
          | Error exception_value -> raise exception_value);
      Eio.Fiber.fork ~sw:submitter.switch (fun () ->
          match
            Eio.Fiber.first
              (fun () -> `Completed (Eio.Promise.await result))
              (fun () ->
                Eio.Promise.await job.cancellation;
                `Cancelled)
          with
          | `Cancelled -> ()
          | `Completed value ->
              if Atomic.compare_and_set job.state pending delivering then begin
                Eio.Fiber.check ();
                on_complete value;
                Atomic.set job.state delivered
              end)
    in
    (try
       start_fibers ();
       Ok job
     with
     | Invalid_argument _ when not (submitter_is_open submitter) -> Error Closed)
