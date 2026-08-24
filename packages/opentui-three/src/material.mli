type kind =
  | Basic
  | Lambert

type t = {
  kind : kind;
  color : Color.t;
}
(** Material state shared by the supported material families. [color] is the
    linear-space albedo; mutate it directly for per-frame effects. The kind
    selects which render pipeline draws the mesh and is fixed at creation,
    matching three.js where swapping families means swapping materials. *)

val color : t -> Color.t

val kind : t -> kind
