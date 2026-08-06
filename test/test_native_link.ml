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
    ]
