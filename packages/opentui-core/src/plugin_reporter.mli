(** A non-authoritative, composable diagnostic sink. *)

type t

val create : (Plugin_failure.t -> unit) -> t
val ignore : t
val compose : t -> t -> t
val report : t -> Plugin_failure.t -> unit

(** Failures raised by reporter callbacks are retained here and never sent back
    through the reporter. *)
val failures : t -> Plugin_failure.t list
