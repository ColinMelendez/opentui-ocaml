open Windtrap

let () =
  run "opentui-native-link"
    [
      test "links the pinned native symbols" (fun () ->
          equal bool true (Test_native_link_support.native_symbol_smoke ()));
      test "runs the memory renderer and buffer ownership round trip" (fun () ->
          equal bool true (Test_native_link_support.memory_renderer_round_trip ()));
      test "copies synchronous event callback payloads" (fun () ->
          equal bool true (Test_native_link_support.event_callback_copy ()));
      test "records the repeated native buffer update baseline" (fun () ->
          let set_cell_calls, write_calls, active_before, active_after, output_valid =
            Test_native_link_support.buffer_update_baseline ()
          in
          equal int 1024 set_cell_calls;
          equal int 1 write_calls;
          equal int64 active_before active_after;
          equal bool true output_valid);
    ]
