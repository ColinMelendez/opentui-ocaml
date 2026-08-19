type color = int * int * int * int
type cell = int32 * int32 * int32 * color * color * int32
type text = string * int32 * int32 * color * color * int32
type grayscale_buffer =
  int32 * int32 * floatarray * int32 * int32 * color option * color option
type box =
  int32 * int32 * int32 * int32 * int32 array * int32 * color * color * color
  * string option * string option
type yoga_layout = float * float * float * float * float * float

type capabilities =
  bool
  * bool
  * bool
  * bool
  * int
  * bool
  * bool
  * bool
  * bool
  * bool
  * bool
  * bool
  * bool
  * bool
  * bool
  * bool
  * bool
  * bool
  * int
  * int
  * string
  * string
  * bool
  * int

type span_feed_options = int32 * int32 * int64 * int * bool * int32
type span_feed_stats = int64 * int64 * int32 * int32
type image_info = int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32
type cursor_state = int32 * int32 * bool * int * bool * color

val renderer_create :
  int32 -> int32 -> int -> int -> Native_token.Span_feed.t option ->
  int * Native_token.Renderer.t
val renderer_resize : Native_token.Renderer.t -> int32 -> int32 -> int
val renderer_write_out : Native_token.Renderer.t -> bytes -> int
val renderer_query_terminal_capabilities : Native_token.Renderer.t -> int
val renderer_trigger_notification :
  Native_token.Renderer.t -> bytes -> bytes option -> int * bool
val renderer_set_background_color :
  Native_token.Renderer.t -> color -> int
val renderer_set_cursor_position :
  Native_token.Renderer.t -> int32 -> int32 -> bool -> int
val renderer_set_cursor_color :
  Native_token.Renderer.t -> color -> int
val renderer_set_cursor_style_options :
  Native_token.Renderer.t -> int option -> bool option -> color option ->
  int option -> int
val renderer_cursor_state :
  Native_token.Renderer.t -> int * cursor_state
val renderer_destroy : Native_token.Renderer.t -> unit
val renderer_buffer :
  Native_token.Renderer.t -> bool -> int * Native_token.Buffer.t
val renderer_render : Native_token.Renderer.t -> bool -> int
val renderer_set_render_offset : Native_token.Renderer.t -> int32 -> int
val renderer_reset_split_scrollback :
  Native_token.Renderer.t -> int32 -> int32 -> int * int32
val renderer_sync_split_scrollback :
  Native_token.Renderer.t -> int32 -> int * int32
val renderer_get_split_output_offset :
  Native_token.Renderer.t -> int32 -> int * int32
val renderer_set_pending_split_footer_transition :
  Native_token.Renderer.t ->
  int32 * int32 * int32 * int32 * int32 * int32 -> int
val renderer_clear_pending_split_footer_transition :
  Native_token.Renderer.t -> int
val renderer_repaint_split_footer :
  Native_token.Renderer.t -> int32 -> bool -> int * int32
val renderer_commit_split_footer_snapshot :
  Native_token.Renderer.t ->
  Native_token.Optimized_buffer.t ->
  int32 -> bool -> bool -> int32 -> bool -> bool -> bool -> int * int32
val optimized_buffer_as_buffer :
  Native_token.Optimized_buffer.t -> Native_token.Buffer.t
val renderer_add_to_hit_grid :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int32 -> int
val renderer_add_to_hit_grid_unchecked :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int32 -> unit
val renderer_clear_current_hit_grid : Native_token.Renderer.t -> int
val renderer_clear_current_hit_grid_unchecked : Native_token.Renderer.t -> unit
val renderer_clear_next_hit_grid : Native_token.Renderer.t -> int
val renderer_clear_next_hit_grid_unchecked : Native_token.Renderer.t -> unit
val renderer_hit_grid_push_scissor_rect :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int
val renderer_hit_grid_push_scissor_rect_unchecked :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> unit
val renderer_hit_grid_pop_scissor_rect : Native_token.Renderer.t -> int
val renderer_hit_grid_pop_scissor_rect_unchecked : Native_token.Renderer.t -> unit
val renderer_hit_grid_clear_scissor_rects : Native_token.Renderer.t -> int
val renderer_hit_grid_clear_scissor_rects_unchecked : Native_token.Renderer.t -> unit
val renderer_add_to_current_hit_grid_clipped :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int32 -> int
val renderer_add_to_current_hit_grid_clipped_unchecked :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int32 -> unit
val renderer_check_hit :
  Native_token.Renderer.t -> int32 -> int32 -> int * int32
