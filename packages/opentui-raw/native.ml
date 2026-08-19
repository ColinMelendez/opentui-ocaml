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

external renderer_create :
  int32 -> int32 -> int -> int -> Native_token.Span_feed.t option ->
  int * Native_token.Renderer.t =
    "opentui_raw_renderer_create"

external renderer_resize :
  Native_token.Renderer.t -> int32 -> int32 -> int =
  "opentui_raw_renderer_resize"

external renderer_write_out :
  Native_token.Renderer.t -> bytes -> int =
  "opentui_raw_renderer_write_out"

external renderer_query_terminal_capabilities :
  Native_token.Renderer.t -> int =
  "opentui_raw_renderer_query_terminal_capabilities"

external renderer_trigger_notification :
  Native_token.Renderer.t -> bytes -> bytes option -> int * bool =
  "opentui_raw_renderer_trigger_notification"

external renderer_set_background_color :
  Native_token.Renderer.t -> color -> int =
  "opentui_raw_renderer_set_background_color"

external renderer_set_cursor_position :
  Native_token.Renderer.t -> int32 -> int32 -> bool -> int =
  "opentui_raw_renderer_set_cursor_position"

external renderer_set_cursor_color :
  Native_token.Renderer.t -> color -> int =
  "opentui_raw_renderer_set_cursor_color"

external renderer_set_cursor_style_options :
  Native_token.Renderer.t -> int option -> bool option -> color option ->
  int option -> int =
  "opentui_raw_renderer_set_cursor_style_options"

external renderer_cursor_state :
  Native_token.Renderer.t -> int * cursor_state =
  "opentui_raw_renderer_cursor_state"

external renderer_destroy : Native_token.Renderer.t -> unit =
  "opentui_raw_renderer_destroy"

external renderer_buffer :
  Native_token.Renderer.t -> bool -> int * Native_token.Buffer.t =
  "opentui_raw_renderer_buffer"

external renderer_render : Native_token.Renderer.t -> bool -> int =
  "opentui_raw_renderer_render"

external renderer_set_render_offset : Native_token.Renderer.t -> int32 -> int =
  "opentui_raw_renderer_set_render_offset"

external renderer_reset_split_scrollback :
  Native_token.Renderer.t -> int32 -> int32 -> int * int32 =
  "opentui_raw_renderer_reset_split_scrollback"

external renderer_sync_split_scrollback :
  Native_token.Renderer.t -> int32 -> int * int32 =
  "opentui_raw_renderer_sync_split_scrollback"

external renderer_get_split_output_offset :
  Native_token.Renderer.t -> int32 -> int * int32 =
  "opentui_raw_renderer_get_split_output_offset"

external renderer_set_pending_split_footer_transition :
  Native_token.Renderer.t ->
  int32 * int32 * int32 * int32 * int32 * int32 -> int =
  "opentui_raw_renderer_set_pending_split_footer_transition"

external renderer_clear_pending_split_footer_transition :
  Native_token.Renderer.t -> int =
  "opentui_raw_renderer_clear_pending_split_footer_transition"

external renderer_repaint_split_footer :
  Native_token.Renderer.t -> int32 -> bool -> int * int32 =
  "opentui_raw_renderer_repaint_split_footer"

external renderer_commit_split_footer_snapshot :
  Native_token.Renderer.t ->
  Native_token.Optimized_buffer.t ->
  int32 -> bool -> bool -> int32 -> bool -> bool -> bool -> int * int32 =
  "opentui_raw_renderer_commit_split_footer_snapshot_bytecode"
  "opentui_raw_renderer_commit_split_footer_snapshot"

external optimized_buffer_as_buffer :
  Native_token.Optimized_buffer.t -> Native_token.Buffer.t =
  "opentui_raw_optimized_buffer_as_buffer"

external renderer_add_to_hit_grid :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int32 -> int =
  "opentui_raw_renderer_add_to_hit_grid_bytecode"
  "opentui_raw_renderer_add_to_hit_grid"

