(** Internal shared lifetime state for a group of raw native values. *)
type t

val is_open : t -> bool
(** [is_open owner] reports whether the owner still permits native calls. *)

module Private : sig
  (** Internal creation and invalidation operations. *)
  val create : unit -> t
  val close : t -> unit
end