val renderer_check_hit_unchecked :
  Native_token.Renderer.t -> int32 -> int32 -> int
val renderer_get_hit_grid_dirty : Native_token.Renderer.t -> int * bool
val renderer_get_hit_grid_dirty_unchecked : Native_token.Renderer.t -> bool
val buffer_dimensions : Native_token.Buffer.t -> int * int32 * int32
val buffer_clear : Native_token.Buffer.t -> color -> int
val buffer_set_cell : Native_token.Buffer.t -> cell -> int
val buffer_draw_text : Native_token.Buffer.t -> text -> int
val buffer_set_cell_with_alpha_blending : Native_token.Buffer.t -> cell -> int
val buffer_fill_rect :
  Native_token.Buffer.t -> int32 * int32 * int32 * int32 * color -> int
val buffer_draw_grayscale_buffer :
  Native_token.Buffer.t -> grayscale_buffer -> int
val buffer_draw_grayscale_buffer_supersampled :
  Native_token.Buffer.t -> grayscale_buffer -> int
val buffer_draw_box : Native_token.Buffer.t -> box -> int
val buffer_draw_text_buffer_view :
  Native_token.Buffer.t -> Native_token.Text_buffer_view.t -> int32 -> int32 -> int
val buffer_draw_frame_buffer :
  Native_token.Buffer.t ->
  (int32 * int32 * Native_token.Optimized_buffer.t * int32 * int32 * int32 * int32) -> int
val buffer_draw_grid :
  Native_token.Buffer.t ->
  (int32 array * color * color * int32 array * int32 array * bool * bool) -> int
val buffer_write_resolved_chars :
  Native_token.Buffer.t -> bytes -> bool -> int * int32
val buffer_draw_image :
  Native_token.Buffer.t ->
  (int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 *
   int32 * Native_token.Image.t) -> int
val buffer_color_matrix :
  Native_token.Buffer.t -> floatarray -> floatarray -> float -> int -> int
val buffer_color_matrix_uniform :
  Native_token.Buffer.t -> floatarray -> float -> int -> int
val buffer_push_scissor_rect :
  Native_token.Buffer.t -> int32 * int32 * int32 * int32 -> int
val buffer_pop_scissor_rect : Native_token.Buffer.t -> int
val buffer_clear_scissor_rects : Native_token.Buffer.t -> int
val buffer_push_opacity : Native_token.Buffer.t -> float -> int
val buffer_pop_opacity : Native_token.Buffer.t -> int
val buffer_get_current_opacity : Native_token.Buffer.t -> float
val buffer_clear_opacity : Native_token.Buffer.t -> int
type buffer_snapshot = int32 array * int32 array * int32 array * int32 array
val buffer_snapshot : Native_token.Buffer.t -> int * buffer_snapshot
val buffer_restore : Native_token.Buffer.t -> buffer_snapshot -> int
val image_info : bytes -> int * image_info
val image_decode : bytes -> int * Native_token.Image.t
val image_create_from_rgba :
  bytes -> int32 -> int32 -> int32 -> int * Native_token.Image.t
val image_destroy : Native_token.Image.t -> unit
val image_retain : Native_token.Image.t -> int * Native_token.Image.t
val image_get_info : Native_token.Image.t -> int * image_info
val image_materialize : Native_token.Image.t -> int
val image_ensure_encoded_png : Native_token.Image.t -> int
val image_clone : Native_token.Image.t -> int * Native_token.Image.t
val image_copy_pixels : Native_token.Image.t -> bytes -> int32 -> bool -> int
val image_resize :
  Native_token.Image.t -> (int32 * int32 * int32) -> int * Native_token.Image.t