external renderer_add_to_hit_grid_unchecked :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int32 -> unit =
  "opentui_raw_renderer_add_to_hit_grid_unchecked_bytecode"
  "opentui_raw_renderer_add_to_hit_grid_unchecked"

external renderer_clear_current_hit_grid : Native_token.Renderer.t -> int =
  "opentui_raw_renderer_clear_current_hit_grid"

external renderer_clear_current_hit_grid_unchecked :
  Native_token.Renderer.t -> unit =
  "opentui_raw_renderer_clear_current_hit_grid_unchecked"

external renderer_clear_next_hit_grid : Native_token.Renderer.t -> int =
  "opentui_raw_renderer_clear_next_hit_grid"

external renderer_clear_next_hit_grid_unchecked : Native_token.Renderer.t -> unit =
  "opentui_raw_renderer_clear_next_hit_grid_unchecked"

external renderer_hit_grid_push_scissor_rect :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int =
  "opentui_raw_renderer_hit_grid_push_scissor_rect"

external renderer_hit_grid_push_scissor_rect_unchecked :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> unit =
  "opentui_raw_renderer_hit_grid_push_scissor_rect_unchecked"

external renderer_hit_grid_pop_scissor_rect : Native_token.Renderer.t -> int =
  "opentui_raw_renderer_hit_grid_pop_scissor_rect"

external renderer_hit_grid_pop_scissor_rect_unchecked :
  Native_token.Renderer.t -> unit =
  "opentui_raw_renderer_hit_grid_pop_scissor_rect_unchecked"

external renderer_hit_grid_clear_scissor_rects : Native_token.Renderer.t -> int =
  "opentui_raw_renderer_hit_grid_clear_scissor_rects"

external renderer_hit_grid_clear_scissor_rects_unchecked :
  Native_token.Renderer.t -> unit =
  "opentui_raw_renderer_hit_grid_clear_scissor_rects_unchecked"

external renderer_add_to_current_hit_grid_clipped :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int32 -> int =
  "opentui_raw_renderer_add_to_current_hit_grid_clipped_bytecode"
  "opentui_raw_renderer_add_to_current_hit_grid_clipped"

external renderer_add_to_current_hit_grid_clipped_unchecked :
  Native_token.Renderer.t -> int32 -> int32 -> int32 -> int32 -> int32 -> unit =
  "opentui_raw_renderer_add_to_current_hit_grid_clipped_unchecked_bytecode"
  "opentui_raw_renderer_add_to_current_hit_grid_clipped_unchecked"

external renderer_check_hit :
  Native_token.Renderer.t -> int32 -> int32 -> int * int32 =
  "opentui_raw_renderer_check_hit"

external renderer_check_hit_unchecked :
  Native_token.Renderer.t -> int32 -> int32 -> int =
  "opentui_raw_renderer_check_hit_unchecked"

external renderer_get_hit_grid_dirty : Native_token.Renderer.t -> int * bool =
  "opentui_raw_renderer_get_hit_grid_dirty"

external renderer_get_hit_grid_dirty_unchecked :
  Native_token.Renderer.t -> bool =
  "opentui_raw_renderer_get_hit_grid_dirty_unchecked"

external buffer_dimensions : Native_token.Buffer.t -> int * int32 * int32 =
  "opentui_raw_buffer_dimensions"

external buffer_clear : Native_token.Buffer.t -> color -> int =
  "opentui_raw_buffer_clear"

external buffer_set_cell : Native_token.Buffer.t -> cell -> int =
  "opentui_raw_buffer_set_cell"

external buffer_draw_text : Native_token.Buffer.t -> text -> int =
  "opentui_raw_buffer_draw_text"

external buffer_set_cell_with_alpha_blending :
  Native_token.Buffer.t -> cell -> int =
  "opentui_raw_buffer_set_cell_with_alpha_blending"

