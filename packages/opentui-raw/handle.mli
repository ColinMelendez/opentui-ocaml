(** An opaque value representing a handle owned by the native OpenTUI ABI. *)

type t

val of_int32 : int32 -> t
val to_int32 : t -> int32
