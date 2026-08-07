type t =
  | Invalid_argument
  | Closed
  | Stale_handle
  | Native_failure
  | Output_too_small
  | Queue_overflow

val message : t -> string
val pp : Format.formatter -> t -> unit

module Private : sig
  val of_native_status : int -> t option
end