external buffer_fill_rect :
  Native_token.Buffer.t -> int32 * int32 * int32 * int32 * color -> int =
  "opentui_raw_buffer_fill_rect"

external buffer_draw_grayscale_buffer :
  Native_token.Buffer.t -> grayscale_buffer -> int =
  "opentui_raw_buffer_draw_grayscale_buffer"

external buffer_draw_grayscale_buffer_supersampled :
  Native_token.Buffer.t -> grayscale_buffer -> int =
  "opentui_raw_buffer_draw_grayscale_buffer_supersampled"

external buffer_draw_box : Native_token.Buffer.t -> box -> int =
  "opentui_raw_buffer_draw_box"

external buffer_draw_text_buffer_view :
  Native_token.Buffer.t -> Native_token.Text_buffer_view.t -> int32 -> int32 -> int =
  "opentui_raw_buffer_draw_text_buffer_view"

external buffer_draw_frame_buffer :
  Native_token.Buffer.t ->
  (int32 * int32 * Native_token.Optimized_buffer.t * int32 * int32 * int32 * int32) -> int =
  "opentui_raw_buffer_draw_frame_buffer"

external buffer_draw_grid :
  Native_token.Buffer.t ->
  (int32 array * color * color * int32 array * int32 array * bool * bool) -> int =
  "opentui_raw_buffer_draw_grid"

external buffer_write_resolved_chars :
  Native_token.Buffer.t -> bytes -> bool -> int * int32 =
  "opentui_raw_buffer_write_resolved_chars"

external buffer_draw_image :
  Native_token.Buffer.t ->
  (int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 *
   int32 * Native_token.Image.t) -> int =
  "opentui_raw_buffer_draw_image"

external buffer_color_matrix :
  Native_token.Buffer.t -> floatarray -> floatarray -> float -> int -> int =
  "opentui_raw_buffer_color_matrix"

external buffer_color_matrix_uniform :
  Native_token.Buffer.t -> floatarray -> float -> int -> int =
  "opentui_raw_buffer_color_matrix_uniform"

external buffer_push_scissor_rect :
  Native_token.Buffer.t -> int32 * int32 * int32 * int32 -> int =
  "opentui_raw_buffer_push_scissor_rect"

external buffer_pop_scissor_rect : Native_token.Buffer.t -> int =
  "opentui_raw_buffer_pop_scissor_rect"

external buffer_clear_scissor_rects : Native_token.Buffer.t -> int =
  "opentui_raw_buffer_clear_scissor_rects"

external buffer_push_opacity : Native_token.Buffer.t -> float -> int =
  "opentui_raw_buffer_push_opacity"

external buffer_pop_opacity : Native_token.Buffer.t -> int =
  "opentui_raw_buffer_pop_opacity"

external buffer_get_current_opacity : Native_token.Buffer.t -> float =
  "opentui_raw_buffer_get_current_opacity"

external buffer_clear_opacity : Native_token.Buffer.t -> int =
  "opentui_raw_buffer_clear_opacity"

type buffer_snapshot = int32 array * int32 array * int32 array * int32 array

external buffer_snapshot : Native_token.Buffer.t ->
  int * buffer_snapshot = "opentui_raw_buffer_snapshot"

external buffer_restore :
  Native_token.Buffer.t -> buffer_snapshot -> int =
  "opentui_raw_buffer_restore"

external image_info : bytes -> int * image_info = "opentui_raw_image_info"

external image_decode : bytes -> int * Native_token.Image.t =
  "opentui_raw_image_decode"

external image_create_from_rgba :
  bytes -> int32 -> int32 -> int32 -> int * Native_token.Image.t =
  "opentui_raw_image_create_from_rgba"

external image_destroy : Native_token.Image.t -> unit =
  "opentui_raw_image_destroy"

external image_retain : Native_token.Image.t -> int * Native_token.Image.t =
  "opentui_raw_image_retain"

external image_get_info : Native_token.Image.t -> int * image_info =
  "opentui_raw_image_get_info"

