(** Caller-run frame scheduling for one renderer on one Eio domain. *)

type t

type error =
  | Closed
  | Missing_clock
  | Clock_mismatch
  | Already_attached
  | Already_running
  | Invalid_frames_per_second
  | Render_error of Error.t

val message : error -> string
val pp : Format.formatter -> error -> unit

val create :
  sw:Eio.Switch.t ->
  clock:Eio_clock.t ->
  renderer:Renderer.t ->
  ?frames_per_second:int ->
  unit ->
  (t, error) result
(** [create] attaches one scheduler to [renderer]. The renderer must have been
    created with the same Eio-backed clock capability. *)

val run : t -> (unit, error) result
(** [run] consumes requests and drives live frames on the caller's Eio fiber.
    It returns when [close] is called, the renderer is destroyed, or a frame
    fails. *)

val close : t -> unit
(** [close] idempotently stops the scheduler without destroying its renderer. *)
