module Error = struct
  type phase = Admission | Connect | Read | Cleanup | Retry

  type failure = Unavailable | Transport | Protocol | Invalid | Exception of exn

  type reason =
    | Closed
    | Wrong_domain
    | Switch_mismatch
    | Owner_closed
    | Invalid_options
    | Cancelled
    | Stale_generation
    | Connect_failure of failure
    | Read_failure of failure
    | Retry_exhausted of failure
    | Retry_policy_failure of exn
    | Cleanup_failure of failure

  type t = {
    phase : phase;
    generation : int;
    attempt : int;
    retry : int;
    reason : reason;
  }

  let failure_message = function
    | Unavailable -> "unavailable"
    | Transport -> "transport failure"
    | Protocol -> "protocol failure"
    | Invalid -> "invalid source"
    | Exception exception_value ->
        "source callback raised: " ^ Printexc.to_string exception_value

  let phase_message = function
    | Admission -> "admission"
    | Connect -> "connect"
    | Read -> "read"
    | Cleanup -> "cleanup"
    | Retry -> "retry"

  let reason_message = function
    | Closed -> "the audio owner is closed"
    | Wrong_domain -> "the audio operation must run in its owner domain"
    | Switch_mismatch -> "the owner capability belongs to another switch"
    | Owner_closed -> "the audio owner is closed"
    | Invalid_options -> "audio retry options are invalid"
    | Cancelled -> "the audio stream was cancelled"
    | Stale_generation -> "the audio source result belongs to a stale generation"
    | Connect_failure failure ->
        "connection failed: " ^ failure_message failure
    | Read_failure failure -> "source read failed: " ^ failure_message failure
    | Retry_exhausted failure ->
        "retry budget exhausted after: " ^ failure_message failure
    | Retry_policy_failure exception_value ->
        "retry policy raised: " ^ Printexc.to_string exception_value
    | Cleanup_failure failure ->
        "connection cleanup failed: " ^ failure_message failure

  let message error =
    Printf.sprintf "%s attempt %d generation %d retry %d: %s"
      (phase_message error.phase) error.attempt error.generation error.retry
      (reason_message error.reason)

  let pp formatter error = Format.pp_print_string formatter (message error)

  let admission reason =
    { phase = Admission; generation = 0; attempt = 0; retry = 0; reason }

  let with_context ~phase ~generation ~attempt ~retry reason =
    { phase; generation; attempt; retry; reason }
end

type diagnostic =
  | Observer_exception of exn
  | Unobserved_error of Error.t
  | Cleanup_error of Error.t

type cancellation = {
  mutable cancelled : bool;
  cancellation : unit Eio.Promise.t;
  resolver : unit Eio.Promise.u;
}

module Cancellation = struct
  type t = cancellation

  let create () =
    let cancellation, resolver = Eio.Promise.create () in
    { cancelled = false; cancellation; resolver }

  let is_cancelled cancellation = cancellation.cancelled

  let await cancellation = Eio.Promise.await cancellation.cancellation

  let cancel cancellation =
    if not cancellation.cancelled then begin
      cancellation.cancelled <- true;
      ignore (Eio.Promise.try_resolve cancellation.resolver ())
    end
end

let cancel_cancellation = Cancellation.cancel
let create_cancellation = Cancellation.create

module Options = struct
  type retry_phase = Connect | Read | End

  type t = {
    max_retries : int;
    initial_delay : float;
    max_delay : float;
    backoff : float;
    retry_on_end : bool;
    should_retry : retry:int -> phase:retry_phase -> error:Error.t -> bool;
    on_diagnostic : diagnostic -> unit;
  }

  let ignore_diagnostic diagnostic =
    match diagnostic with
    | Observer_exception exception_value -> ignore exception_value
    | Unobserved_error error -> ignore error
    | Cleanup_error error -> ignore error

  let default =
    {
      max_retries = 0;
      initial_delay = 0.1;
      max_delay = 30.0;
      backoff = 2.0;
      retry_on_end = false;
      should_retry =
        (fun ~retry ~phase ~error ->
          ignore retry;
          ignore phase;
          ignore error;
          true);
      on_diagnostic = ignore_diagnostic;
    }

  let valid_delay value =
    not (Float.is_nan value)
    && not (Float.is_infinite value)
    && Float.compare value 0.0 >= 0

  let create ?(max_retries = default.max_retries)
      ?(initial_delay = default.initial_delay) ?(max_delay = default.max_delay)
      ?(backoff = default.backoff) ?(retry_on_end = default.retry_on_end)
      ?(should_retry = default.should_retry)
      ?(on_diagnostic = default.on_diagnostic) () =
    if Int.compare max_retries 0 < 0
       || not (valid_delay initial_delay)
       || not (valid_delay max_delay)
       || Float.compare max_delay initial_delay < 0
       || not (valid_delay backoff)
       || Float.compare backoff 1.0 < 0
    then Error (Error.admission Error.Invalid_options)
    else
      Ok
        {
          max_retries;
          initial_delay;
          max_delay;
          backoff;
          retry_on_end;
          should_retry;
          on_diagnostic;
        }
