(** A process-local polling sink for copied native event callbacks.

    The pinned callback ABI has no context pointer, so at most one sink may be
    active. The sink copies callback payloads into a bounded native queue and
    does not call OCaml from the callback. *)
type t

(** [create ()] installs the sole active event sink. *)
val create : unit -> (t, Error.t) result

(** [close sink] destroys the sink and discards queued events. It is
    idempotent. *)
val close : t -> unit

(** [poll sink] removes and returns the oldest copied event, or [None] when
    the queue is empty. *)
val poll : t -> (Event.t option, Error.t) result
