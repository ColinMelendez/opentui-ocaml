type buffer =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type char_buffer =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type t

type error = Invalid_capacity | Invalid_range | Max_capacity

val message : error -> string
val pp : Format.formatter -> error -> unit

val create :
  ?initial_capacity:int -> ?max_capacity:int -> unit -> (t, error) result

val length : t -> int
val capacity : t -> int
val max_capacity : t -> int

val append : t -> source:buffer -> off:int -> len:int -> (unit, error) result

val append_chars :
  t -> source:char_buffer -> off:int -> len:int -> (unit, error) result

val append_bytes : t -> source:bytes -> off:int -> len:int -> (unit, error) result

val get : t -> int -> int option
val consume : t -> int -> (unit, error) result
val clear : t -> unit
