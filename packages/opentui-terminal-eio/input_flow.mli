(** Eio source adapter for the pure terminal input coordinator.

    The flow reuses one caller-owned Cstruct/Bigarray read buffer. Parsed
    events are owned by the coordinator; this module does not close the input
    source or create fibers. *)

type event = Opentui_terminal.Input_coordinator.event
(** A decoded terminal event. *)

type read_result = End_of_input | Bytes_read of int
(** The result of one source read. *)

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
(** [create ...] allocates the reusable read storage and parser. *)

val timeout_ms : t -> int
(** [timeout_ms input] is the parser timeout. *)

val deadline : t -> int64 option
(** [deadline input] is the parser deadline in monotonic milliseconds. *)

val read_once :
  t ->
  clock:_ Eio.Time.Mono.t ->
  source:([> Eio.Flow.source_ty] Eio.Resource.t) ->
  (read_result, error) result
(** [read_once] performs one source read and feeds the bytes to the parser.
    Cancellation propagates; end-of-file is returned as [End_of_input]. *)

val read : t -> event option
(** [read input] removes one decoded event, if any. *)

val drain : t -> (event -> unit) -> unit
(** [drain input callback] invokes [callback] for queued decoded events. *)

val transfer_one :
  t ->
  queue:Opentui_terminal.Event_queue.t ->
  (bool, Opentui_terminal.Event_queue.error) result
(** [transfer_one] moves one event to the bounded runtime queue. *)

val transfer_one_and_notify :
  t ->
  queue:Opentui_terminal.Event_queue.t ->
  wakeup:Wakeup.t ->
  (bool, Opentui_terminal.Event_queue.error) result
(** [transfer_one_and_notify] performs {!transfer_one} and notifies [wakeup]
    only after acceptance or coalescing. *)

val fire_timeout : t -> clock:_ Eio.Time.Mono.t -> unit
(** [fire_timeout input ~clock] flushes an expired parser prefix. *)

val reset : t -> unit
(** [reset input] discards parser and decoded-event state. *)
