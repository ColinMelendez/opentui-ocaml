(** Validated positive terminal dimensions. *)
type t

type error = Invalid_dimensions
(** Errors from invalid column or row counts. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create : columns:int -> rows:int -> (t, error) result
(** [create ~columns ~rows] validates and stores terminal dimensions. *)

val columns : t -> int
(** [columns size] is the number of terminal columns. *)

val rows : t -> int
(** [rows size] is the number of terminal rows. *)

val equal : t -> t -> bool
(** [equal left right] compares dimensions explicitly. *)
