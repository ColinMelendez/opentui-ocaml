(** Owner-domain lifecycle for encoded audio streams.

    This module deliberately stops above decoding and playback.  It owns the
    Eio scope, encoded-source attempts, cancellation, retries, metadata, and
    terminal events.  A later native adapter can consume {!Stream.Data} from a
    source without changing the ownership rules here. *)

module Error : sig
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

  val message : t -> string
  val pp : Format.formatter -> t -> unit
end

type diagnostic =
  | Observer_exception of exn
  | Unobserved_error of Error.t
  | Cleanup_error of Error.t

module Owner : sig
  type t

  (** [create ~sw ~clock] creates the explicit audio owner capability.  The
      capability is bound to the calling domain, switch, and monotonic clock;
      it does not acquire renderer ownership. *)
  val create :
    sw:Eio.Switch.t -> clock:_ Eio.Time.Mono.t -> (t, Error.t) result

  (** [is_current owner] is a non-mutating affinity/lifetime predicate. *)
  val is_current : t -> bool
end

module Engine : sig
  type t

  type state = Open | Closing | Closed

  (** The engine is an owner-domain registry and lifecycle boundary.  It does
      not decode, mix, or play bytes. *)
  val create : owner:Owner.t -> (t, Error.t) result
  val owner : t -> Owner.t
  val state : t -> (state, Error.t) result
  val close : t -> (unit, Error.t) result
end

module Options : sig
  type retry_phase = Connect | Read | End

  type t

  (** Retry defaults are intentionally conservative: no automatic retry and
      no retry on clean source end. *)
  val default : t

  val create :
    ?max_retries:int ->
    ?initial_delay:float ->
    ?max_delay:float ->
    ?backoff:float ->
    ?retry_on_end:bool ->
    ?should_retry:(retry:int -> phase:retry_phase -> error:Error.t -> bool) ->
    ?on_diagnostic:(diagnostic -> unit) ->
    unit -> (t, Error.t) result
end

module Stream : sig
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

  (** [Data] is still encoded source data.  The first slice records its byte
      count but never claims to decode or play it. *)
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

  module Cancellation : sig
    type t

    (** A connector or source should poll [is_cancelled] around any operation
        that can complete after ownership has changed. *)
    val is_cancelled : t -> bool

    (** [await cancel] is a cancellation-aware wait primitive for in-memory or
        Eio-backed connectors. *)
    val await : t -> unit
  end

  type 'metadata connection
  type 'metadata connector

  val connection :
    initial_metadata:'metadata option ->
    next:(Cancellation.t -> ('metadata input, Error.failure) result) ->
    close:(unit -> (unit, Error.failure) result) ->
    'metadata connection

  val connector :
    connect:(
      attempt:int ->
      cancel:Cancellation.t ->
      ('metadata connection, Error.failure) result) ->
    'metadata connector

  type 'metadata t

  (** [open_] admits a stream only after a connection has been established.
      A connection failure is returned directly when setup retries are
      exhausted; a clean source end after admission returns an already-ended
      stream.  [owner] is an explicit capability and must be the exact owner
      used to create [engine]. *)
  val open_ :
    engine:Engine.t ->
    owner:Owner.t ->
    connector:'metadata connector ->
    options:Options.t ->
    ('metadata t, Error.t) result

  val state : 'metadata t -> (state, Error.t) result
  val terminal : 'metadata t -> (terminal option, Error.t) result
  val is_exposed : 'metadata t -> (bool, Error.t) result
  val generation : 'metadata t -> (int, Error.t) result
  val metadata : 'metadata t -> ('metadata option, Error.t) result
  val get_stats : 'metadata t -> (stats, Error.t) result

  (** Event registration is owner-local.  A registration made immediately
      after [open_] observes setup metadata and setup-time terminal events
      because delivery is queued behind the caller's first continuation. *)
  val on_metadata :
    'metadata t ->
    ('metadata metadata_event -> unit) ->
    (Event_subscription.t, Error.t) result

  val on_reconnecting :
    'metadata t ->
    (reconnecting_event -> unit) ->
    (Event_subscription.t, Error.t) result

  val on_ended :
    'metadata t ->
    (ended_event -> unit) ->
    (Event_subscription.t, Error.t) result

  val on_error :
    'metadata t ->
    (error_event -> unit) ->
    (Event_subscription.t, Error.t) result

  val on_disposed :
    'metadata t ->
    (disposed_event -> unit) ->
    (Event_subscription.t, Error.t) result

  (** [close] is idempotent.  It invalidates the current generation before
      asking the connector to stop, so a late source result cannot publish an
      event or alter statistics. *)
  val close : 'metadata t -> (unit, Error.t) result

  (** [await_closed] waits until terminal cleanup and the terminal event's
      delivery attempt have completed. *)
  val await_closed : 'metadata t -> (terminal, Error.t) result
end