val image_extract :
  Native_token.Image.t -> (int32 * int32 * int32 * int32) ->
  int * Native_token.Image.t
val image_extend :
  Native_token.Image.t -> (int32 * int32 * int32 * int32 * bytes) ->
  int * Native_token.Image.t
val image_transform :
  Native_token.Image.t -> int32 -> int * Native_token.Image.t
val image_composite :
  Native_token.Image.t ->
  Native_token.Image.t -> (int32 * int32 * int32 * int32) ->
  int * Native_token.Image.t

module Optimized_buffer : sig
  val create :
    width:int32 -> height:int32 -> respect_alpha:bool -> width_method:int32 ->
    id:string -> int * Native_token.Optimized_buffer.t
  val destroy : Native_token.Optimized_buffer.t -> unit
  val dimensions : Native_token.Optimized_buffer.t -> int * int32 * int32
  val clear : Native_token.Optimized_buffer.t -> color -> int
  val set_cell : Native_token.Optimized_buffer.t -> cell -> int
  val set_cell_with_alpha_blending : Native_token.Optimized_buffer.t -> cell -> int
  val draw_text : Native_token.Optimized_buffer.t -> text -> int
  val draw_text_buffer_view :
    Native_token.Optimized_buffer.t -> Native_token.Text_buffer_view.t -> int32 -> int32 -> int
  val fill_rect :
    Native_token.Optimized_buffer.t -> int32 * int32 * int32 * int32 * color -> int
  val draw_grayscale_buffer :
    Native_token.Optimized_buffer.t -> grayscale_buffer -> int
  val draw_grayscale_buffer_supersampled :
    Native_token.Optimized_buffer.t -> grayscale_buffer -> int
  val draw_frame_buffer :
    Native_token.Optimized_buffer.t ->
    (int32 * int32 * Native_token.Optimized_buffer.t * int32 * int32 * int32 * int32) -> int
  val resize : Native_token.Optimized_buffer.t -> int32 -> int32 -> int
  val draw_grid :
    Native_token.Optimized_buffer.t ->
    (int32 array * color * color * int32 array * int32 array * bool * bool) -> int
  val draw_image :
    Native_token.Optimized_buffer.t ->
    (int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 *
   int32 * Native_token.Image.t) -> int
  val snapshot : Native_token.Optimized_buffer.t -> int * buffer_snapshot
  val restore : Native_token.Optimized_buffer.t -> buffer_snapshot -> int
end
val event_sink_create : unit -> int * Native_token.Event_sink.t
val event_sink_destroy : Native_token.Event_sink.t -> unit
val event_sink_poll :
  Native_token.Event_sink.t -> int * (bytes * bytes) option
val yoga_node_create : unit -> int * Native_token.Yoga_node.t
val yoga_node_free : Native_token.Yoga_node.t -> int
val yoga_node_free_recursive : Native_token.Yoga_node.t -> int
val yoga_node_insert_child :
  Native_token.Yoga_node.t -> Native_token.Yoga_node.t -> int32 -> int
val yoga_node_remove_child :
  Native_token.Yoga_node.t -> Native_token.Yoga_node.t -> int
val yoga_node_move_child :
  Native_token.Yoga_node.t -> Native_token.Yoga_node.t -> int32 -> int
val yoga_node_child_count : Native_token.Yoga_node.t -> int * int32
val yoga_node_calculate :
  Native_token.Yoga_node.t -> float -> float -> int32 -> int
val yoga_node_is_dirty : Native_token.Yoga_node.t -> int * bool
val yoga_node_mark_dirty : Native_token.Yoga_node.t -> int
val yoga_node_has_new_layout : Native_token.Yoga_node.t -> int * bool
val yoga_node_mark_layout_seen : Native_token.Yoga_node.t -> int
val yoga_node_style_set_value :
  Native_token.Yoga_node.t -> int32 -> int32 -> int32 -> float -> int
