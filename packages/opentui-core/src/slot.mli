(** One independently typed slot and its contribution-only sink. *)

type 'props t
type 'props sink

val create :
  host:Plugin_host.t ->
  id:Plugin_id.t ->
  (('props t * 'props sink), Plugin_failure.t) result

val id : 'props t -> Plugin_id.t

val contribute :
  Plugin_host.scope ->
  'props sink ->
  render:('props -> (Slot_view.t option, Plugin_failure.t) result) ->
  (unit, Plugin_failure.t) result

module Private : sig
  type 'props contribution
  type subscription

  val subscribe :
    'props t ->
    notify:(unit -> Plugin_failure.t list) ->
    (subscription, Plugin_failure.t) result

  val unsubscribe : subscription -> unit
  val contributions : 'props t -> 'props contribution list
  val contribution_instance : 'props contribution -> Plugin_host.instance
  val contribution_render :
    'props contribution ->
    'props ->
    (Slot_view.t option, Plugin_failure.t) result
  val host : 'props t -> Plugin_host.t
  val id : 'props t -> Plugin_id.t
  val notify : 'props t -> Plugin_failure.t list
end
