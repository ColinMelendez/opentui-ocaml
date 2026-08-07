type growth_policy = Grow | Block

type options = {
  chunk_size : int32;
  initial_chunks : int32;
  max_bytes : int64;
  growth_policy : growth_policy;
  auto_commit_on_full : bool;
  span_queue_capacity : int32;
}

type stats = {
  bytes_written : int64;
  spans_committed : int64;
  chunks : int32;
  pending_spans : int32;
}

type t = {
  token : Native_token.Span_feed.t;
  owner : Native_owner.t;
}

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let result_of_status status value =
  match status with
  | 0 -> Ok value
  | _ -> Error (error_of_status status)

let growth_policy_code policy =
  match policy with
  | Grow -> 0
  | Block -> 1

let native_options options =
  ( options.chunk_size,
    options.initial_chunks,
    options.max_bytes,
    growth_policy_code options.growth_policy,
    options.auto_commit_on_full,
    options.span_queue_capacity )

let default_options =
  {
    chunk_size = 65536l;
    initial_chunks = 2l;
    max_bytes = 0L;
    growth_policy = Grow;
    auto_commit_on_full = true;
    span_queue_capacity = 0l;
  }

let create ?(options = default_options) () =
  let status, token = Native.span_feed_create (native_options options) in
  match status with
  | 0 -> Ok { token; owner = Native_owner.Private.create () }
  | _ -> Error (error_of_status status)

let with_open feed operation =
  if Native_owner.is_open feed.owner then operation feed.token
  else Error Error.Closed

let write feed data =
  with_open feed (fun token -> result_of_status (Native.span_feed_write token data) ())

let commit feed =
  with_open feed (fun token -> result_of_status (Native.span_feed_commit token) ())

module Span = struct
  type t = {
    token : Native_token.Span.t;
    owner : Native_owner.t;
    bytes : bytes;
    mutable released : bool;
  }

  let bytes span = span.bytes

  let release span =
    if span.released then Ok ()
    else if not (Native_owner.is_open span.owner) then Error Error.Closed
    else
      match Native.span_release span.token with
      | 0 ->
          span.released <- true;
          Ok ()
      | status -> Error (error_of_status status)
end

module Reservation = struct
  type state = Active | Committed | Cancelled

  type t = {
    token : Native_token.Reservation.t;
    owner : Native_owner.t;
    capacity : int32;
    contents : bytes;
    mutable state : state;
  }

  let capacity reservation = reservation.capacity
  let contents reservation = reservation.contents

  let active reservation operation =
    if not (Native_owner.is_open reservation.owner) then Error Error.Closed
    else
      match reservation.state with
      | Active -> operation ()
      | Committed | Cancelled -> Error Error.Invalid_argument

  let commit reservation ~used =
    if Int32.compare used 0l < 0
       || Int32.compare used reservation.capacity > 0
    then Error Error.Invalid_argument
    else
      active reservation (fun () ->
          match
            Native.span_feed_reservation_commit
              reservation.token reservation.contents used
          with
          | 0 ->
              reservation.state <- Committed;
              Ok ()
          | status -> Error (error_of_status status))

  let cancel reservation =
    active reservation (fun () ->
        match Native.span_feed_reservation_cancel reservation.token with
        | 0 ->
            reservation.state <- Cancelled;
            Ok ()
        | status -> Error (error_of_status status))
end

let reserve feed ~min_length =
  if Int32.compare min_length 0l < 0 then Error Error.Invalid_argument
  else
    with_open feed (fun token ->
        let status, reservation = Native.span_feed_reserve token min_length in
        match status, reservation with
        | 0, Some (reservation_token, reservation_capacity, staging_bytes) ->
            (try
               Ok
                 (Reservation.{
                    token = reservation_token;
                    owner = feed.owner;
                    capacity = reservation_capacity;
                    contents = staging_bytes;
                    state = Active;
                  })
             with
             | Out_of_memory ->
                 ignore
                   (Native.span_feed_reservation_cancel reservation_token);
                 raise Out_of_memory)
        | 0, None -> Error Error.Native_failure
        | _, _ -> Error (error_of_status status))

let stats feed =
  with_open feed (fun token ->
      let status, native_stats = Native.span_feed_stats token in
      match status, native_stats with
      | 0, Some (bytes_written, spans_committed, chunks, pending_spans) ->
          Ok { bytes_written; spans_committed; chunks; pending_spans }
      | 0, None -> Error Error.Native_failure
      | _, _ -> Error (error_of_status status))

let drain feed =
  with_open feed (fun token ->
      let spans = ref [] in
      let status = ref 0 in
      let finished = ref false in
      let release_spans () =
        List.iter (fun span -> ignore (Span.release span)) !spans
      in
      let add_span payload span_token =
        try
          let span =
            Span.{
              token = span_token;
              owner = feed.owner;
              bytes = payload;
              released = false;
            }
          in
          spans := span :: !spans
        with
        | Out_of_memory ->
            ignore (Native.span_release span_token);
            raise Out_of_memory
      in
      try
        while not !finished do
          let current_status, native_span = Native.span_feed_drain token in
          status := current_status;
          match current_status, native_span with
          | 0, None -> finished := true
          | 0, Some (payload, span_token) -> add_span payload span_token
          | _, _ -> finished := true
        done;
        match !status with
        | 0 -> Ok (List.rev !spans)
        | status ->
            release_spans ();
            Error (error_of_status status)
      with
      | Out_of_memory ->
          release_spans ();
          raise Out_of_memory)

let close feed =
  if not (Native_owner.is_open feed.owner) then Ok ()
  else
    match Native.span_feed_close feed.token with
    | 0 ->
        Native_owner.Private.close feed.owner;
        Ok ()
    | status -> Error (error_of_status status)
