type timer_state = {
  id : Lib.Clock.timer;
  cancellation : unit Eio.Promise.t;
  cancellation_resolver : unit Eio.Promise.u;
  mutable cancelled : bool;
  mutable finished : bool;
}

type mono_clock = Mono_clock : 'a Eio.Time.Mono.t -> mono_clock

type t = {
  sw : Eio.Switch.t;
  mono_clock : mono_clock;
  origin : Mtime.t;
  mutable timers : timer_state list;
  mutable closed : bool;
  mutable lib_clock : Lib.Clock.t option;
}

let seconds_between origin current =
  Mtime.Span.to_float_ns (Mtime.span origin current) /. 1e9

let now clock =
  let Mono_clock mono_clock = clock.mono_clock in
  seconds_between clock.origin
    (Eio.Time.Mono.now mono_clock)

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
  let id = Lib.Clock.fresh_timer () in
  let cancellation, cancellation_resolver = Eio.Promise.create () in
  let timer =
    {
      id;
      cancellation;
      cancellation_resolver;
      cancelled = clock.closed;
      finished = false;
    }
  in
  if not clock.closed then begin
    clock.timers <- timer :: clock.timers;
    Eio.Fiber.fork ~sw:clock.sw (fun () ->
        run_timer clock timer ~delay:(normalise_delay delay) callback)
  end;
  id

let cancel clock id =
  List.iter
    (fun timer -> if Lib.Clock.equal_timer timer.id id then cancel_timer timer)
    clock.timers

let close clock =
  if not clock.closed then begin
    clock.closed <- true;
    List.iter cancel_timer clock.timers;
    clock.timers <- []
  end

let create ~sw ~mono_clock =
  let clock =
    {
      sw;
      mono_clock = Mono_clock mono_clock;
      origin = Eio.Time.Mono.now mono_clock;
      timers = [];
      closed = false;
      lib_clock = None;
    }
  in
  Eio.Switch.on_release sw (fun () -> close clock);
  clock

let lib_clock clock =
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
  match clock.lib_clock with
  | Some current -> current == value
  | None -> false

let sleep_until clock ~deadline =
  let delay = deadline -. now clock in
  if Float.compare delay 0.0 > 0 then begin
    let Mono_clock mono_clock = clock.mono_clock in
    Eio.Time.Mono.sleep mono_clock delay
  end