val yoga_node_style_set_enum :
  Native_token.Yoga_node.t -> int32 -> int32 -> int
val yoga_node_style_set_float :
  Native_token.Yoga_node.t -> int32 -> float -> int
val yoga_node_style_set_border :
  Native_token.Yoga_node.t -> int32 -> float -> int
val yoga_node_set_measure_func : Native_token.Yoga_node.t -> bool -> unit
val yoga_node_unset_measure_func : Native_token.Yoga_node.t -> unit
val yoga_node_has_measure_func : Native_token.Yoga_node.t -> bool
  val yoga_set_measure_callback :
    (Nativeint.t * float * int32 * float * int32 -> float * float) -> unit
val yoga_clear_measure_callback : unit -> unit
val yoga_node_pointer : Native_token.Yoga_node.t -> Nativeint.t
val yoga_node_layout :
  Native_token.Yoga_node.t -> int * yoga_layout option
val renderer_capabilities :
  Native_token.Renderer.t -> int * capabilities option
val process_capability_response :
  Native_token.Renderer.t -> string -> int

val span_feed_create :
  span_feed_options -> int * Native_token.Span_feed.t
val span_feed_close : Native_token.Span_feed.t -> int
val span_feed_write : Native_token.Span_feed.t -> bytes -> int
val span_feed_commit : Native_token.Span_feed.t -> int
val span_feed_reserve :
  Native_token.Span_feed.t -> int32 ->
  int * (Native_token.Reservation.t * int32 * bytes) option
val span_feed_reservation_commit :
  Native_token.Reservation.t -> bytes -> int32 -> int
val span_feed_reservation_cancel : Native_token.Reservation.t -> int
val span_feed_stats :
  Native_token.Span_feed.t -> int * span_feed_stats option
val span_feed_drain :
  Native_token.Span_feed.t -> int * (bytes * Native_token.Span.t) option
val span_release : Native_token.Span.t -> int

val text_buffer_create : int32 -> int * Native_token.Text_buffer.t
val text_buffer_destroy : Native_token.Text_buffer.t -> unit
val text_buffer_clear : Native_token.Text_buffer.t -> int
val text_buffer_reset : Native_token.Text_buffer.t -> int
val text_buffer_append :
  Native_token.Text_buffer.t ->
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t -> int
val text_buffer_register_mem_buffer :
  Native_token.Text_buffer.t ->
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t ->
  bool -> int * int32
val text_buffer_replace_mem_buffer :
  Native_token.Text_buffer.t -> int32 ->
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t ->
  bool -> int
val text_buffer_set_text_from_mem :
  Native_token.Text_buffer.t -> int32 -> int32 -> int
val text_buffer_length : Native_token.Text_buffer.t -> int * int32
val text_buffer_byte_size : Native_token.Text_buffer.t -> int * int32
val text_buffer_line_count : Native_token.Text_buffer.t -> int * int32
val text_buffer_load_file : Native_token.Text_buffer.t -> string -> int
val text_buffer_get_tab_width : Native_token.Text_buffer.t -> int * int32
val text_buffer_set_tab_width : Native_token.Text_buffer.t -> int32 -> int
type styled_chunk = string * color option * color option * int32 * string option
val text_buffer_set_styled_text : Native_token.Text_buffer.t -> styled_chunk list -> int
val text_buffer_clear_all_highlights : Native_token.Text_buffer.t -> int
type highlight = int32 * int32 * int32 * int * int
val text_buffer_add_highlight_by_char_range :
  Native_token.Text_buffer.t -> highlight -> int
val text_buffer_add_highlight :
  Native_token.Text_buffer.t -> int32 -> highlight -> int
val text_buffer_remove_highlights_by_ref :
  Native_token.Text_buffer.t -> int -> int
val text_buffer_clear_line_highlights :
  Native_token.Text_buffer.t -> int32 -> int
