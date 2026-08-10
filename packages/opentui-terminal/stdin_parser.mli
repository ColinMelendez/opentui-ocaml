type protocol = Csi | Ss3 | Osc | Dcs | Apc | Unknown

type event =
  | Key of bytes
  | Sequence of { protocol : protocol; bytes : bytes }
  | Paste of bytes

type t

type error = Invalid_timeout | Queue_error of Byte_queue.error

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
val buffer_capacity : t -> int

val push :
  t -> source:Byte_queue.buffer -> off:int -> len:int -> (unit, error) result

val push_chars :
  t ->
  source:Byte_queue.char_buffer ->
  off:int ->
  len:int ->
  (unit, error) result

val push_bytes : t -> source:bytes -> off:int -> len:int -> (unit, error) result

val read : t -> event option
val drain : t -> (event -> unit) -> unit
val flush_timeout : t -> unit
val reset : t -> unit
