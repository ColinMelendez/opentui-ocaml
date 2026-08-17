(** Explicit ownership for deterministic animation timelines. *)

type t
type registration
type run_once

type failure = {
  timeline_id : int;
  fault : Timeline.fault;
}

type diagnostic =
  | Timeline_failure of failure
  | Engine_failure of Error.t
  | Renderer_failure of string
  | Failure_callback_exception of exn

(** [create ()] creates an unattached engine. It can be driven manually or
    attached to one renderer later. *)
val create : ?on_failure:(failure -> unit) -> unit -> t

val register : t -> Timeline.t -> (registration, Error.t) result
val release : registration -> unit

(** [run_once] registers and starts a timeline, releasing its registration
    when the timeline completes or faults. *)
val run_once : t -> Timeline.t -> (run_once, Error.t) result
val cancel : run_once -> (unit, Error.t) result

(** [update] advances every eligible registered root. A successful result may
    contain per-timeline faults; all roots in the frame snapshot receive their
    update opportunity. *)
val update : t -> delta_time_ms:float -> (failure list, Error.t) result

(** Attach the engine to one renderer's pre-render phase. The engine receives
    the renderer's seconds-valued frame delta and converts it to milliseconds
    at this boundary. *)
val attach : t -> renderer:Renderer.t -> (unit, Error.t) result
val detach : t -> unit

val clear : t -> (unit, Error.t) result
val destroy : t -> unit
val diagnostics : t -> diagnostic list
