(** Explicit cancellation for an owner-local event registration. *)

type t
(** A registration owned by one event source. *)

(** [cancel subscription] removes the registration. Repeated cancellation is
    harmless. *)
val cancel : t -> unit

module Private : sig
  (** Internal construction for event-source implementations. *)
  val create : (unit -> unit) -> t
end
