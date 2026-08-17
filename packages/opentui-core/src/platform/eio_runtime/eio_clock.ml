type timer_state = {
  id : Lib.Clock.timer;
  cancellation : unit Eio.Promise.t;
  cancellation_resolver : unit Eio.Promise.u;
  mutable cancelled : bool;
  mutable finished : bool;
}

type mono_clock = Mono_clock : 'a Eio.Time.Mono.t -> mono_clock

type error = Closed | Wrong_domain | Switch_mismatch

type t = {
  sw : Eio.Switch.t;
  domain_id : int;
  mono_clock : mono_clock;
  origin : Mtime.t;
  mutable timers : timer_state list;
  mutable closed : bool;
  mutable lib_clock : Lib.Clock.t option;
}

let current_domain_id () = (Domain.self () :> int)

let owns_domain clock = Int.equal (current_domain_id ()) clock.domain_id

let require_owner clock operation =
  if not (owns_domain clock) then
    invalid_arg (operation ^ " must run in the Eio clock's owner domain")

let require_open clock operation =
  if clock.closed then invalid_arg (operation ^ " cannot use a closed Eio clock")

let message = function
  | Closed -> "the Eio clock is closed"
  | Wrong_domain -> "the Eio clock must be used from its owner domain"
  | Switch_mismatch -> "the Eio switch is not the clock's owner switch"

let pp formatter error = Format.pp_print_string formatter (message error)

let seconds_between origin current =
  Mtime.Span.to_float_ns (Mtime.span origin current) /. 1e9

let now_unchecked clock =
  let Mono_clock mono_clock = clock.mono_clock in
  seconds_between clock.origin
    (Eio.Time.Mono.now mono_clock)

let now clock =
  require_owner clock "Eio_clock.now";
  require_open clock "Eio_clock.now";
  now_unchecked clock

let normalise_delay delay =
  if Float.is_nan delay || Float.compare delay 0.0 < 0 then 0.0 else delay

let remove_timer clock id =
  clock.timers <-
    List.filter
      (fun timer -> not (Lib.Clock.equal_timer timer.id id))
      clock.timers

let cancel_timer timer =
  if not timer.cancelled && not timer.finished then begin
    timer.cancelled <- true;
    ignore (Eio.Promise.try_resolve timer.cancellation_resolver ())
  end

let run_timer clock timer ~delay callback =
  let Mono_clock mono_clock = clock.mono_clock in
  let outcome =
    Eio.Fiber.first
      (fun () ->
        Eio.Time.Mono.sleep mono_clock delay;
        `Elapsed)
      (fun () ->
        Eio.Promise.await timer.cancellation;
        `Cancelled)
  in
  match outcome with
  | `Cancelled ->
      timer.finished <- true;
      remove_timer clock timer.id
  | `Elapsed ->
      if not clock.closed && not timer.cancelled && not timer.finished then begin
        timer.finished <- true;
        remove_timer clock timer.id;
        callback ()
      end
      else begin
        timer.finished <- true;
        remove_timer clock timer.id
      end

let schedule clock ~delay callback =
  require_owner clock "Lib.Clock.schedule";
  require_open clock "Lib.Clock.schedule";
  let id = Lib.Clock.fresh_timer () in
  let cancellation, cancellation_resolver = Eio.Promise.create () in
  let timer =
    {
      id;
      cancellation;
      cancellation_resolver;
      cancelled = false;
      finished = false;
    }
  in
  clock.timers <- timer :: clock.timers;
  Eio.Fiber.fork ~sw:clock.sw (fun () ->
      run_timer clock timer ~delay:(normalise_delay delay) callback);
  id

let cancel clock id =
  require_owner clock "Lib.Clock.cancel";
  List.iter
    (fun timer -> if Lib.Clock.equal_timer timer.id id then cancel_timer timer)
    clock.timers

let close_unchecked clock =
  if not clock.closed then begin
    clock.closed <- true;
    List.iter cancel_timer clock.timers;
    clock.timers <- []
  end

let create ~sw ~mono_clock =
  let clock =
    {
      sw;
      domain_id = current_domain_id ();
      mono_clock = Mono_clock mono_clock;
      origin = Eio.Time.Mono.now mono_clock;
      timers = [];
      closed = false;
      lib_clock = None;
    }
  in
  Eio.Switch.on_release sw (fun () -> close_unchecked clock);
  clock

let owns_switch clock switch = clock.sw == switch

let check_owner clock =
  if not (owns_domain clock) then Error Wrong_domain
  else if clock.closed then Error Closed
  else Ok ()

let check clock ~sw =
  match check_owner clock with
  | Error error -> Error error
  | Ok () when not (owns_switch clock sw) -> Error Switch_mismatch
  | Ok () -> Ok ()

let lib_clock clock =
  require_owner clock "Eio_clock.lib_clock";
  require_open clock "Eio_clock.lib_clock";
  match clock.lib_clock with
  | Some value -> value
  | None ->
      let value =
        Lib.Clock.create
          ~now:(fun () -> now clock)
          ~schedule:(fun ~delay callback -> schedule clock ~delay callback)
          ~cancel:(fun id -> cancel clock id)
      in
      clock.lib_clock <- Some value;
      value

let owns_lib_clock clock value =
  require_owner clock "Eio_clock.owns_lib_clock";
  match clock.lib_clock with
  | Some current -> current == value
  | None -> false

let sleep_until clock ~deadline =
  require_owner clock "Eio_clock.sleep_until";
  require_open clock "Eio_clock.sleep_until";
  let delay = deadline -. now_unchecked clock in
  if Float.compare delay 0.0 > 0 then begin
    let Mono_clock mono_clock = clock.mono_clock in
    Eio.Time.Mono.sleep mono_clock delay
  end

let close clock =
  if not (owns_domain clock) then Error Wrong_domain
  else begin
    close_unchecked clock;
    Ok ()
  end
