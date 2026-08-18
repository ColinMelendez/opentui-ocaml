(** Owner-scoped renderer handles for the pinned native ABI.

    Buffer values returned by this module are borrowed children of the
    renderer. Closing a renderer invalidates its buffers and is idempotent. *)
type t

type render_status = Rendered | Skipped | Failed
(** The native renderer's frame outcome. *)

module Hit_grid : sig
  (** An opaque, renderer-owned hit-grid capability. It remains tied to its
      renderer owner and reports [Error.Closed] after that renderer closes. *)
  type t

  (** [add_to_hit_grid grid ...] writes a renderable rectangle to the native
      next grid. Signed origins are clipped by native renderer dimensions and
      active hit-grid scissors. *)
  val add_to_hit_grid :
    t ->
    x:int32 ->
    y:int32 ->
    width:int32 ->
    height:int32 ->
    id:int32 ->
    (unit, Error.t) result

  (** [clear_current_hit_grid grid] clears the committed grid for an explicit
      immediate rebuild. *)
  val clear_current_hit_grid : t -> (unit, Error.t) result

  (** [clear_next_hit_grid grid] aborts the in-progress next-grid build before
      native rendering performs its normal frame cleanup. *)
  val clear_next_hit_grid : t -> (unit, Error.t) result

  (** Hit-grid scissor state is native and frame-local. *)
  val hit_grid_push_scissor_rect :
    t ->
    x:int32 ->
    y:int32 ->
    width:int32 ->
    height:int32 ->
    (unit, Error.t) result
  val hit_grid_pop_scissor_rect : t -> (unit, Error.t) result
  val hit_grid_clear_scissor_rects : t -> (unit, Error.t) result

  (** [add_to_current_hit_grid_clipped grid ...] updates the committed grid
      using native clipping for immediate synchronization. *)
  val add_to_current_hit_grid_clipped :
    t ->
    x:int32 ->
    y:int32 ->
    width:int32 ->
    height:int32 ->
    id:int32 ->
    (unit, Error.t) result

  (** [check_hit grid ~x ~y] reads the committed native grid. [0l] means no
      target. *)
  val check_hit : t -> x:int32 -> y:int32 -> (int32, Error.t) result

  (** [get_hit_grid_dirty grid] reports whether the last committed frame
      changed the current grid. The native dirty value remains the baseline
      until a later commit recomputes it; resize invalidation is consumed by
      this read. *)
  val get_hit_grid_dirty : t -> (bool, Error.t) result

  module Private : sig
    (** These operations are allocation-free native fast paths for Core's
        open renderer context. The caller must keep the renderer owner open
        and must provide nonnegative widths, heights, and IDs. They perform no
        lifecycle or argument checks. *)
    val add_to_hit_grid_unchecked :
      t ->
      x:int32 ->
      y:int32 ->
      width:int32 ->
      height:int32 ->
      id:int32 ->
      unit
    val clear_current_hit_grid_unchecked : t -> unit
    val clear_next_hit_grid_unchecked : t -> unit
    val hit_grid_push_scissor_rect_unchecked :
      t ->
      x:int32 ->
      y:int32 ->
      width:int32 ->
      height:int32 ->
      unit
    val hit_grid_pop_scissor_rect_unchecked : t -> unit
    val hit_grid_clear_scissor_rects_unchecked : t -> unit
    val add_to_current_hit_grid_clipped_unchecked :
      t ->
      x:int32 ->
      y:int32 ->
      width:int32 ->
      height:int32 ->
      id:int32 ->
      unit
    val check_hit_unchecked : t -> x:int32 -> y:int32 -> int
    val get_hit_grid_dirty_unchecked : t -> bool
  end
end

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

(** [hit_grid renderer] creates an opaque capability for native hit-grid
    production and lookup. The capability borrows [renderer]'s owner. *)
val hit_grid : t -> Hit_grid.t

module Private : sig
  (** Internal access for higher-level raw submodules while the renderer is
      open. *)
  val with_open :
    t ->
    (Native_token.Renderer.t -> ('a, Error.t) result) ->
    ('a, Error.t) result
end