external image_materialize : Native_token.Image.t -> int =
  "opentui_raw_image_materialize"

external image_ensure_encoded_png : Native_token.Image.t -> int =
  "opentui_raw_image_ensure_encoded_png"

external image_clone : Native_token.Image.t -> int * Native_token.Image.t =
  "opentui_raw_image_clone"

external image_copy_pixels :
  Native_token.Image.t -> bytes -> int32 -> bool -> int =
  "opentui_raw_image_copy_pixels"

external image_resize :
  Native_token.Image.t -> (int32 * int32 * int32) -> int * Native_token.Image.t =
  "opentui_raw_image_resize"

external image_extract :
  Native_token.Image.t -> (int32 * int32 * int32 * int32) ->
  int * Native_token.Image.t =
  "opentui_raw_image_extract"

external image_extend :
  Native_token.Image.t -> (int32 * int32 * int32 * int32 * bytes) ->
  int * Native_token.Image.t =
  "opentui_raw_image_extend"

external image_transform :
  Native_token.Image.t -> int32 -> int * Native_token.Image.t =
  "opentui_raw_image_transform"

external image_composite :
  Native_token.Image.t ->
  Native_token.Image.t -> (int32 * int32 * int32 * int32) ->
  int * Native_token.Image.t =
  "opentui_raw_image_composite"

module Optimized_buffer = struct
  external create :
    width:int32 -> height:int32 -> respect_alpha:bool -> width_method:int32 ->
    id:string -> int * Native_token.Optimized_buffer.t =
    "opentui_raw_optimized_buffer_create"

  external destroy : Native_token.Optimized_buffer.t -> unit =
    "opentui_raw_optimized_buffer_destroy"

  external dimensions : Native_token.Optimized_buffer.t -> int * int32 * int32 =
    "opentui_raw_optimized_buffer_dimensions"

  external clear : Native_token.Optimized_buffer.t -> color -> int =
    "opentui_raw_optimized_buffer_clear"

  external set_cell : Native_token.Optimized_buffer.t -> cell -> int =
    "opentui_raw_optimized_buffer_set_cell"

  external set_cell_with_alpha_blending :
    Native_token.Optimized_buffer.t -> cell -> int =
    "opentui_raw_optimized_buffer_set_cell_with_alpha_blending"

  external draw_text : Native_token.Optimized_buffer.t -> text -> int =
    "opentui_raw_optimized_buffer_draw_text"

  external draw_text_buffer_view :
    Native_token.Optimized_buffer.t -> Native_token.Text_buffer_view.t -> int32 -> int32 -> int =
    "opentui_raw_buffer_draw_text_buffer_view"

  external fill_rect :
    Native_token.Optimized_buffer.t -> int32 * int32 * int32 * int32 * color -> int =
    "opentui_raw_optimized_buffer_fill_rect"

  external draw_grayscale_buffer :
    Native_token.Optimized_buffer.t -> grayscale_buffer -> int =
    "opentui_raw_optimized_buffer_draw_grayscale_buffer"

  external draw_grayscale_buffer_supersampled :
    Native_token.Optimized_buffer.t -> grayscale_buffer -> int =
    "opentui_raw_optimized_buffer_draw_grayscale_buffer_supersampled"

  external draw_frame_buffer :
    Native_token.Optimized_buffer.t ->
    (int32 * int32 * Native_token.Optimized_buffer.t * int32 * int32 * int32 * int32) -> int =
    "opentui_raw_optimized_buffer_draw_frame_buffer"

  external resize : Native_token.Optimized_buffer.t -> int32 -> int32 -> int =
    "opentui_raw_optimized_buffer_resize"

  external draw_grid :
    Native_token.Optimized_buffer.t ->
    (int32 array * color * color * int32 array * int32 array * bool * bool) -> int =
    "opentui_raw_optimized_buffer_draw_grid"

  external draw_image :
    Native_token.Optimized_buffer.t ->
    (int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 * int32 *
     int32 * Native_token.Image.t) -> int =
    "opentui_raw_buffer_draw_image"

  external snapshot : Native_token.Optimized_buffer.t -> int * buffer_snapshot =
    "opentui_raw_buffer_snapshot"

  external restore : Native_token.Optimized_buffer.t -> buffer_snapshot -> int =
    "opentui_raw_buffer_restore"
