(** Parser/decoder coordination above {!Stdin_parser}.

    Input bytes are copied into the parser's bounded pending storage; decoded
    events remain owned by the coordinator until [read], [drain], or
    [transfer_one] consumes them. The destination handoff in [transfer_one]
    is bounded by {!Event_queue}. *)

type event = Input_decoder.event
(** A decoded terminal event. *)

type error = Parser_error of Stdin_parser.error
(** Errors returned while accepting input bytes. *)

type t
(** A mutable parser, decoder, and deadline coordinator. *)

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
(** [create ...] creates a coordinator with bounded incomplete-protocol
    storage and the parser's timeout policy. *)

val timeout_ms : t -> int
(** [timeout_ms coordinator] is the configured escape-sequence timeout. *)

val pending_bytes : t -> int
(** [pending_bytes coordinator] is the currently buffered incomplete prefix. *)

val deadline : t -> int64 option
(** [deadline coordinator] is the absolute millisecond deadline for the
    incomplete prefix, if one exists. *)

val push :
  t ->
  now_ms:int64 ->
  source:Byte_queue.buffer ->
  off:int ->
  len:int ->
  (unit, error) result
(** [push coordinator ~now_ms ...] copies and parses an integer Bigarray
    source range. *)

val push_chars :
  t ->
  now_ms:int64 ->
  source:Byte_queue.char_buffer ->
  off:int ->
  len:int ->
  (unit, error) result
(** [push_chars] is the character Bigarray variant of {!push}. *)

val push_bytes :
  t ->
  now_ms:int64 ->
  source:bytes ->
  off:int ->
  len:int ->
  (unit, error) result
(** [push_bytes] is the [bytes] variant of {!push}. *)

val read : t -> event option
(** [read coordinator] removes the oldest decoded event, if any. *)

val drain : t -> (event -> unit) -> unit
(** [drain coordinator callback] invokes [callback] for every queued decoded
    event in order. *)

val transfer_one :
  t ->
  queue:Event_queue.t ->
  (bool, Event_queue.error) result
(** [transfer_one coordinator ~queue] moves one decoded event into the bounded
    destination queue. On [Full], the event remains in the coordinator. *)

val fire_timeout : t -> now_ms:int64 -> unit
(** [fire_timeout coordinator ~now_ms] flushes an expired incomplete prefix. *)

val reset : t -> unit
(** [reset coordinator] discards pending bytes, decoded events, and deadline
    state. *)
