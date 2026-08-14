(** Validated colors accepted by native buffer operations. *)
type t

(** [rgba ...] constructs a color whose channels are in [0, 255]. *)
val rgba :
  red:int -> green:int -> blue:int -> alpha:int -> (t, Error.t) result

(** [rgb ...] constructs an opaque color with alpha [255]. *)
val rgb : red:int -> green:int -> blue:int -> (t, Error.t) result

(** [black] and [white] are opaque standard colors. *)
val black : t
val white : t

(** [transparent] has zero alpha and black RGB channels. *)
val transparent : t

(** [channels color] returns [red, green, blue, alpha]. *)
val channels : t -> int * int * int * int

module Private : sig
  (** Internal conversion to the native tuple representation. *)
  val to_native : t -> int * int * int * int
end