end

external event_sink_create : unit -> int * Native_token.Event_sink.t =
  "opentui_raw_event_sink_create"

external event_sink_destroy : Native_token.Event_sink.t -> unit =
  "opentui_raw_event_sink_destroy"

external event_sink_poll :
  Native_token.Event_sink.t -> int * (bytes * bytes) option =
  "opentui_raw_event_sink_poll"

external yoga_node_create : unit -> int * Native_token.Yoga_node.t =
  "opentui_raw_yoga_node_create"

external yoga_node_free : Native_token.Yoga_node.t -> int =
  "opentui_raw_yoga_node_free"

external yoga_node_free_recursive : Native_token.Yoga_node.t -> int =
  "opentui_raw_yoga_node_free_recursive"

external yoga_node_insert_child :
  Native_token.Yoga_node.t -> Native_token.Yoga_node.t -> int32 -> int =
  "opentui_raw_yoga_node_insert_child"

external yoga_node_remove_child :
  Native_token.Yoga_node.t -> Native_token.Yoga_node.t -> int =
  "opentui_raw_yoga_node_remove_child"

external yoga_node_move_child :
  Native_token.Yoga_node.t -> Native_token.Yoga_node.t -> int32 -> int =
  "opentui_raw_yoga_node_move_child"

external yoga_node_child_count : Native_token.Yoga_node.t -> int * int32 =
  "opentui_raw_yoga_node_child_count"

external yoga_node_calculate :
  Native_token.Yoga_node.t -> float -> float -> int32 -> int =
  "opentui_raw_yoga_node_calculate"

external yoga_node_is_dirty : Native_token.Yoga_node.t -> int * bool =
  "opentui_raw_yoga_node_is_dirty"

external yoga_node_mark_dirty : Native_token.Yoga_node.t -> int =
  "opentui_raw_yoga_node_mark_dirty"

external yoga_node_has_new_layout : Native_token.Yoga_node.t -> int * bool =
  "opentui_raw_yoga_node_has_new_layout"

external yoga_node_mark_layout_seen : Native_token.Yoga_node.t -> int =
  "opentui_raw_yoga_node_mark_layout_seen"

external yoga_node_style_set_value :
  Native_token.Yoga_node.t -> int32 -> int32 -> int32 -> float -> int =
  "opentui_raw_yoga_node_style_set_value"

external yoga_node_style_set_enum :
  Native_token.Yoga_node.t -> int32 -> int32 -> int =
  "opentui_raw_yoga_node_style_set_enum"

external yoga_node_style_set_float :
  Native_token.Yoga_node.t -> int32 -> float -> int =
  "opentui_raw_yoga_node_style_set_float"

external yoga_node_style_set_border :
  Native_token.Yoga_node.t -> int32 -> float -> int =
  "opentui_raw_yoga_node_style_set_border"

external yoga_node_set_measure_func :
  Native_token.Yoga_node.t -> bool -> unit =
  "opentui_raw_yoga_node_set_measure_func"

external yoga_node_unset_measure_func :
  Native_token.Yoga_node.t -> unit =
  "opentui_raw_yoga_node_unset_measure_func"

external yoga_node_has_measure_func :
  Native_token.Yoga_node.t -> bool =
  "opentui_raw_yoga_node_has_measure_func"

external yoga_set_measure_callback :
  (Nativeint.t * float * int32 * float * int32 -> float * float) -> unit =
  "opentui_raw_yoga_set_measure_callback"

