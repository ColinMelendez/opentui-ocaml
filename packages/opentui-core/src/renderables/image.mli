(** Capability-aware image rendering over the native image owner. *)

type fit = Fit | Cover | Fill
type source = Native of Native_image.t | Source of Native_image.source
type load_state =
  | Empty
  | Loading
  | Ready
  | Failed of Native_image.load_error
type t

(** [create context ...] binds the image owner to the calling domain. Path
    sources additionally require [sw] to delimit their cooperative Eio read
    lifetime. *)
val create :
  Render_context.t ->
  ?id:string ->
  ?source:source ->
  ?fit:fit ->
  ?protocol:Native_image.protocol ->
  ?sw:Eio.Switch.t ->
  ?buffered:bool ->
  ?width:int ->
  ?height:int ->
  ?on_load:(Native_image.info -> unit) ->
  ?on_error:(Native_image.load_error -> unit) ->
  unit -> (t, Error.t) result

val as_renderable : t -> Renderable.t
val image : t -> Native_image.t option
val source : t -> source option
val fit : t -> fit
(** Mutating operations return [Error.Wrong_domain] when called outside the
    domain that created the image. *)
val set_fit : t -> fit -> (unit, Error.t) result
val protocol : t -> Native_image.protocol
val set_protocol : t -> Native_image.protocol -> (unit, Error.t) result
val effective_protocol : t -> Native_image.protocol
val state : t -> load_state
val cell_aspect_ratio : t -> float
val loading : t -> bool
val buffered : t -> bool
val load_error : t -> Native_image.load_error option
val set_source : t -> source option -> (unit, Error.t) result
val get_fitted_size :
  t -> target_width:int -> target_height:int -> ?cell_aspect:float -> unit -> int * int
val resolve_protocol :
  Native_image.protocol -> Terminal_capabilities.t option ->
  has_resolution:bool -> Native_image.protocol
(** [destroy image] must run on the owner domain. Calling it from another
    domain raises [Invalid_argument], because the unit-returning operation
    cannot represent [Error.Wrong_domain]. *)
val destroy : t -> unit
