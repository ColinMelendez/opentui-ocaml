open Windtrap

let () =
  run "opentui-native-link"
    [
      test "links the pinned native symbols" (fun () ->
          equal bool true (Test_native_link_support.native_symbol_smoke ()));
      test "runs the memory renderer and buffer ownership round trip" (fun () ->
          equal bool true (Test_native_link_support.memory_renderer_round_trip ()));
    ]