external yoga_clear_measure_callback : unit -> unit =
  "opentui_raw_yoga_clear_measure_callback"

external yoga_node_pointer :
  Native_token.Yoga_node.t -> Nativeint.t =
  "opentui_raw_yoga_node_pointer"

external yoga_node_layout :
  Native_token.Yoga_node.t -> int * yoga_layout option =
  "opentui_raw_yoga_node_layout"

external renderer_capabilities :
  Native_token.Renderer.t -> int * capabilities option =
  "opentui_raw_renderer_capabilities"

external process_capability_response :
  Native_token.Renderer.t -> string -> int =
  "opentui_raw_process_capability_response"

external span_feed_create :
  span_feed_options -> int * Native_token.Span_feed.t =
  "opentui_raw_span_feed_create"

external span_feed_close : Native_token.Span_feed.t -> int =
  "opentui_raw_span_feed_close"

external span_feed_write : Native_token.Span_feed.t -> bytes -> int =
  "opentui_raw_span_feed_write"

external span_feed_commit : Native_token.Span_feed.t -> int =
  "opentui_raw_span_feed_commit"

external span_feed_reserve :
  Native_token.Span_feed.t -> int32 ->
  int * (Native_token.Reservation.t * int32 * bytes) option =
  "opentui_raw_span_feed_reserve"

external span_feed_reservation_commit :
  Native_token.Reservation.t -> bytes -> int32 -> int =
  "opentui_raw_span_feed_reservation_commit"

external span_feed_reservation_cancel : Native_token.Reservation.t -> int =
  "opentui_raw_span_feed_reservation_cancel"

external span_feed_stats :
  Native_token.Span_feed.t -> int * span_feed_stats option =
  "opentui_raw_span_feed_stats"

external span_feed_drain :
  Native_token.Span_feed.t -> int * (bytes * Native_token.Span.t) option =
  "opentui_raw_span_feed_drain"

external span_release : Native_token.Span.t -> int =
  "opentui_raw_span_release"

external text_buffer_create : int32 -> int * Native_token.Text_buffer.t =
  "opentui_raw_text_buffer_create"

external text_buffer_destroy : Native_token.Text_buffer.t -> unit =
  "opentui_raw_text_buffer_destroy"

external text_buffer_clear : Native_token.Text_buffer.t -> int =
  "opentui_raw_text_buffer_clear"

external text_buffer_reset : Native_token.Text_buffer.t -> int =
  "opentui_raw_text_buffer_reset"

external text_buffer_append :
  Native_token.Text_buffer.t ->
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t -> int =
  "opentui_raw_text_buffer_append"

external text_buffer_register_mem_buffer :
  Native_token.Text_buffer.t ->
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t ->
  bool -> int * int32 =
  "opentui_raw_text_buffer_register_mem_buffer"

external text_buffer_replace_mem_buffer :
  Native_token.Text_buffer.t -> int32 ->
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t ->
  bool -> int =
  "opentui_raw_text_buffer_replace_mem_buffer"

external text_buffer_set_text_from_mem :
  Native_token.Text_buffer.t -> int32 -> int32 -> int =
  "opentui_raw_text_buffer_set_text_from_mem"

external text_buffer_length : Native_token.Text_buffer.t -> int * int32 =
  "opentui_raw_text_buffer_length"

external text_buffer_byte_size : Native_token.Text_buffer.t -> int * int32 =
  "opentui_raw_text_buffer_byte_size"

external text_buffer_line_count : Native_token.Text_buffer.t -> int * int32 =
  "opentui_raw_text_buffer_line_count"

external text_buffer_load_file : Native_token.Text_buffer.t -> string -> int =
  "opentui_raw_text_buffer_load_file"

external text_buffer_get_tab_width : Native_token.Text_buffer.t -> int * int32 =
  "opentui_raw_text_buffer_get_tab_width"

external text_buffer_set_tab_width : Native_token.Text_buffer.t -> int32 -> int =
  "opentui_raw_text_buffer_set_tab_width"

