(** Parser/decoder coordination above {!Stdin_parser}.

    Input bytes are copied into the parser's bounded pending storage. Decoded
    events are offered synchronously to a caller-owned sink; when that sink is
    full, the coordinator retains the blocked event and reports the exact
    source prefix it accepted. *)

type event = Input_decoder.event
(** A decoded terminal event. *)

type delivery = Accepted | Full
(** The result of offering one decoded event to a caller-owned sink.
    [Accepted] means that the sink now owns the event. [Full] leaves the event
    owned by the coordinator for a later {!drain} or {!push}. An [emit]
    callback must not retain or mutate the event when it returns [Full]. *)

type push_result = Accepted_all | Full_after of int
(** [Accepted_all] means that the complete source range was consumed.
    [Full_after count] means that [count] source bytes were consumed before
    the sink reported {!Full}; the remaining suffix must be submitted again. *)

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
    storage and the parser's timeout policy. The default timeout is 20
    milliseconds. *)

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
  emit:(event -> delivery) ->
  source:Byte_queue.buffer ->
  off:int ->
  len:int ->
  (push_result, error) result
(** [push coordinator ~now_ms ~emit ...] copies and parses an integer
    Bigarray source range, offering each decoded event to [emit]. It returns
    [Full_after 0] without consuming new source bytes if an earlier event is
    still blocked. *)

val push_chars :
  t ->
  now_ms:int64 ->
  emit:(event -> delivery) ->
  source:Byte_queue.char_buffer ->
  off:int ->
  len:int ->
  (push_result, error) result
(** [push_chars] is the character Bigarray variant of {!push}. *)

val push_bytes :
  t ->
  now_ms:int64 ->
  emit:(event -> delivery) ->
  source:bytes ->
  off:int ->
  len:int ->
  (push_result, error) result
(** [push_bytes] is the [bytes] variant of {!push}. *)

val drain : t -> emit:(event -> delivery) -> delivery
(** [drain coordinator ~emit] offers all already-framed events to [emit] in
    order, stopping without loss when [emit] reports {!Full}. *)

val fire_timeout :
  t ->
  now_ms:int64 ->
  emit:(event -> delivery) ->
  delivery
(** [fire_timeout coordinator ~now_ms ~emit] flushes an expired incomplete
    prefix and offers the resulting events to [emit]. *)

val reset : t -> unit
(** [reset coordinator] discards pending bytes, framed events, and deadline
    state. *)
