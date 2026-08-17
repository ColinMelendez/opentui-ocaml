(** Renderer-bounded transactional plugin ownership. *)

type errors = Plugin_failure.t * Plugin_failure.t list
type scope
type instance
type t

type 'capabilities definition

val define :
  id:Plugin_id.t ->
  order:int ->
  install:(scope -> 'capabilities -> (unit, Plugin_failure.t) result) ->
  ('capabilities definition, Plugin_failure.t) result

module Scope : sig
  type t = scope

  val on_release :
    t ->
    (unit -> (unit, Plugin_failure.t) result) ->
    (unit, Plugin_failure.t) result
end

module Instance : sig
  type t = instance

  val id : t -> Plugin_id.t
  val order : t -> int
  val set_order : t -> int -> (unit, Plugin_failure.t) result
  val uninstall : t -> (unit, errors) result
end

module Host : sig
  type nonrec t = t

  val create : renderer:Renderer.t -> reporter:Plugin_reporter.t -> t

  val install :
    t ->
    capabilities:'capabilities ->
    'capabilities definition ->
    (instance, errors) result

  val close : t -> (unit, errors) result
end

module Private : sig
  val register_slot :
    t -> Plugin_id.t -> (int, Plugin_failure.t) result

  val stage_contribution :
    scope ->
    slot_id:Plugin_id.t ->
    slot_key:int ->
    publish:(instance -> (unit, Plugin_failure.t) result) ->
    withdraw:(instance -> (unit, Plugin_failure.t) result) ->
    notify:(unit -> Plugin_failure.t list) ->
    (unit, Plugin_failure.t) result

  val scope_host : scope -> t
  val renderer : t -> Renderer.t
  val is_open : t -> bool
  val report : t -> Plugin_failure.t -> unit
  val instance_sequence : instance -> int
  val compare_instances : instance -> instance -> int
end
