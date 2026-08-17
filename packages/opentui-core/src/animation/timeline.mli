type t

type state = Idle | Playing | Paused | Completed | Faulted

type loops = Once | Count of int | Infinite

type update = {
  progress : float;
  current_time_ms : float;
  delta_time_ms : float;
}

type fault = Error.fault
type sync_token

val create :
  ?duration_ms:float ->
  ?loop:bool ->
  ?autoplay:bool ->
  ?on_complete:(unit -> unit) ->
  ?on_pause:(unit -> unit) ->
  unit ->
  (t, Error.t) result

val id : t -> int
val state : t -> state
val current_time_ms : t -> float
val duration_ms : t -> float
val progress : t -> float
val is_playing : t -> bool
val is_complete : t -> bool
val fault : t -> fault option
val item_count : t -> int

val add :
  t ->
  bindings:Property.binding list ->
  ?start_time_ms:float ->
  ?duration_ms:float ->
  ?easing:Easing.t ->
  ?loops:loops ->
  ?loop_delay_ms:float ->
  ?alternate:bool ->
  ?once:bool ->
  ?on_update:(update -> unit) ->
  ?on_start:(unit -> unit) ->
  ?on_loop:(unit -> unit) ->
  ?on_complete:(unit -> unit) ->
  unit ->
  (int, Error.t) result

val once :
  t ->
  bindings:Property.binding list ->
  ?start_time_ms:float ->
  ?duration_ms:float ->
  ?easing:Easing.t ->
  ?loops:loops ->
  ?loop_delay_ms:float ->
  ?alternate:bool ->
  ?on_update:(update -> unit) ->
  ?on_start:(unit -> unit) ->
  ?on_loop:(unit -> unit) ->
  ?on_complete:(unit -> unit) ->
  unit ->
  (int, Error.t) result

val call :
  t ->
  ?start_time_ms:float ->
  (unit -> unit) ->
  (int, Error.t) result

val sync :
  t ->
  t ->
  ?start_time_ms:float ->
  unit ->
  (sync_token, Error.t) result

val cancel_sync : sync_token -> (unit, Error.t) result

val play : t -> (unit, Error.t) result
val pause : t -> (unit, Error.t) result
val restart : t -> (unit, Error.t) result
val update : t -> delta_time_ms:float -> (unit, fault) result

module Sync : sig
  type t = sync_token

  val cancel : t -> (unit, Error.t) result
end

module Private : sig
  val id : t -> int
  val subtree : t -> t list
  val is_playing : t -> bool
  val is_engine_root : t -> engine_id:int -> bool

  val add_state_listener : t -> (t -> unit) -> int
  val remove_state_listener : t -> int -> unit

  val attach_engine :
    t ->
    engine_id:int ->
    token_id:int ->
    promote:(t -> unit) ->
    (unit, Error.t) result

  val detach_engine : t -> engine_id:int -> token_id:int -> unit

  val engine_update :
    t ->
    engine_id:int ->
    delta_time_ms:float ->
    (unit, fault) result
end
