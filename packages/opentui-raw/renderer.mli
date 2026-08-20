(** Owner-scoped renderer handles for the pinned native ABI.

    Buffer values returned by this module are borrowed children of the
    renderer. Closing a renderer invalidates its buffers and is idempotent. *)
type t

type output = Memory | Stdout | Feed of Span_feed.t
(** The native destination selected when the renderer is created. A [Feed] is
    borrowed from its caller and remains the caller's responsibility. *)

type remote_mode = Auto | Local | Remote
(** How the native renderer treats its output destination. *)

type render_status = Rendered | Skipped | Failed
(** The native renderer's frame outcome. *)

type split_footer_transition = Viewport_scroll | Clear_stale_rows

type cursor_style = Block | Line | Underline | Default

type mouse_pointer_style =
  | Mouse_default
  | Mouse_pointer
  | Mouse_text
  | Mouse_crosshair
  | Mouse_move
  | Mouse_not_allowed

type cursor_style_options = {
  style : cursor_style option;
  blinking : bool option;
  color : Color.t option;
  cursor : mouse_pointer_style option;
}

type cursor_state = {
  x : int32;
  y : int32;
  visible : bool;
  style : cursor_style;
  blinking : bool;
  color : Color.t;
}

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

(** [create ~width ~height] creates a renderer with positive dimensions. The
    default is the low-level memory destination. *)
val create :
  ?output:output -> ?remote_mode:remote_mode ->
  width:int32 -> height:int32 -> unit -> (t, Error.t) result

(** [resize renderer ...] resizes the renderer and its borrowed buffers. *)
val resize : t -> width:int32 -> height:int32 -> (unit, Error.t) result

(** [write_out renderer bytes] appends owner-synchronous terminal bytes to the
    renderer's configured output backend, preserving order with frame output. *)
val write_out : t -> bytes -> (unit, Error.t) result

(** [set_background_color renderer ~color] changes the native backdrop and
    requests the next renderer frame. *)
val set_background_color : t -> color:Color.t -> (unit, Error.t) result

(** [set_cursor_position renderer ...] updates the native terminal cursor. The
    native renderer clamps coordinates to its one-based dimensions. *)
val set_cursor_position :
  t -> x:int32 -> y:int32 -> ?visible:bool -> unit -> (unit, Error.t) result

(** [set_cursor_color renderer ~color] updates the native terminal cursor
    color without changing its style or blinking mode. *)
val set_cursor_color : t -> color:Color.t -> (unit, Error.t) result

(** [set_cursor_style renderer options] updates only the cursor options supplied
    by the caller. Unspecified style, blinking, and color values persist. *)
val set_cursor_style :
  t -> cursor_style_options -> (unit, Error.t) result

(** [cursor_state renderer] reads the native terminal cursor presentation. *)
val cursor_state : t -> (cursor_state, Error.t) result

(** [close renderer] destroys the renderer and invalidates borrowed buffers. *)
val close : t -> unit

(** [drain_output renderer] copies and returns complete native output spans.
    It remains available after [close] so the owner can drain native teardown
    bytes before closing a borrowed feed. *)
val drain_output : t -> (Span_feed.Span.t list, Error.t) result

(** [current_buffer renderer] returns the current renderer-owned buffer. *)
val current_buffer : t -> (Buffer.t, Error.t) result

(** [next_buffer renderer] returns the next renderer-owned buffer. *)
val next_buffer : t -> (Buffer.t, Error.t) result

(** [render renderer ~force] presents the native frame and reports its status. *)
val render : t -> force:bool -> (render_status, Error.t) result

(** Split-footer primitives mirror the native scrollback state machine. The
    returned offset is the output-space render offset selected by native code. *)
val set_render_offset : t -> offset:int32 -> (unit, Error.t) result
val reset_split_scrollback :
  t -> seed_rows:int32 -> pinned_render_offset:int32 -> (int32, Error.t) result
val sync_split_scrollback :
  t -> pinned_render_offset:int32 -> (int32, Error.t) result
val get_split_output_offset :
  t -> surface_offset:int32 -> (int32, Error.t) result
val set_pending_split_footer_transition :
  t ->
  split_footer_transition ->
  source_top_line:int32 ->
  source_height:int32 ->
  target_top_line:int32 ->
  target_height:int32 ->
  scroll_lines:int32 ->
  (unit, Error.t) result
val clear_pending_split_footer_transition : t -> (unit, Error.t) result
val repaint_split_footer :
  t -> pinned_render_offset:int32 -> force:bool ->
  (int32 * render_status, Error.t) result
val commit_split_footer_snapshot :
  t ->
  snapshot:Optimized_buffer.t ->
  row_columns:int32 ->
  start_on_new_line:bool ->
  trailing_newline:bool ->
  pinned_render_offset:int32 ->
  force:bool ->
  begin_frame:bool ->
  finalize_frame:bool ->
  (int32 * render_status, Error.t) result

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
