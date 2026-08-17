(** Typed compiled plugins and their renderer-bounded host. *)

module Id = Plugin_id
module Failure = Plugin_failure
module Reporter = Plugin_reporter

type errors = Plugin_host.errors
type instance = Plugin_host.instance
type 'capabilities definition = 'capabilities Plugin_host.definition

val errors_to_list : errors -> Failure.t list

module Scope : sig
  type t = Plugin_host.scope

  val contribute :
    t ->
    'props Slot.sink ->
    render:('props -> (Slot_view.t option, Failure.t) result) ->
    (unit, Failure.t) result

  val on_release :
    t ->
    (unit -> (unit, Failure.t) result) ->
    (unit, Failure.t) result
end

val define :
  id:Id.t ->
  order:int ->
  install:(Scope.t -> 'capabilities -> (unit, Failure.t) result) ->
  ('capabilities definition, Failure.t) result

module Instance : sig
  type t = instance

  val id : t -> Id.t
  val order : t -> int
  val set_order : t -> int -> (unit, Failure.t) result
  val uninstall : t -> (unit, errors) result
end

module Host : sig
  type t = Plugin_host.t

  val create : renderer:Renderer.t -> reporter:Reporter.t -> t

  val install :
    t ->
    capabilities:'capabilities ->
    'capabilities definition ->
    (Instance.t, errors) result

  val close : t -> (unit, errors) result
end
