(** Text-position markers that move with edit-buffer changes. *)

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

type options = {
  start : int;
  end_ : int;
  virtual_ : bool;
  style_id : int option;
  priority : int option;
  data : string option;
  type_id : int option;
  metadata : string option;
}

type t

val create : unit -> t
val create_mark : t -> options -> (int, Error.t) result
val delete : t -> int -> (bool, Error.t) result
val get : t -> int -> (extmark option, Error.t) result
val all : t -> (extmark list, Error.t) result
val virtual_marks : t -> (extmark list, Error.t) result
val at_offset : t -> int -> (extmark list, Error.t) result
val all_for_type_id : t -> int -> (extmark list, Error.t) result
val clear : t -> (unit, Error.t) result

val adjust_after_insertion : t -> offset:int -> length:int -> (unit, Error.t) result
val adjust_after_deletion : t -> offset:int -> length:int -> (unit, Error.t) result

val register_type : t -> string -> (int, Error.t) result
val type_id : t -> string -> (int option, Error.t) result
val type_name : t -> int -> (string option, Error.t) result
val metadata : t -> int -> (string option, Error.t) result

val save_snapshot : t -> (unit, Error.t) result
val undo : t -> (bool, Error.t) result
val redo : t -> (bool, Error.t) result
val can_undo : t -> (bool, Error.t) result
val can_redo : t -> (bool, Error.t) result
val destroy : t -> unit
