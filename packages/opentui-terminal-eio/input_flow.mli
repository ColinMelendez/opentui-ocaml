type event = Opentui_terminal.Input_coordinator.event

type read_result = End_of_input | Bytes_read of int

type error =
  | Invalid_buffer_size
  | Parser_error of Opentui_terminal.Input_coordinator.error
  | Flow_error

type t

val message : error -> string
val pp : Format.formatter -> error -> unit

val create :
  ?buffer_size:int ->
  ?initial_capacity:int ->
  ?max_pending_bytes:int ->
  ?timeout_ms:int ->
  unit ->
  (t, error) result

val timeout_ms : t -> int
val deadline : t -> int64 option

val read_once :
  t ->
  clock:_ Eio.Time.Mono.t ->
  source:([> Eio.Flow.source_ty] Eio.Resource.t) ->
  (read_result, error) result

val read : t -> event option
val drain : t -> (event -> unit) -> unit
val transfer_one :
  t ->
  queue:Opentui_terminal.Event_queue.t ->
  (bool, Opentui_terminal.Event_queue.error) result
val fire_timeout : t -> clock:_ Eio.Time.Mono.t -> unit
val reset : t -> unit
