(** Caller-run frame scheduling for one renderer on one Eio domain. *)

type t

type error =
  | Closed
  | Missing_clock
  | Wrong_domain
  | Switch_mismatch
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
    Recoverable renderer frame failures are emitted through the renderer's
    render-error event and retried at the configured frame cadence. The
    operation returns when [close] is called, the renderer is destroyed, or a
    structural scheduler error occurs. It must run in the clock's owner domain. *)

val set_frames_per_second : t -> int -> (unit, error) result
(** [set_frames_per_second scheduler frames_per_second] changes the live frame
    cadence to [frames_per_second] while the scheduler is running or idle. The
    new interval takes effect on the next deadline computation; the caller is
    trusted to choose a sensible positive value. Returns [Closed] or
    [Invalid_frames_per_second] without mutation on failure. *)

val frames_per_second : t -> (int, error) result
(** [frames_per_second scheduler] reports the current configured cadence. *)

val close : t -> (unit, error) result
(** [close] idempotently stops the scheduler without destroying its renderer or
    closing its Eio clock when called from the owner domain. Wrong-domain calls
    return [Wrong_domain] without mutation. The clock remains owned by the
    switch supplied to {!Eio_clock.create}. *)