end

module Owner = struct
  type t = {
    switch : Eio.Switch.t;
    domain_id : int;
    sleep : float -> unit;
    mutable closed : bool;
  }

  let current_domain_id () = (Domain.self () :> int)

  let switch_is_open switch = Option.is_none (Eio.Switch.get_error switch)

  let create ~sw ~clock =
    if not (switch_is_open sw) then Error (Error.admission Error.Closed)
    else
      let owner =
        {
          switch = sw;
          domain_id = current_domain_id ();
          sleep = (fun delay -> Eio.Time.Mono.sleep clock delay);
          closed = false;
        }
      in
      (try
         Eio.Switch.on_release sw (fun () -> owner.closed <- true);
         Ok owner
       with
      | Invalid_argument _ ->
          owner.closed <- true;
          Error (Error.admission Error.Closed))

  let is_current owner =
    Int.equal (current_domain_id ()) owner.domain_id
    && not owner.closed
    && switch_is_open owner.switch

  let check owner =
    if not (Int.equal (current_domain_id ()) owner.domain_id) then
      Error (Error.admission Error.Wrong_domain)
    else if owner.closed || not (switch_is_open owner.switch) then
      Error (Error.admission Error.Owner_closed)
    else Ok ()

  let switch owner = owner.switch
  let sleep owner delay = owner.sleep delay
end

type engine_state = Open | Closing | Closed

type child = {
  id : int;
  close : unit -> (unit, Error.t) result;
}

type engine = {
  owner : Owner.t;
  mutable state : engine_state;
  mutable next_child_id : int;
  mutable children : child list;
}

module Engine = struct
  type t = engine
  type state = engine_state = Open | Closing | Closed

  let create ~owner =
    match Owner.check owner with
    | Error error -> Error error
    | Ok () -> Ok { owner; state = Open; next_child_id = 0; children = [] }

  let owner engine = engine.owner

  let state engine =
    match Owner.check engine.owner with
    | Error error -> Error error
    | Ok () -> Ok engine.state

  let add_child engine close =
    match Owner.check engine.owner with
    | Error error -> Error error
    | Ok () ->
        (match engine.state with
        | Open ->
            let id = engine.next_child_id in
            engine.next_child_id <- id + 1;
            engine.children <- { id; close } :: engine.children;
            Ok id
        | Closing | Closed -> Error (Error.admission Error.Closed))

  let remove_child engine id =
    engine.children <-
      List.filter (fun child -> not (Int.equal child.id id)) engine.children

  let close engine =
    match Owner.check engine.owner with
    | Error error -> Error error
    | Ok () ->
        (match engine.state with
        | Closed -> Ok ()
        | Open | Closing ->
            engine.state <- Closing;
            let first_error = ref None in
            let children = engine.children in
            List.iter
              (fun child ->
                match child.close () with
                | Ok () -> ()
                | Error error ->
                    if Option.is_none !first_error then
                      first_error := Some error)
              children;
            (match engine.children with
            | [] -> engine.state <- Closed
            | _ -> ());
            (match !first_error with
            | Some error -> Error error
            | None ->
                (match engine.state with
                | Closed -> Ok ()
                | Open | Closing -> Error (Error.admission Error.Closed))))

  let register = add_child
  let unregister = remove_child
end

