(** Eio source adapter for the pure terminal input coordinator.

    The flow reuses one caller-owned Cstruct/Bigarray read buffer. Parsed
    events are offered synchronously to a caller-owned sink. If the sink is
    full, unread input remains in that same reusable buffer and the next call
    retries it before reading the source again. *)

type event = Opentui_terminal.Input_coordinator.event
(** A decoded terminal event. *)

type delivery = Opentui_terminal.Input_coordinator.delivery
(** The result of offering one decoded event to the caller's sink. *)

type read_result = End_of_input | Bytes_read of int | Backpressured of int
(** The result of one source attempt. [Backpressured count] means that the sink
    still needs to accept earlier input; [count] is the number of bytes read
    during this call, and is [0] when no new source read was performed. *)

type error =
  | Invalid_buffer_size
  | Parser_error of Opentui_terminal.Input_coordinator.error
  | Flow_error
(** Input-buffer, parser, and Eio flow errors. *)

type t
(** A reusable Eio input adapter. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create :
  ?buffer_size:int ->
  ?initial_capacity:int ->
  ?max_pending_bytes:int ->
  ?timeout_ms:int ->
  unit ->
  (t, error) result
(** [create ...] allocates the reusable read storage and parser. The default
    read buffer is 4096 bytes. *)

val timeout_ms : t -> int
(** [timeout_ms input] is the parser timeout. *)

val deadline : t -> int64 option
(** [deadline input] is the parser deadline in monotonic milliseconds. *)

val read_once :
  t ->
  clock:_ Eio.Time.Mono.t ->
  source:([> Eio.Flow.source_ty] Eio.Resource.t) ->
  emit:(event -> delivery) ->
  (read_result, error) result
(** [read_once] retries any unread suffix first, then performs at most one
    source read and offers its bytes to [emit]. It never reads a new source
    chunk while earlier input is blocked. If the source read itself leaves the
    sink full, the result is [Backpressured count] and the adapter retains the
    unread suffix. The [emit] callback must not retain or mutate an event when
    it returns [Full]. *)

val fire_timeout :
  t ->
  clock:_ Eio.Time.Mono.t ->
  emit:(event -> delivery) ->
  (delivery, error) result
(** [fire_timeout input ~clock ~emit] feeds any already-read suffix before
    applying the coordinator timeout. [Full] leaves the event pending. The
    callback ownership rule is the same as for {!read_once}. *)

val reset : t -> unit
(** [reset input] discards parser, pending-input, and deadline state. *)
