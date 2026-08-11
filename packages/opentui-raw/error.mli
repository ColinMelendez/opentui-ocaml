(** Structured errors at the OCaml/native OpenTUI boundary. *)
type t =
  | Invalid_argument
  | Closed
  | Stale_handle
  | Native_failure
  | Output_too_small
  | Queue_overflow
  | No_space
  | Max_bytes
  | Busy

(** [message error] is a diagnostic string for [error]. *)
val message : t -> string

(** [pp ppf error] formats [error] for diagnostics. *)
val pp : Format.formatter -> t -> unit

module Private : sig
  (** Internal decoding of native status codes. *)
  val of_native_status : int -> t option
end
