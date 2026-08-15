(** Undo/redo snapshots for extmark state. *)

type extmark = {
  id : int;
  start : int;
  end_ : int;
  virtual_ : bool;
  style_id : int option;
  priority : int option;
  data : string option;
  type_id : int;
}

type snapshot = { extmarks : extmark list; next_id : int }
type t

val create : unit -> t
val save_snapshot : t -> extmark list -> next_id:int -> unit
val undo : t -> snapshot option
val redo : t -> snapshot option
val push_undo : t -> snapshot -> unit
val push_redo : t -> snapshot -> unit
val clear : t -> unit
val can_undo : t -> bool
val can_redo : t -> bool
