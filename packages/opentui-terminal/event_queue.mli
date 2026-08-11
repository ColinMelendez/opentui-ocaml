(** Bounded terminal event handoff with coalescing for resize and pointer
    motion events. Key, paste, opaque sequence, button, and scroll events are
    lossless until the queue reports {!Full}. *)

type event =
  | Input of Input_decoder.event
  | Resize of Terminal_size.t

type t
(** A bounded FIFO event queue. *)

type error =
  | Invalid_capacity
  | Full
(** Queue construction and capacity errors. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create : ?capacity:int -> unit -> (t, error) result
(** [create ?capacity ()] creates an empty bounded queue. *)

val capacity : t -> int
(** [capacity queue] is the fixed queue capacity. *)

val length : t -> int
(** [length queue] is the number of queued events. *)

val push : t -> event -> (unit, error) result
(** [push queue event] appends [event]. Pending resize and mouse motion events
    replace the existing event of the same coalescing class in place. *)

val read : t -> event option
(** [read queue] removes and returns the oldest event, if any. *)

val clear : t -> unit
(** [clear queue] removes all queued events. *)
