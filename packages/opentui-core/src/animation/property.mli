type 'target t
type binding

val create :
  read:('target -> (float, Error.t) result) ->
  write:('target -> float -> (unit, Error.t) result) ->
  'target t

(** [bind property target ~to_] creates a typed binding. The endpoint is
    validated when the binding is added to a timeline, so this constructor
    never raises for malformed runtime data. *)
val bind : 'target t -> 'target -> to_:float -> binding

(** [bind_ref reference ~to_] is the convenient binding for a mutable numeric
    model value. *)
val bind_ref : float ref -> to_:float -> binding

module Private : sig
  val validate : binding -> (unit, Error.t) result
  val target_value : binding -> float
  val read : binding -> (float, Error.t) result
  val write : binding -> float -> (unit, Error.t) result
end
