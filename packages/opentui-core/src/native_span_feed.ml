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

type t = { raw : Opentui_raw.Span_feed.t; mutable closed : bool }

let map_error error =
  match error with
  | Opentui_raw.Error.Closed -> Error.Closed
  | Opentui_raw.Error.Invalid_argument -> Error.Invalid_argument
  | value -> Error.Native (Native.Error.Native value)

let map_result result =
  match result with Ok value -> Ok value | Error error -> Error (map_error error)

let default_options =
  {
    chunk_size = 65536l;
    initial_chunks = 2l;
    max_bytes = 0L;
    growth_policy = Grow;
    auto_commit_on_full = true;
    span_queue_capacity = 0l;
  }

let raw_policy = function Grow -> Opentui_raw.Span_feed.Grow | Block -> Block

let raw_options options =
  {
    Opentui_raw.Span_feed.chunk_size = options.chunk_size;
    initial_chunks = options.initial_chunks;
    max_bytes = options.max_bytes;
    growth_policy = raw_policy options.growth_policy;
    auto_commit_on_full = options.auto_commit_on_full;
    span_queue_capacity = options.span_queue_capacity;
  }

let create ?(options = default_options) () =
  match Opentui_raw.Span_feed.create ~options:(raw_options options) () with
  | Ok raw -> Ok { raw; closed = false }
  | Error error -> Error (map_error error)

let ensure_open feed = if feed.closed then Error Error.Closed else Ok ()

let write feed bytes =
  Result.bind (ensure_open feed) (fun () -> map_result (Opentui_raw.Span_feed.write feed.raw bytes))

let commit feed =
  Result.bind (ensure_open feed) (fun () -> map_result (Opentui_raw.Span_feed.commit feed.raw))

module Span = struct
  type t = Opentui_raw.Span_feed.Span.t
  let bytes = Opentui_raw.Span_feed.Span.bytes
  let release span = map_result (Opentui_raw.Span_feed.Span.release span)
end

module Reservation = struct
  type t = Opentui_raw.Span_feed.Reservation.t
  let capacity = Opentui_raw.Span_feed.Reservation.capacity
  let contents = Opentui_raw.Span_feed.Reservation.contents
  let commit reservation ~used =
    map_result (Opentui_raw.Span_feed.Reservation.commit reservation ~used)
  let cancel reservation = map_result (Opentui_raw.Span_feed.Reservation.cancel reservation)
end

let reserve feed ~min_length =
  Result.bind (ensure_open feed) (fun () ->
      match Opentui_raw.Span_feed.reserve feed.raw ~min_length with
      | Ok reservation -> Ok reservation
      | Error error -> Error (map_error error))

let stats feed =
  Result.bind (ensure_open feed) (fun () ->
      match Opentui_raw.Span_feed.stats feed.raw with
      | Error error -> Error (map_error error)
      | Ok stats ->
          Ok
            {
              bytes_written = stats.bytes_written;
              spans_committed = stats.spans_committed;
              chunks = stats.chunks;
              pending_spans = stats.pending_spans;
            })

let drain feed =
  Result.bind (ensure_open feed) (fun () ->
      match Opentui_raw.Span_feed.drain feed.raw with
      | Ok spans -> Ok spans
      | Error error -> Error (map_error error))

let close feed =
  if feed.closed then Ok ()
  else
    match Opentui_raw.Span_feed.close feed.raw with
    | Ok () ->
        feed.closed <- true;
        Ok ()
    | Error error -> Error (map_error error)

module Private = struct
  let raw feed =
    if feed.closed then Error Error.Closed else Ok feed.raw
end
