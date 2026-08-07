type color = int * int * int * int
type cell = int32 * int32 * int32 * color * color * int32
type text = string * int32 * int32 * color * color * int32

external renderer_create : int32 -> int32 -> int * Native_token.Renderer.t =
  "opentui_raw_renderer_create"

external renderer_destroy : Native_token.Renderer.t -> unit =
  "opentui_raw_renderer_destroy"

external renderer_buffer :
  Native_token.Renderer.t -> bool -> int * Native_token.Buffer.t =
  "opentui_raw_renderer_buffer"

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
