type ('a, 'e) t

val create :
  ?auto_process:bool ->
  schedule:((unit -> unit) -> unit) ->
  process:('a -> (unit, 'e) result) ->
  on_error:('e -> unit) ->
  unit ->
  ('a, 'e) t

val enqueue : ('a, 'e) t -> 'a -> unit
val run : ('a, 'e) t -> unit
val clear : ('a, 'e) t -> unit
val is_processing : ('a, 'e) t -> bool
val size : ('a, 'e) t -> int