type styled_chunk = string * color option * color option * int32 * string option

external text_buffer_set_styled_text :
  Native_token.Text_buffer.t -> styled_chunk list -> int =
  "opentui_raw_text_buffer_set_styled_text"

external text_buffer_clear_all_highlights : Native_token.Text_buffer.t -> int =
  "opentui_raw_text_buffer_clear_all_highlights"

type highlight = int32 * int32 * int32 * int * int

external text_buffer_add_highlight_by_char_range :
  Native_token.Text_buffer.t -> highlight -> int =
  "opentui_raw_text_buffer_add_highlight_by_char_range"

external text_buffer_add_highlight :
  Native_token.Text_buffer.t -> int32 -> highlight -> int =
  "opentui_raw_text_buffer_add_highlight"

external text_buffer_remove_highlights_by_ref :
  Native_token.Text_buffer.t -> int -> int =
  "opentui_raw_text_buffer_remove_highlights_by_ref"

external text_buffer_clear_line_highlights :
  Native_token.Text_buffer.t -> int32 -> int =
  "opentui_raw_text_buffer_clear_line_highlights"

external text_buffer_set_default_fg :
  Native_token.Text_buffer.t -> color option -> int =
  "opentui_raw_text_buffer_set_default_fg"

external text_buffer_set_default_bg :
  Native_token.Text_buffer.t -> color option -> int =
  "opentui_raw_text_buffer_set_default_bg"

external text_buffer_set_default_attributes :
  Native_token.Text_buffer.t -> int32 option -> int =
  "opentui_raw_text_buffer_set_default_attributes"

external text_buffer_reset_defaults : Native_token.Text_buffer.t -> int =
  "opentui_raw_text_buffer_reset_defaults"

external text_buffer_set_syntax_style :
  Native_token.Text_buffer.t -> Native_token.Syntax_style.t option -> int =
  "opentui_raw_text_buffer_set_syntax_style"

external syntax_style_create : unit -> int * Native_token.Syntax_style.t =
  "opentui_raw_syntax_style_create"

external syntax_style_destroy : Native_token.Syntax_style.t -> unit =
  "opentui_raw_syntax_style_destroy"

external syntax_style_register :
  Native_token.Syntax_style.t -> string -> color option -> color option -> int32 -> int * int32 =
  "opentui_raw_syntax_style_register"

external syntax_style_resolve :
  Native_token.Syntax_style.t -> string -> int * int32 =
  "opentui_raw_syntax_style_resolve"

external syntax_style_count : Native_token.Syntax_style.t -> int * int32 =
  "opentui_raw_syntax_style_count"

external text_buffer_view_create :
  Native_token.Text_buffer.t -> int * Native_token.Text_buffer_view.t =
  "opentui_raw_text_buffer_view_create"

external text_buffer_view_destroy : Native_token.Text_buffer_view.t -> unit =
  "opentui_raw_text_buffer_view_destroy"

external text_buffer_view_set_wrap_width :
  Native_token.Text_buffer_view.t -> int32 -> int =
  "opentui_raw_text_buffer_view_set_wrap_width"

external text_buffer_view_set_wrap_mode :
  Native_token.Text_buffer_view.t -> int32 -> int =
  "opentui_raw_text_buffer_view_set_wrap_mode"

external text_buffer_view_set_first_line_offset :
  Native_token.Text_buffer_view.t -> int32 -> int =
  "opentui_raw_text_buffer_view_set_first_line_offset"

external text_buffer_view_set_selection :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> Color.t option ->
  Color.t option -> int =
  "opentui_raw_text_buffer_view_set_selection"

external text_buffer_view_update_selection :
  Native_token.Text_buffer_view.t -> int32 -> Color.t option -> Color.t option ->
  int =
  "opentui_raw_text_buffer_view_update_selection"

external text_buffer_view_reset_selection : Native_token.Text_buffer_view.t -> int =
  "opentui_raw_text_buffer_view_reset_selection"