val text_buffer_set_default_fg : Native_token.Text_buffer.t -> color option -> int
val text_buffer_set_default_bg : Native_token.Text_buffer.t -> color option -> int
val text_buffer_set_default_attributes : Native_token.Text_buffer.t -> int32 option -> int
val text_buffer_reset_defaults : Native_token.Text_buffer.t -> int
val text_buffer_set_syntax_style :
  Native_token.Text_buffer.t -> Native_token.Syntax_style.t option -> int
val syntax_style_create : unit -> int * Native_token.Syntax_style.t
val syntax_style_destroy : Native_token.Syntax_style.t -> unit
val syntax_style_register :
  Native_token.Syntax_style.t -> string -> color option -> color option -> int32 -> int * int32
val syntax_style_resolve : Native_token.Syntax_style.t -> string -> int * int32
val syntax_style_count : Native_token.Syntax_style.t -> int * int32
val text_buffer_view_create :
  Native_token.Text_buffer.t -> int * Native_token.Text_buffer_view.t
val text_buffer_view_destroy : Native_token.Text_buffer_view.t -> unit
val text_buffer_view_set_wrap_width :
  Native_token.Text_buffer_view.t -> int32 -> int
val text_buffer_view_set_wrap_mode :
  Native_token.Text_buffer_view.t -> int32 -> int
val text_buffer_view_set_first_line_offset :
  Native_token.Text_buffer_view.t -> int32 -> int
val text_buffer_view_set_selection :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> Color.t option ->
  Color.t option -> int
val text_buffer_view_update_selection :
  Native_token.Text_buffer_view.t -> int32 -> Color.t option -> Color.t option ->
  int
val text_buffer_view_reset_selection : Native_token.Text_buffer_view.t -> int
val text_buffer_view_get_selection_info :
  Native_token.Text_buffer_view.t -> int64
val text_buffer_view_set_local_selection :
  Native_token.Text_buffer_view.t ->
  (int32 * int32 * int32 * int32 * Color.t option * Color.t option) ->
  int * bool
val text_buffer_view_update_local_selection :
  Native_token.Text_buffer_view.t ->
  (int32 * int32 * int32 * int32 * Color.t option * Color.t option) ->
  int * bool
val text_buffer_view_reset_local_selection :
  Native_token.Text_buffer_view.t -> int
val text_buffer_view_get_selected_text :
  Native_token.Text_buffer_view.t -> bytes -> int32 -> int * int32
val text_buffer_view_set_viewport_size :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> int
val text_buffer_view_set_viewport :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> int32 -> int32 -> int
val text_buffer_view_get_virtual_line_count :
  Native_token.Text_buffer_view.t -> int * int32
val text_buffer_view_set_tab_indicator :
  Native_token.Text_buffer_view.t -> int32 -> int
val text_buffer_view_set_tab_indicator_color :
  Native_token.Text_buffer_view.t -> Color.t -> int
val text_buffer_view_set_truncate : Native_token.Text_buffer_view.t -> bool -> int
val text_buffer_view_measure_for_dimensions :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> int * int32 * int32
val text_buffer_view_get_line_info :
  Native_token.Text_buffer_view.t ->
  int * int32 array * int32 array * int32 array * int32 array * int32
val text_buffer_view_get_logical_line_info :
  Native_token.Text_buffer_view.t ->
  int * int32 array * int32 array * int32 array * int32 array * int32
val native_renderable_create :
  unit -> int * Native_token.Native_renderable.t
val native_renderable_destroy : Native_token.Native_renderable.t -> unit
val native_renderable_attach_yoga_node :
  Native_token.Native_renderable.t -> Native_token.Yoga_node.t -> int
val yoga_node_claim_native_renderable : Native_token.Yoga_node.t -> int
val yoga_node_release_native_renderable : Native_token.Yoga_node.t -> int
val yoga_node_set_native_measure_attached :
  Native_token.Yoga_node.t -> bool -> int
val native_renderable_set_measure_target :
  Native_token.Native_renderable.t -> int32 -> Native_token.Text_buffer_view.t -> int
val native_renderable_clear_measure_target :
  Native_token.Native_renderable.t -> int
