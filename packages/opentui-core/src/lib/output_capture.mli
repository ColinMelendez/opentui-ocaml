type stream = Stdout | Stderr

type chunk = { stream : stream; output : string }

type error =
  | Closed
  | Limit_exceeded
  | Flow_failed of string
  | Restore_failed of string

type t

val create :
  ?max_bytes:int ->
  ?restore:(unit -> (unit, string) result) ->
  unit -> t
val write : t -> stream:stream -> string -> (unit, error) result
val size : t -> int
val bytes : t -> int
val claim_output : t -> string
val chunks : t -> chunk list
val restore : t -> (unit, error) result
val drain_to :
  t ->
  write:(stream -> bytes -> off:int -> len:int -> (int, string) result) ->
  (unit, error) result
val close : t -> unit
val message : error -> string
