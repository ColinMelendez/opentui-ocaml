(** Native ownership for the reference Yoga measure callback. *)

type measure_target = Text_buffer_view of Text_buffer_view.t
(** A concrete native object that supplies synchronous text measurement. *)

type t
(** An explicitly owned native measure-callback owner. *)

val create : unit -> (t, Error.t) result
val attach_yoga_node : t -> Yoga.Node.t -> (unit, Error.t) result
val set_measure_target : t -> measure_target -> (unit, Error.t) result
val clear_measure_target : t -> (unit, Error.t) result
val close : t -> (unit, Error.t) result
(** [close] clears the Yoga callback, releases borrowed targets, and then
    releases the native owner. The attached Yoga node remains independently
    owned and must be closed separately. *)

module Private : sig
  val with_open :
    t ->
    (Native_token.Native_renderable.t -> ('a, Error.t) result) ->
    ('a, Error.t) result
end
