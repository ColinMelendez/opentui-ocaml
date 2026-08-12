(** Bounded reusable byte storage for terminal protocol framing.

    The queue owns its backing Bigarray and copies data appended from caller
    buffers. Logical cursors are independent of the backing array position. *)

type buffer =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type char_buffer =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type t
(** A bounded mutable byte queue. *)

type error = Invalid_capacity | Invalid_range | Max_capacity
(** Errors from queue construction or bounded append operations. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create :
  ?initial_capacity:int -> ?max_capacity:int -> unit -> (t, error) result

val length : t -> int
(** [length queue] is the number of unread bytes. *)

val capacity : t -> int
(** [capacity queue] is the current backing capacity. *)

val max_capacity : t -> int
(** [max_capacity queue] is the append limit. *)

val append : t -> source:buffer -> off:int -> len:int -> (unit, error) result
(** [append queue ~source ~off ~len] copies a bounded range from [source]. *)

val append_chars :
  t -> source:char_buffer -> off:int -> len:int -> (unit, error) result
(** [append_chars] is the character Bigarray variant of {!append}. *)

val append_bytes : t -> source:bytes -> off:int -> len:int -> (unit, error) result
(** [append_bytes] is the [bytes] variant of {!append}. *)

val get : t -> int -> int option
(** [get queue index] returns the unread byte at zero-based [index], if any. *)

val consume : t -> int -> (unit, error) result
(** [consume queue count] removes [count] unread bytes. *)

val clear : t -> unit
(** [clear queue] removes all unread bytes without changing its capacity. *)
