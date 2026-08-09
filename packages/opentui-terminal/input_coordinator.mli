type event = Input_decoder.event

type error = Parser_error of Stdin_parser.error

type t

val message : error -> string
val pp : Format.formatter -> error -> unit

val create :
  ?initial_capacity:int ->
  ?max_pending_bytes:int ->
  ?timeout_ms:int ->
  unit ->
  (t, error) result

val timeout_ms : t -> int
val pending_bytes : t -> int
val deadline : t -> int64 option

val push :
  t ->
  now_ms:int64 ->
  source:Byte_queue.buffer ->
  off:int ->
  len:int ->
  (unit, error) result

val push_bytes :
  t ->
  now_ms:int64 ->
  source:bytes ->
  off:int ->
  len:int ->
  (unit, error) result

val read : t -> event option
val drain : t -> (event -> unit) -> unit
val fire_timeout : t -> now_ms:int64 -> unit
val reset : t -> unit
