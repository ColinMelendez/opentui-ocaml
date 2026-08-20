(** Structured failures raised at the webgpu.h boundary. *)

type t =
  | Closed of { operation : string }
  (** The owning device was closed before [operation] ran. *)
  | Invalid_argument of string
  (** A caller-supplied value violated a documented precondition. *)
  | Creation_failed of {
      what : string;
      code : int;
      message : string;
    }
  (** An object request or creation returned a non-success status; [what]
      names the object, [code] is the raw native status, and [message] is the
      native diagnostic when one was produced. *)
  | Map_failed of { code : int; message : string }
  (** A readback buffer map completed with a non-success status. *)
  | Native_failure of { operation : string }
  (** A synchronous native call returned failure without a status code. *)

val pp : Format.formatter -> t -> unit

val message : t -> string
