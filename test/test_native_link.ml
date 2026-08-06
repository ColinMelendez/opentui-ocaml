open Windtrap

let () =
  run "opentui-native-link"
    [
      test "links the pinned native symbols" (fun () ->
          equal bool true (Test_native_link_support.native_symbol_smoke ()));
    ]
