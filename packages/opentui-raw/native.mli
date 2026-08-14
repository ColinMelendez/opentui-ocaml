type color = int * int * int * int
type cell = int32 * int32 * int32 * color * color * int32
type text = string * int32 * int32 * color * color * int32
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

val renderer_create : int32 -> int32 -> int * Native_token.Renderer.t
val renderer_resize : Native_token.Renderer.t -> int32 -> int32 -> int
val renderer_destroy : Native_token.Renderer.t -> unit
val renderer_buffer :
  Native_token.Renderer.t -> bool -> int * Native_token.Buffer.t
val renderer_render : Native_token.Renderer.t -> bool -> int
val buffer_dimensions : Native_token.Buffer.t -> int * int32 * int32
val buffer_clear : Native_token.Buffer.t -> color -> int
val buffer_set_cell : Native_token.Buffer.t -> cell -> int
val buffer_draw_text : Native_token.Buffer.t -> text -> int
val buffer_draw_box : Native_token.Buffer.t -> box -> int
val buffer_draw_text_buffer_view :
  Native_token.Buffer.t -> Native_token.Text_buffer_view.t -> int32 -> int32 -> int
val buffer_write_resolved_chars :
  Native_token.Buffer.t -> bytes -> bool -> int * int32
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
val text_buffer_view_create :
  Native_token.Text_buffer.t -> int * Native_token.Text_buffer_view.t
val text_buffer_view_destroy : Native_token.Text_buffer_view.t -> unit
val text_buffer_view_set_wrap_width :
  Native_token.Text_buffer_view.t -> int32 -> int
val text_buffer_view_set_wrap_mode :
  Native_token.Text_buffer_view.t -> int32 -> int
val text_buffer_view_set_first_line_offset :
  Native_token.Text_buffer_view.t -> int32 -> int
val text_buffer_view_measure_for_dimensions :
  Native_token.Text_buffer_view.t -> int32 -> int32 -> int * int32 * int32
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
