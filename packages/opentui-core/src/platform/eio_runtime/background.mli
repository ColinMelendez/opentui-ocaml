(** Application-owned CPU work on reusable Eio executor domains.

    This module moves only the [work] closure across the executor boundary.
    The completion callback always runs in the domain that called {!bind} and
    {!submit}. Renderer, event, terminal, and native values must not be
    captured by either closure. *)

type t
(** An application-owned executor pool. *)

type submitter
(** A submission capability bound to one owner-domain Eio switch. *)

type job
(** A submitted job's owner-domain completion lease. *)

type error =
  | Invalid_worker_count of int
  | Closed
  | Wrong_domain
(** Errors admitting a pool, submitter, or job. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create :
  sw:Eio.Switch.t ->
  domain_mgr:_ Eio.Domain_manager.t ->
  worker_count:int ->
  (t, error) result
(** [create ~sw ~domain_mgr ~worker_count] creates an application-owned
    executor pool whose workers are released with [sw]. The submitting
    application domain counts toward {!Domain.recommended_domain_count}; a
    positive worker count is accepted only when it leaves that domain within
    the recommended total. *)

val bind :
  t ->
  sw:Eio.Switch.t ->
  (submitter, error) result
(** [bind pool ~sw] binds owner-domain fibers and completion callbacks to [sw].
    The returned submitter must be used from the domain in which it was
    created. *)

val submit :
  submitter ->
  work:(unit -> ('value, 'work_error) result) ->
  on_complete:(('value, 'work_error) result -> unit) ->
  (job, error) result
(** [submit submitter ~work ~on_complete] runs [work] on an executor worker at
    weight [1.0]. [on_complete] runs on the submitter's owner domain and
    receives the worker's typed result unchanged. Unexpected exceptions from
    [work] or [on_complete] fail the submitter's Eio switch. *)

val cancel : job -> unit
(** [cancel job] suppresses its completion callback when delivery has not
    started. It does not forcibly terminate executor work already running. *)
