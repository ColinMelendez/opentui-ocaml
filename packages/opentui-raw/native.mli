type color = int * int * int * int
type cell = int32 * int32 * int32 * color * color * int32
type text = string * int32 * int32 * color * color * int32

val renderer_create : int32 -> int32 -> int * Native_token.Renderer.t
val renderer_destroy : Native_token.Renderer.t -> unit
val renderer_buffer :
  Native_token.Renderer.t -> bool -> int * Native_token.Buffer.t
val buffer_dimensions : Native_token.Buffer.t -> int * int32 * int32
val buffer_clear : Native_token.Buffer.t -> color -> int
val buffer_set_cell : Native_token.Buffer.t -> cell -> int
val buffer_draw_text : Native_token.Buffer.t -> text -> int
val buffer_write_resolved_chars :
  Native_token.Buffer.t -> bytes -> bool -> int * int32
val event_sink_create : unit -> int * Native_token.Event_sink.t
val event_sink_destroy : Native_token.Event_sink.t -> unit
val event_sink_poll :
  Native_token.Event_sink.t -> int * (bytes * bytes) option
