(** An owned copy of one synchronous native event payload. *)
type t

(** [name event] returns the mutable owned event name bytes. *)
val name : t -> bytes

(** [data event] returns the mutable owned event data bytes. *)
val data : t -> bytes

module Private : sig
  (** Internal construction from already-copied payloads. *)
  val of_native : bytes -> bytes -> t
end
