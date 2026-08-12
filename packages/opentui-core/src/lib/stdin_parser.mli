(** Incremental terminal framing above {!Byte_queue}.

    The parser preserves protocol units across input chunks, emits owned byte
    payloads, and uses a caller-driven timeout for incomplete escape prefixes.
    The pending protocol prefix is bounded by [max_pending_bytes]; callers
    should consume emitted events with {!read}, {!drain}, or their handoff. *)

type protocol = Csi | Ss3 | Osc | Dcs | Apc | Unknown
(** The protocol family of an opaque framed sequence. *)

type event =
  | Key of bytes
  | Sequence of { protocol : protocol; bytes : bytes }
  | Paste of bytes
(** A copied ground key, framed sequence, or bracketed-paste body. *)

type t
(** Mutable incremental parser state. *)

type error = Invalid_timeout | Queue_error of Byte_queue.error
(** Parser construction or backing-queue errors. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create :
  ?initial_capacity:int ->
  ?max_pending_bytes:int ->
  ?timeout_ms:int ->
  unit ->
  (t, error) result
(** [create ...] creates a parser with bounded pending-prefix storage. *)

val timeout_ms : t -> int
(** [timeout_ms parser] is the configured incomplete-escape timeout. *)

val pending_bytes : t -> int
(** [pending_bytes parser] is the unread incomplete-prefix length. *)

val buffer_capacity : t -> int
(** [buffer_capacity parser] is the current backing capacity. *)

val push :
  t -> source:Byte_queue.buffer -> off:int -> len:int -> (unit, error) result
(** [push] copies and parses an integer Bigarray range. A zero-length range
    emits one empty {!event} without changing pending protocol state. *)

val push_chars :
  t ->
  source:Byte_queue.char_buffer ->
  off:int ->
  len:int ->
  (unit, error) result
(** [push_chars] is the character Bigarray variant of {!push}. A zero-length
    range has the same behavior as {!push}. *)

val push_bytes : t -> source:bytes -> off:int -> len:int -> (unit, error) result
(** [push_bytes] is the [bytes] variant of {!push}. A zero-length range has the
    same behavior as {!push}. *)

val read : t -> event option
(** [read parser] removes the oldest emitted event, if any. *)

val drain : t -> (event -> unit) -> unit
(** [drain parser callback] invokes [callback] for every emitted event in
    order. *)

val flush_timeout : t -> unit
(** [flush_timeout parser] force-flushes an incomplete non-paste prefix as an
    opaque event. It does not inspect time; callers invoke it after the
    configured timeout, typically through {!Input_coordinator.fire_timeout}. *)

val reset : t -> unit
(** [reset parser] discards pending bytes, emitted events, and protocol state. *)
