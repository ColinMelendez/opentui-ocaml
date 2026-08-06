open Windtrap

let () =
  run "opentui-raw"
    [
      test "handles round-trip through the ABI representation" (fun () ->
          let expected = 42l in
          let actual =
            expected |> Opentui_raw.Handle.of_int32
            |> Opentui_raw.Handle.to_int32 |> Int32.to_int
          in
          equal int 42 actual);
    ]
