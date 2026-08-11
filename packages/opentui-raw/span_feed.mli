(** Copy-first ownership bindings for the native span feed.

    Drained spans are copied into OCaml [bytes] and must be released. Reserve
    operations expose caller-owned staging bytes with explicit commit or
    cancel. The feed is explicitly closed and is not finalized implicitly. *)

type growth_policy = Grow | Block
(** Whether native storage grows or reports no space. *)

type options = {
  chunk_size : int32;
  initial_chunks : int32;
  max_bytes : int64;
  growth_policy : growth_policy;
  auto_commit_on_full : bool;
  span_queue_capacity : int32;
}
(** Native feed configuration. Zero values use the pinned backend defaults. *)

type stats = {
  bytes_written : int64;
  spans_committed : int64;
  chunks : int32;
  pending_spans : int32;
}
(** Copied feed counters. *)

type t
(** An explicitly owned native span feed. *)

module Span : sig
  (** A copied payload whose native chunk remains retained until release. *)
  type t

  (** [bytes span] returns the mutable owned payload copy. *)
  val bytes : t -> bytes

  (** [release span] marks the native span consumed. Releasing twice is safe. *)
  val release : t -> (unit, Error.t) result
end

module Reservation : sig
  (** A one-shot caller-owned staging reservation. *)
  type t

  (** [capacity reservation] is the reserved native capacity. *)
  val capacity : t -> int32

  (** [contents reservation] is the mutable staging buffer to fill before
      {!commit}. *)
  val contents : t -> bytes

  (** [commit reservation ~used] publishes the first [used] bytes. *)
  val commit : t -> used:int32 -> (unit, Error.t) result

  (** [cancel reservation] abandons the reservation without publishing it. *)
  val cancel : t -> (unit, Error.t) result
end

(** [create ?options ()] allocates a feed. *)
val create : ?options:options -> unit -> (t, Error.t) result

(** [write feed data] copies [data] into the native feed. *)
val write : t -> bytes -> (unit, Error.t) result

(** [commit feed] publishes the current pending native span. *)
val commit : t -> (unit, Error.t) result

(** [reserve feed ~min_length] allocates a caller-owned staging reservation. *)
val reserve : t -> min_length:int32 -> (Reservation.t, Error.t) result

(** [stats feed] returns copied feed counters. *)
val stats : t -> (stats, Error.t) result

(** [drain feed] returns all currently available copied spans. *)
val drain : t -> (Span.t list, Error.t) result

(** [close feed] releases the feed and invalidates outstanding spans and
    reservations. It is idempotent after successful close. *)
val close : t -> (unit, Error.t) result
