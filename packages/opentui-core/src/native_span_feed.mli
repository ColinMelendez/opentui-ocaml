(** Core-facing ownership wrapper for the raw native span feed. *)

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

type t

module Span : sig
  type t
  val bytes : t -> bytes
  val release : t -> (unit, Error.t) result
end

module Reservation : sig
  type t
  val capacity : t -> int32
  val contents : t -> bytes
  val commit : t -> used:int32 -> (unit, Error.t) result
  val cancel : t -> (unit, Error.t) result
end

val default_options : options
val create : ?options:options -> unit -> (t, Error.t) result
val write : t -> bytes -> (unit, Error.t) result
val commit : t -> (unit, Error.t) result
val reserve : t -> min_length:int32 -> (Reservation.t, Error.t) result
val stats : t -> (stats, Error.t) result
val drain : t -> (Span.t list, Error.t) result
val close : t -> (unit, Error.t) result
