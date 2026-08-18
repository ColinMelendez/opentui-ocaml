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
  | Invalid_frame_rate
  | Render_error of Error.t

val message : error -> string
val pp : Format.formatter -> error -> unit

val create :
  sw:Eio.Switch.t ->
  clock:Eio_clock.t ->
  renderer:Renderer.t ->
  ?target_frames_per_second:int ->
  ?max_frames_per_second:int ->
  unit ->
  (t, error) result
(** [create] attaches one scheduler to [renderer]. The renderer must have been
    created with the same Eio-backed clock capability. Live frames use
    [target_frames_per_second]. Coalesced on-demand frames are limited by
    [max_frames_per_second]. *)

val run : t -> (unit, error) result
(** [run] consumes coalesced render requests and drives live frames on the
    caller's Eio fiber. Recoverable renderer frame failures are emitted through
    the renderer's render-error event and retried at the active frame cadence.
    The operation returns when [close] is called, the renderer is destroyed, or
    a structural scheduler error occurs. It must run in the clock's owner
    domain. *)

val set_target_frames_per_second : t -> int -> (unit, error) result
(** [set_target_frames_per_second scheduler frames_per_second] changes the live
    frame cadence while the scheduler is running or idle. Non-positive values
    return [Invalid_frame_rate] without mutation. *)

val target_frames_per_second : t -> (int, error) result
(** [target_frames_per_second scheduler] reports the live frame cadence. *)

val set_max_frames_per_second : t -> int -> (unit, error) result
(** [set_max_frames_per_second scheduler frames_per_second] changes the maximum
    cadence for coalesced on-demand frames while the scheduler is running or
    idle. Non-positive values return [Invalid_frame_rate] without mutation. *)

val max_frames_per_second : t -> (int, error) result
(** [max_frames_per_second scheduler] reports the on-demand frame limit. *)

val close : t -> (unit, error) result
(** [close] idempotently stops the scheduler without destroying its renderer or
    closing its Eio clock when called from the owner domain. Wrong-domain calls
    return [Wrong_domain] without mutation. The clock remains owned by the
    switch supplied to {!Eio_clock.create}. *)
