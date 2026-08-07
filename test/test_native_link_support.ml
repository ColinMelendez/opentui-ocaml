external native_symbol_smoke : unit -> bool = "opentui_test_native_symbol_smoke"

external memory_renderer_round_trip : unit -> bool = "opentui_test_memory_renderer_round_trip"

external event_callback_copy : unit -> bool = "opentui_test_event_callback_copy"

external buffer_update_baseline : unit -> int * int * int64 * int64 * bool =
  "opentui_test_buffer_update_baseline"
