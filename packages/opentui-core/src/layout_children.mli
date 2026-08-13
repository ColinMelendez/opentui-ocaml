(** Layout-child mutation for concrete retained containers. *)

type t
(** A capability for one retained object's physical Yoga children. *)

val add : ?index:int -> t -> Renderable.t -> (int, Error.t) result
(** [add capability child] appends [child]. An in-range [index] inserts before
    the child occupying that layout slot; an out-of-range index appends. *)

val insert_before :
  t -> Renderable.t -> anchor:Renderable.t -> (int, Error.t) result
(** [insert_before capability child ~anchor] places [child] immediately before
    a direct sibling. *)

val remove : t -> Renderable.t -> (unit, Error.t) result
(** [remove capability child] detaches a direct child without destroying it. *)

module Private : sig
  (** Construction used by renderer and concrete retained containers. *)
  val of_renderable : Renderable.t -> t
end
