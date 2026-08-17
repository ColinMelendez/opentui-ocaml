(** A detached native renderable and its visibility lifecycle. *)

type t

val create :
  ?on_activate:(unit -> (unit, Plugin_failure.t) result) ->
  ?on_deactivate:(unit -> (unit, Plugin_failure.t) result) ->
  Renderable.t ->
  t

val renderable : t -> Renderable.t

module Private : sig
  val claim : t -> (unit, Plugin_failure.t) result
  val activate : t -> (unit, Plugin_failure.t) result
  val deactivate : t -> (unit, Plugin_failure.t) result
  val destroy : t -> unit
  val is_active : t -> bool
  val is_destroyed : t -> bool
end
