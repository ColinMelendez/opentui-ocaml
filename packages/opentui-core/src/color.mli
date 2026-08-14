(** Validated RGBA colors used by the imperative renderer. *)
type t

(** [rgba ...] constructs a color whose channels are in [0, 255]. *)
val rgba :
  red:int -> green:int -> blue:int -> alpha:int -> (t, Native.Error.t) result

(** [rgb ...] constructs an opaque color with alpha [255]. *)
val rgb : red:int -> green:int -> blue:int -> (t, Native.Error.t) result

(** The opaque black color. *)
val black : t

(** The opaque white color. *)
val white : t

(** A fully transparent black color. *)
val transparent : t

(** [channels color] returns [red, green, blue, alpha]. *)
val channels : t -> int * int * int * int

module Private : sig
  (** Internal conversion used by the raw renderer bridge. *)
  val to_raw : t -> Opentui_raw.Color.t
end
