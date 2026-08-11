(** Owner-scoped renderer handles for the pinned native ABI.

    Buffer values returned by this module are borrowed children of the
    renderer. Closing a renderer invalidates its buffers and is idempotent. *)
type t

type render_status = Rendered | Skipped | Failed
(** The native renderer's frame outcome. *)

(** [create ~width ~height] creates a renderer with positive dimensions. *)
val create : width:int32 -> height:int32 -> (t, Error.t) result

(** [resize renderer ...] resizes the renderer and its borrowed buffers. *)
val resize : t -> width:int32 -> height:int32 -> (unit, Error.t) result

(** [close renderer] destroys the renderer and invalidates borrowed buffers. *)
val close : t -> unit

(** [current_buffer renderer] returns the current renderer-owned buffer. *)
val current_buffer : t -> (Buffer.t, Error.t) result

(** [next_buffer renderer] returns the next renderer-owned buffer. *)
val next_buffer : t -> (Buffer.t, Error.t) result

(** [render renderer ~force] presents the native frame and reports its status. *)
val render : t -> force:bool -> (render_status, Error.t) result

module Private : sig
  (** Internal access for higher-level raw submodules while the renderer is
      open. *)
  val with_open :
    t ->
    (Native_token.Renderer.t -> ('a, Error.t) result) ->
    ('a, Error.t) result
end
