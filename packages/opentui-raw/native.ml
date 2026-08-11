type color = int * int * int * int
type cell = int32 * int32 * int32 * color * color * int32
type text = string * int32 * int32 * color * color * int32
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

external renderer_create : int32 -> int32 -> int * Native_token.Renderer.t =
  "opentui_raw_renderer_create"

external renderer_resize :
  Native_token.Renderer.t -> int32 -> int32 -> int =
  "opentui_raw_renderer_resize"

external renderer_destroy : Native_token.Renderer.t -> unit =
  "opentui_raw_renderer_destroy"

external renderer_buffer :
  Native_token.Renderer.t -> bool -> int * Native_token.Buffer.t =
  "opentui_raw_renderer_buffer"

external renderer_render : Native_token.Renderer.t -> bool -> int =
  "opentui_raw_renderer_render"

external buffer_dimensions : Native_token.Buffer.t -> int * int32 * int32 =
  "opentui_raw_buffer_dimensions"

external buffer_clear : Native_token.Buffer.t -> color -> int =
  "opentui_raw_buffer_clear"

external buffer_set_cell : Native_token.Buffer.t -> cell -> int =
  "opentui_raw_buffer_set_cell"

external buffer_draw_text : Native_token.Buffer.t -> text -> int =
  "opentui_raw_buffer_draw_text"

external buffer_write_resolved_chars :
  Native_token.Buffer.t -> bytes -> bool -> int * int32 =
  "opentui_raw_buffer_write_resolved_chars"

external event_sink_create : unit -> int * Native_token.Event_sink.t =
  "opentui_raw_event_sink_create"

external event_sink_destroy : Native_token.Event_sink.t -> unit =
  "opentui_raw_event_sink_destroy"

external event_sink_poll :
  Native_token.Event_sink.t -> int * (bytes * bytes) option =
  "opentui_raw_event_sink_poll"

external yoga_create : unit -> int * Native_token.Yoga_tree.t =
  "opentui_raw_yoga_create"

external yoga_destroy : Native_token.Yoga_tree.t -> unit =
  "opentui_raw_yoga_destroy"

external yoga_root : Native_token.Yoga_tree.t -> int * Native_token.Yoga_node.t =
  "opentui_raw_yoga_root"

external yoga_add_child :
  Native_token.Yoga_tree.t -> Native_token.Yoga_node.t -> int * Native_token.Yoga_node.t =
  "opentui_raw_yoga_add_child"

external yoga_remove_child :
  Native_token.Yoga_tree.t ->
  Native_token.Yoga_node.t ->
  Native_token.Yoga_node.t -> int =
  "opentui_raw_yoga_remove_child"

external yoga_move_child :
  Native_token.Yoga_tree.t ->
  Native_token.Yoga_node.t ->
  Native_token.Yoga_node.t ->
  int32 -> int =
  "opentui_raw_yoga_move_child"

external yoga_node_set_width : Native_token.Yoga_node.t -> float -> int =
  "opentui_raw_yoga_node_set_width"

external yoga_node_set_height : Native_token.Yoga_node.t -> float -> int =
  "opentui_raw_yoga_node_set_height"

external yoga_calculate :
  Native_token.Yoga_tree.t -> float -> float -> int -> int =
  "opentui_raw_yoga_calculate"

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
