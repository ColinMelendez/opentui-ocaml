(** Deterministic proportional column allocation used by {!Renderables.Text_table}. *)

val allocate_proportional_column_widths :
  widths:int list -> target_width:int -> min_width:int -> int list