external text_buffer_view_get_selection_info :
  Native_token.Text_buffer_view.t -> int64 =
  "opentui_raw_text_buffer_view_get_selection_info"

external text_buffer_view_set_local_selection :
  Native_token.Text_buffer_view.t ->
  (int32 * int32 * int32 * int32 * Color.t option * Color.t option) ->
  int * bool =
  "opentui_raw_text_buffer_view_set_local_selection"

external text_buffer_view_update_local_selection :
  Native_token.Text_buffer_view.t ->
  (int32 * int32 * int32 * int32 * Color.t option * Color.t option) ->
  int * bool =
  "opentui_raw_text_buffer_view_update_local_selection"

external text_buffer_view_reset_local_selection :
  Native_token.Text_buffer_view.t -> int =
  "opentui_raw_text_buffer_view_reset_local_selection"

external text_buffer_view_get_selected_text :
  Native_token.Text_buffer_view.t -> bytes -> int32 -> int * int32 =
  "opentui_raw_text_buffer_view_get_selected_text"

external text_buffer_view_set_viewport_size :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> int =
  "opentui_raw_text_buffer_view_set_viewport_size"

external text_buffer_view_set_viewport :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> int32 -> int32 -> int =
  "opentui_raw_text_buffer_view_set_viewport"

external text_buffer_view_get_virtual_line_count :
  Native_token.Text_buffer_view.t -> int * int32 =
  "opentui_raw_text_buffer_view_get_virtual_line_count"

external text_buffer_view_set_tab_indicator :
  Native_token.Text_buffer_view.t -> int32 -> int =
  "opentui_raw_text_buffer_view_set_tab_indicator"

external text_buffer_view_set_tab_indicator_color :
  Native_token.Text_buffer_view.t -> Color.t -> int =
  "opentui_raw_text_buffer_view_set_tab_indicator_color"

external text_buffer_view_set_truncate :
  Native_token.Text_buffer_view.t -> bool -> int =
  "opentui_raw_text_buffer_view_set_truncate"

external text_buffer_view_measure_for_dimensions :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> int * int32 * int32 =
  "opentui_raw_text_buffer_view_measure_for_dimensions"

external text_buffer_view_get_line_info :
  Native_token.Text_buffer_view.t ->
  int * int32 array * int32 array * int32 array * int32 array * int32 =
  "opentui_raw_text_buffer_view_get_line_info"

external text_buffer_view_get_logical_line_info :
  Native_token.Text_buffer_view.t ->
  int * int32 array * int32 array * int32 array * int32 array * int32 =
  "opentui_raw_text_buffer_view_get_logical_line_info"

external native_renderable_create :
  unit -> int * Native_token.Native_renderable.t =
  "opentui_raw_native_renderable_create"

external native_renderable_destroy :
  Native_token.Native_renderable.t -> unit =
  "opentui_raw_native_renderable_destroy"

external native_renderable_attach_yoga_node :
  Native_token.Native_renderable.t -> Native_token.Yoga_node.t -> int =
  "opentui_raw_native_renderable_attach_yoga_node"

external yoga_node_claim_native_renderable :
  Native_token.Yoga_node.t -> int =
  "opentui_raw_yoga_node_claim_native_renderable"

external yoga_node_release_native_renderable :
  Native_token.Yoga_node.t -> int =
  "opentui_raw_yoga_node_release_native_renderable"

external yoga_node_set_native_measure_attached :
  Native_token.Yoga_node.t -> bool -> int =
  "opentui_raw_yoga_node_set_native_measure_attached"

external native_renderable_set_measure_target :
  Native_token.Native_renderable.t -> int32 -> Native_token.Text_buffer_view.t -> int =
  "opentui_raw_native_renderable_set_measure_target"

external native_renderable_clear_measure_target :
  Native_token.Native_renderable.t -> int =
  "opentui_raw_native_renderable_clear_measure_target"