module Stream = struct
  type state =
    | Initializing
    | Buffering
    | Playing
    | Reconnecting
    | Ended
    | Errored
    | Disposed

  type terminal =
    | Ended_terminal
    | Errored_terminal of Error.t
    | Disposed_terminal

  type 'metadata input =
    | Data of bytes
    | Metadata of 'metadata option
    | End

  type 'metadata metadata_event = {
    generation : int;
    attempt : int;
    value : 'metadata option;
  }

  type reconnecting_event = {
    generation : int;
    attempt : int;
    retry : int;
    phase : Options.retry_phase;
    error : Error.t;
  }

  type ended_event = {
    generation : int;
    attempt : int;
  }

  type error_event = {
    generation : int;
    attempt : int;
    error : Error.t;
  }

  type disposed_event = {
    generation : int;
  }

  type stats = {
    generation : int;
    attempt : int;
    bytes_received : int;
    reconnects : int;
  }

  module Cancellation = struct
    type t = cancellation

    let is_cancelled = Cancellation.is_cancelled
    let await = Cancellation.await
  end

  type 'metadata connection = {
    initial_metadata : 'metadata option;
    next : cancellation -> ('metadata input, Error.failure) result;
    close : unit -> (unit, Error.failure) result;
    mutable closed : bool;
  }

  type 'metadata connector = {
    connect :
      attempt:int ->
      cancel:cancellation ->
      ('metadata connection, Error.failure) result;
  }

  let connection ~initial_metadata ~next ~close =
    { initial_metadata; next; close; closed = false }

  let connector ~connect = { connect }

  type 'metadata pending_event =
    | Metadata_tick
    | Reconnecting_event of reconnecting_event
    | Ended_event of ended_event
    | Error_event of error_event
    | Disposed_event of disposed_event

  type 'metadata t = {
    engine : engine;
    owner : Owner.t;
    connector : 'metadata connector;
    options : Options.t;
    sleep : float -> unit;
    mutable state : state;
    mutable terminal : terminal option;
    mutable exposed : bool;
    mutable generation : int;
    mutable attempt : int;
    mutable metadata : 'metadata option;
    mutable metadata_seen : bool;
    mutable bytes_received : int;
    mutable reconnects : int;
    mutable close_requested : bool;
    shutdown : cancellation;
    mutable current_cancel : cancellation option;
    mutable current_connection : 'metadata connection option;
    mutable child_id : int option;
    exposure : (unit, Error.t) result Eio.Promise.t;
    exposure_resolver : (unit, Error.t) result Eio.Promise.u;
    closed : terminal Eio.Promise.t;
    closed_resolver : terminal Eio.Promise.u;
    mutable closed_resolved : bool;
    metadata_events : 'metadata metadata_event Event_kernel.t;
    reconnecting_events : reconnecting_event Event_kernel.t;
    ended_events : ended_event Event_kernel.t;
    error_events : error_event Event_kernel.t;
    disposed_events : disposed_event Event_kernel.t;
    mutable events : 'metadata pending_event Queue.t;
    mutable event_fiber_running : bool;
    mutable metadata_queued : bool;
    mutable pending_metadata : 'metadata metadata_event option;
    mutable event_callback_depth : int;
  }

  type attempt_outcome =
    | Attempt_ended
    | Attempt_failed of Error.failure
    | Attempt_cancelled
    | Attempt_cleanup_failed of Error.t

  let current stream generation cancel =
    not stream.close_requested
    && Option.is_none stream.terminal
    && Int.equal stream.generation generation
    && not (Cancellation.is_cancelled cancel)
    &&
    match stream.current_cancel with
    | Some current -> current == cancel
    | None -> false

  let with_event_callback stream callback =
    stream.event_callback_depth <- stream.event_callback_depth + 1;
    Fun.protect callback ~finally:(fun () ->
        stream.event_callback_depth <- stream.event_callback_depth - 1)

  let report stream diagnostic = stream.options.on_diagnostic diagnostic

  let report_from_event_callback stream exception_value =
    with_event_callback stream (fun () ->
        report stream (Observer_exception exception_value))

  let emit stream channel value =
    try ignore (with_event_callback stream (fun () -> Event_kernel.emit channel value)) with
    | exception_value ->
        report_from_event_callback stream exception_value

  let rec dispatch_events stream =
    Eio.Fiber.yield ();
    while not (Queue.is_empty stream.events) do
      let event = Queue.take stream.events in
      (match event with
      | Metadata_tick ->
          stream.metadata_queued <- false;
          (match stream.pending_metadata with
          | Some metadata_event ->
              stream.pending_metadata <- None;
              emit stream stream.metadata_events metadata_event
          | None -> ())
      | Reconnecting_event value -> emit stream stream.reconnecting_events value
      | Ended_event value -> emit stream stream.ended_events value
      | Error_event value ->
          let delivered = ref false in
          let snapshot = stream.error_events in
          (try
             delivered :=
               with_event_callback stream (fun () ->
                   Event_kernel.emit snapshot value);
           with
          | exception_value ->
              delivered := true;
              report_from_event_callback stream exception_value);
          if not !delivered then report stream (Unobserved_error value.error)
      | Disposed_event value -> emit stream stream.disposed_events value)
    done;
    stream.event_fiber_running <- false;
    if Option.is_some stream.terminal && not stream.closed_resolved then begin
      stream.closed_resolved <- true;
      match stream.terminal with
      | Some terminal -> ignore (Eio.Promise.try_resolve stream.closed_resolver terminal)
      | None -> ()
    end;
    if not (Queue.is_empty stream.events) && not stream.event_fiber_running then begin
      stream.event_fiber_running <- true;
      Eio.Fiber.fork ~sw:(Owner.switch stream.owner) (fun () ->
          dispatch_events stream)
    end

  let schedule_events stream =
    if not stream.event_fiber_running then begin
      stream.event_fiber_running <- true;
      Eio.Fiber.fork ~sw:(Owner.switch stream.owner) (fun () ->
          dispatch_events stream)
    end

  let enqueue stream event =
    Queue.add event stream.events;
    schedule_events stream

  let enqueue_metadata stream =
    stream.pending_metadata <-
      Some
        {
          generation = stream.generation;
          attempt = stream.attempt;
          value = stream.metadata;
        };
    if not stream.metadata_queued then begin
      stream.metadata_queued <- true;
      enqueue stream Metadata_tick
    end

  let enqueue_terminal_event stream =
    match stream.terminal with
    | Some Ended_terminal ->
        enqueue stream
          (Ended_event
             { generation = stream.generation; attempt = stream.attempt })
    | Some (Errored_terminal error) ->
        enqueue stream
          (Error_event
             {
               generation = stream.generation;
               attempt = stream.attempt;
               error;
             })
    | Some Disposed_terminal ->
        enqueue stream (Disposed_event { generation = stream.generation })
    | None -> ()

  let remove_from_engine stream =
    match stream.child_id with
    | None -> ()
    | Some id ->
        Engine.unregister stream.engine id;
        stream.child_id <- None

  let resolve_exposure stream result =
    ignore (Eio.Promise.try_resolve stream.exposure_resolver result)

  let request_disposal stream =
    if not stream.close_requested then begin
      stream.close_requested <- true;
      stream.generation <- stream.generation + 1
    end;
    cancel_cancellation stream.shutdown;
    Option.iter cancel_cancellation stream.current_cancel

  let cancelled_error stream =
    Error.with_context ~phase:Error.Cleanup ~generation:stream.generation
      ~attempt:stream.attempt ~retry:0 Error.Cancelled

  let await_closed_value stream =
    try Ok (Eio.Promise.await stream.closed) with
    | Eio.Cancel.Cancelled _ -> Error (cancelled_error stream)

  let fail_unexposed stream error =
    if Option.is_none stream.terminal then begin
      stream.state <- Errored;
      stream.terminal <- Some (Errored_terminal error);
      remove_from_engine stream;
      resolve_exposure stream (Error error);
      stream.closed_resolved <- true;
      ignore
        (Eio.Promise.try_resolve stream.closed_resolver (Errored_terminal error))
    end

  let finish_terminal stream terminal =
    if Option.is_none stream.terminal then begin
      stream.terminal <- Some terminal;
      stream.state <-
        (match terminal with
        | Ended_terminal -> Ended
        | Errored_terminal _ -> Errored
        | Disposed_terminal -> Disposed);
      remove_from_engine stream;
      if stream.exposed then enqueue_terminal_event stream
      else
        (match terminal with
        | Disposed_terminal | Errored_terminal _ ->
            resolve_exposure stream
              (Error
                 (Error.with_context ~phase:Error.Connect ~generation:stream.generation
                    ~attempt:stream.attempt ~retry:0 Error.Cancelled))
        | Ended_terminal -> resolve_exposure stream (Ok ()))
    end

  let finish_disposed stream =
    request_disposal stream;
    if stream.exposed then finish_terminal stream Disposed_terminal
    else
      fail_unexposed stream
        (Error.with_context ~phase:Error.Connect ~generation:stream.generation
           ~attempt:stream.attempt ~retry:0 Error.Cancelled)

  let close_connection stream ~generation ~attempt
      (connection : 'metadata connection) =
    if connection.closed then Ok ()
    else begin
      connection.closed <- true;
      (match stream.current_connection with
      | Some current when current == connection -> stream.current_connection <- None
      | Some _ | None -> ());
      (try connection.close () with
      | Eio.Cancel.Cancelled _ as exception_value -> raise exception_value
      | exception_value -> Error (Error.Exception exception_value))
      |> function
      | Ok () -> Ok ()
      | Error failure ->
          Error
            (Error.with_context ~phase:Error.Cleanup ~generation ~attempt ~retry:0
               (Error.Cleanup_failure failure))
    end

  let cleanup_current stream ~generation ~attempt =
    match stream.current_connection with
    | None -> Ok ()
    | Some connection -> close_connection stream ~generation ~attempt connection

  let expose stream =
    if not stream.exposed then begin
      stream.exposed <- true;
      resolve_exposure stream (Ok ());
      if stream.metadata_seen then enqueue_metadata stream;
      Eio.Fiber.yield ()
    end

  let set_metadata stream value =
    stream.metadata <- value;
    stream.metadata_seen <- true;
    if stream.exposed then enqueue_metadata stream

  let next_retry_error stream ~phase ~generation ~attempt ~retry failure =
    let reason =
      match phase with
      | Options.Connect -> Error.Connect_failure failure
      | Options.Read -> Error.Read_failure failure
      | Options.End -> Error.Read_failure failure
    in
    Error.with_context ~phase:Error.Retry ~generation ~attempt ~retry reason

  let delay_for options retry =
    let delay = ref options.Options.initial_delay in
    let index = ref 1 in
    while Int.compare !index retry < 0 do
      delay :=
        Float.min options.Options.max_delay
          (!delay *. options.Options.backoff);
      incr index
    done;
    Float.min options.Options.max_delay !delay

  let sleep_or_cancel stream delay =
    if Float.compare delay 0.0 <= 0 then begin
      Eio.Fiber.yield ();
      if Cancellation.is_cancelled stream.shutdown then `Cancelled else `Elapsed
    end
    else
      Eio.Fiber.first
        (fun () ->
          stream.sleep delay;
          `Elapsed)
        (fun () ->
          Cancellation.await stream.shutdown;
          `Cancelled)

  let retry_allowed stream ~phase ~error ~retry =
    if Int.compare retry stream.options.Options.max_retries > 0 then false
    else
      match phase with
      | Options.End -> stream.options.Options.retry_on_end
      | Options.Connect | Options.Read ->
          stream.options.Options.should_retry ~retry ~phase ~error

  type retry_outcome = Retry | Stop | Retry_failed of Error.t

  let exhausted_error ~phase:_ error =
    match error.Error.reason with
    | Error.Connect_failure failure ->
        { error with Error.reason = Error.Retry_exhausted failure }
    | Error.Read_failure failure ->
        { error with Error.reason = Error.Retry_exhausted failure }
    | Error.Retry_exhausted _ | Error.Retry_policy_failure _
    | Error.Cleanup_failure _ | Error.Closed
    | Error.Wrong_domain | Error.Switch_mismatch | Error.Owner_closed
    | Error.Invalid_options | Error.Cancelled | Error.Stale_generation -> error

  let schedule_retry stream ~phase ~failure ~generation ~attempt ~retry =
    let error = next_retry_error stream ~phase ~generation ~attempt ~retry failure in
    if stream.close_requested || Cancellation.is_cancelled stream.shutdown then
      Stop
    else
      let permitted =
        try Ok (retry_allowed stream ~phase ~error ~retry) with
        | Eio.Cancel.Cancelled _ as exception_value -> raise exception_value
        | exception_value ->
            Error
              (Error.with_context ~phase:Error.Retry ~generation ~attempt ~retry
                 (Error.Retry_policy_failure exception_value))
      in
      match permitted with
      | Error policy_error -> Retry_failed policy_error
      | Ok false -> Stop
      | Ok true ->
          stream.reconnects <- stream.reconnects + 1;
          if stream.exposed then begin
            stream.state <- Reconnecting;
            enqueue stream
              (Reconnecting_event
                 { generation; attempt; retry; phase; error })
          end;
          (match sleep_or_cancel stream (delay_for stream.options retry) with
          | `Cancelled -> Stop
          | `Elapsed -> Retry)

  let source_current stream generation cancel =
    current stream generation cancel

  let consume stream ~generation ~attempt ~cancel connection =
    let outcome = ref Attempt_cancelled in
    let running = ref true in
    while !running do
      if not (source_current stream generation cancel) then begin
        outcome := Attempt_cancelled;
        running := false
      end
      else
        let next_result =
          try connection.next cancel with
          | Eio.Cancel.Cancelled _ as exception_value -> raise exception_value
          | exception_value -> Error (Error.Exception exception_value)
        in
        match next_result with
        | Ok (Data bytes) ->
            if not (source_current stream generation cancel) then begin
              outcome := Attempt_cancelled;
              running := false
            end
            else begin
              stream.bytes_received <-
                stream.bytes_received + Bytes.length bytes;
              stream.state <- Playing;
              if Int.equal (Bytes.length bytes) 0 then Eio.Fiber.yield ()
            end
        | Ok (Metadata value) ->
            if not (source_current stream generation cancel) then begin
              outcome := Attempt_cancelled;
              running := false
            end
            else begin
              set_metadata stream value;
              Eio.Fiber.yield ()
            end
        | Ok End ->
            running := false;
            outcome :=
              (match close_connection stream ~generation ~attempt connection with
              | Ok () -> Attempt_ended
              | Error error -> Attempt_cleanup_failed error)
        | Error failure ->
            running := false;
            let cancelled =
              Cancellation.is_cancelled cancel || stream.close_requested
            in
            outcome :=
              (match close_connection stream ~generation ~attempt connection with
              | Error error -> Attempt_cleanup_failed error
              | Ok () when cancelled -> Attempt_cancelled
              | Ok () -> Attempt_failed failure)
    done;
    !outcome

  type 'metadata connection_outcome =
    | Connected of 'metadata connection
    | Connection_failed of Error.failure
    | Connection_cancelled
    | Connection_cleanup_failed of Error.t

  let connect stream ~attempt ~generation ~cancel =
    let result =
      try stream.connector.connect ~attempt ~cancel with
      | Eio.Cancel.Cancelled _ as exception_value -> raise exception_value
      | exception_value -> Error (Error.Exception exception_value)
    in
    match result with
    | Error failure -> Connection_failed failure
    | Ok connection when not (current stream generation cancel) ->
        (match close_connection stream ~generation ~attempt connection with
        | Ok () -> Connection_cancelled
        | Error error -> Connection_cleanup_failed error)
    | Ok connection -> Connected connection

  let finish_cleanup_failure stream error =
    report stream (Cleanup_error error);
    if stream.exposed then finish_terminal stream (Errored_terminal error)
    else fail_unexposed stream error

  let disposal_requested stream =
    stream.close_requested || Cancellation.is_cancelled stream.shutdown

  let finish_retry_failure stream error =
    if disposal_requested stream then finish_disposed stream
    else if stream.exposed then finish_terminal stream (Errored_terminal error)
    else fail_unexposed stream error

  let rec supervise stream ~attempt ~retry_ordinal =
    if stream.close_requested || Cancellation.is_cancelled stream.shutdown then
      finish_disposed stream
    else begin
      stream.generation <- stream.generation + 1;
      let generation = stream.generation in
      let cancel = create_cancellation () in
      stream.current_cancel <- Some cancel;
      stream.attempt <- attempt;
      match connect stream ~attempt ~generation ~cancel with
      | Connection_cancelled ->
          stream.current_cancel <- None;
          finish_disposed stream
      | Connection_cleanup_failed error ->
          stream.current_cancel <- None;
          finish_cleanup_failure stream error
      | Connection_failed _ when not (current stream generation cancel) ->
          stream.current_cancel <- None;
          finish_disposed stream
      | Connection_failed failure ->
          stream.current_cancel <- None;
          let error =
            Error.with_context ~phase:Error.Connect ~generation ~attempt
              ~retry:retry_ordinal (Error.Connect_failure failure)
          in
          let retry = retry_ordinal + 1 in
          (match
             schedule_retry stream ~phase:Options.Connect ~failure ~generation
               ~attempt ~retry
           with
          | Retry -> supervise stream ~attempt:(attempt + 1) ~retry_ordinal:retry
          | Retry_failed retry_error -> finish_retry_failure stream retry_error
          | Stop ->
              if disposal_requested stream then finish_disposed stream
              else if stream.exposed then
                finish_terminal stream
                  (Errored_terminal
                     (exhausted_error ~phase:Options.Connect error))
              else fail_unexposed stream (exhausted_error ~phase:Options.Connect error))
      | Connected connection ->
          stream.current_connection <- Some connection;
          stream.state <- Buffering;
          (match connection.initial_metadata with
          | Some value -> set_metadata stream (Some value)
          | None when stream.metadata_seen ->
              set_metadata stream None
          | None -> ());
          if not (current stream generation cancel) then begin
            stream.current_cancel <- None;
            (match close_connection stream ~generation ~attempt connection with
            | Ok () -> finish_disposed stream
            | Error error -> finish_cleanup_failure stream error)
          end
          else begin
            expose stream;
            let outcome = consume stream ~generation ~attempt ~cancel connection in
            stream.current_cancel <- None;
            (match outcome with
            | Attempt_cancelled ->
                (match cleanup_current stream ~generation ~attempt with
                | Ok () -> finish_disposed stream
                | Error error -> finish_cleanup_failure stream error)
            | Attempt_cleanup_failed error -> finish_cleanup_failure stream error
            | Attempt_ended ->
                let retry = retry_ordinal + 1 in
                (match
                   schedule_retry stream ~phase:Options.End
                     ~failure:Error.Invalid ~generation ~attempt ~retry
                 with
                | Retry -> supervise stream ~attempt:0 ~retry_ordinal:retry
                | Retry_failed retry_error ->
                    finish_retry_failure stream retry_error
                | Stop ->
                    if disposal_requested stream then finish_disposed stream
                    else finish_terminal stream Ended_terminal)
            | Attempt_failed failure ->
                let retry = retry_ordinal + 1 in
                let error =
                  Error.with_context ~phase:Error.Read ~generation ~attempt
                    ~retry:retry_ordinal (Error.Read_failure failure)
                in
                (match
                   schedule_retry stream ~phase:Options.Read ~failure
                     ~generation ~attempt ~retry
                 with
                | Retry -> supervise stream ~attempt:0 ~retry_ordinal:retry
                | Retry_failed retry_error ->
                    finish_retry_failure stream retry_error
                | Stop ->
                    if disposal_requested stream then finish_disposed stream
                    else
                      finish_terminal stream
                        (Errored_terminal
                           (exhausted_error ~phase:Options.Read error))))
          end
    end

  let switch_cancelled stream =
    request_disposal stream;
    (try
       match cleanup_current stream ~generation:stream.generation
           ~attempt:stream.attempt with
       | Ok () -> ()
       | Error error -> report stream (Cleanup_error error)
     with
    | Eio.Cancel.Cancelled _ -> report stream (Cleanup_error (cancelled_error stream)));
    stream.current_cancel <- None;
    if Option.is_none stream.terminal then begin
      stream.terminal <- Some Disposed_terminal;
      stream.state <- Disposed;
      remove_from_engine stream;
      if stream.exposed then ()
      else resolve_exposure stream (Error (cancelled_error stream))
    end;
    stream.closed_resolved <- true;
    match stream.terminal with
    | Some terminal -> ignore (Eio.Promise.try_resolve stream.closed_resolver terminal)
    | None -> ()

  let start_supervisor stream =
    Eio.Fiber.fork ~sw:(Owner.switch stream.owner) (fun () ->
        try supervise stream ~attempt:0 ~retry_ordinal:0 with
        | Eio.Cancel.Cancelled _ -> switch_cancelled stream)

  let check_stream stream =
    match Owner.check stream.owner with
    | Error error -> Error error
    | Ok () -> Ok ()

  let check_event_registration stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () when stream.closed_resolved -> Error (Error.admission Error.Closed)
    | Ok () -> Ok ()

  let on_metadata stream callback =
    match check_event_registration stream with
    | Error error -> Error error
    | Ok () -> Ok (Event_kernel.on stream.metadata_events callback)

  let on_reconnecting stream callback =
    match check_event_registration stream with
    | Error error -> Error error
    | Ok () -> Ok (Event_kernel.on stream.reconnecting_events callback)

  let on_ended stream callback =
    match check_event_registration stream with
    | Error error -> Error error
    | Ok () -> Ok (Event_kernel.on stream.ended_events callback)

  let on_error stream callback =
    match check_event_registration stream with
    | Error error -> Error error
    | Ok () -> Ok (Event_kernel.on stream.error_events callback)

  let on_disposed stream callback =
    match check_event_registration stream with
    | Error error -> Error error
    | Ok () -> Ok (Event_kernel.on stream.disposed_events callback)

  let close_from_engine stream =
    finish_disposed stream;
    if Int.compare stream.event_callback_depth 0 > 0 then Ok ()
    else
      match await_closed_value stream with
      | Ok _ -> Ok ()
      | Error error -> Error error

  let open_ ~(engine : engine) ~owner ~connector ~options =
    match Owner.check owner with
    | Error error -> Error error
    | Ok () when not (owner == engine.owner) ->
        Error (Error.admission Error.Switch_mismatch)
    | Ok () ->
        let exposure, exposure_resolver = Eio.Promise.create () in
        let closed, closed_resolver = Eio.Promise.create () in
        let stream =
          {
            engine;
            owner;
            connector;
            options;
            sleep = Owner.sleep owner;
            state = Initializing;
            terminal = None;
            exposed = false;
            generation = 0;
            attempt = 0;
            metadata = None;
            metadata_seen = false;
            bytes_received = 0;
            reconnects = 0;
            close_requested = false;
            shutdown = create_cancellation ();
            current_cancel = None;
            current_connection = None;
            child_id = None;
            exposure;
            exposure_resolver;
            closed;
            closed_resolver;
            closed_resolved = false;
            metadata_events = Event_kernel.create ();
            reconnecting_events = Event_kernel.create ();
            ended_events = Event_kernel.create ();
            error_events = Event_kernel.create ();
            disposed_events = Event_kernel.create ();
            events = Queue.create ();
            event_fiber_running = false;
            metadata_queued = false;
            pending_metadata = None;
            event_callback_depth = 0;
          }
        in
        (match
           Engine.register engine (fun () -> close_from_engine stream)
         with
        | Error error -> Error error
        | Ok child_id ->
            stream.child_id <- Some child_id;
            start_supervisor stream;
            (try
               match Eio.Promise.await stream.exposure with
               | Ok () -> Ok stream
               | Error error -> Error error
             with
            | Eio.Cancel.Cancelled _ ->
                request_disposal stream;
                let error =
                  Error.with_context ~phase:Error.Connect
                    ~generation:stream.generation ~attempt:stream.attempt ~retry:0
                    Error.Cancelled
                in
                Error error))

  let state stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () -> Ok stream.state

  let terminal stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () -> Ok stream.terminal

  let is_exposed stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () -> Ok stream.exposed

  let generation stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () -> Ok stream.generation

  let metadata stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () -> Ok stream.metadata

  let get_stats stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () ->
        Ok
          {
            generation = stream.generation;
            attempt = stream.attempt;
            bytes_received = stream.bytes_received;
            reconnects = stream.reconnects;
          }

  let terminal_result = function
    | Ended_terminal | Disposed_terminal -> Ok ()
    | Errored_terminal error -> Error error

  let close stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () ->
        (match stream.terminal with
        | Some _ when Int.compare stream.event_callback_depth 0 > 0 ->
            (match stream.terminal with
            | Some terminal -> terminal_result terminal
            | None -> Ok ())
        | None ->
            request_disposal stream;
            if Int.compare stream.event_callback_depth 0 > 0 then Ok ()
            else
              (match await_closed_value stream with
              | Error error -> Error error
              | Ok terminal -> terminal_result terminal)
        | Some _ ->
            (match await_closed_value stream with
            | Error error -> Error error
            | Ok terminal -> terminal_result terminal))

  let await_closed stream =
    match check_stream stream with
    | Error error -> Error error
    | Ok () -> await_closed_value stream
end
