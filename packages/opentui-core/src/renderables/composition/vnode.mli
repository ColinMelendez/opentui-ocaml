(** Inert composition descriptions.  Instantiation creates ordinary retained
    {!Renderable.t} identities; VNodes never form a second runtime tree. *)

type t
type child = t

type 'props constructor =
  Render_context.t -> 'props -> (Renderable.t, Error.t) result

val empty : t
val of_renderable : Renderable.t -> t
val fragment : child list -> t
val h : 'props constructor -> 'props -> child list -> t

val add_child : t -> child -> unit
val add_post_mount : t -> (Renderable.t -> (unit, Error.t) result) -> unit
val delegate : t -> (string * string) list -> unit

val instantiate : Render_context.t -> t -> (Renderable.t list, Error.t) result
val instantiate_one : Render_context.t -> t -> (Renderable.t, Error.t) result

val resolve_delegate :
  Renderable.t -> name:string -> id:string -> Renderable.t option
