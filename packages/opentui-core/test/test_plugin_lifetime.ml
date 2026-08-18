open Windtrap

module Core = Opentui_core
module Plugin = Core.Plugin

let expect_core result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_failure result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Plugin_failure.message error)

let expect_host result =
  match result with
  | Ok value -> value
  | Error (first, _) -> fail (Core.Plugin_failure.message first)

let expect_id value =
  match Core.Plugin_id.create value with
  | Ok id -> id
  | Error error -> fail (Core.Plugin_id.error_message error)

let () =
  run "opentui-core-plugin-lifetime"
    [
      test "renderer destruction closes attached plugin hosts" (fun () ->
          let renderer =
            expect_core (Core.Renderer.create ~output:Core.Renderer.Output.Memory ~width:2l ~height:1l ())
          in
          let host =
            Plugin.Host.create ~renderer ~reporter:Plugin.Reporter.ignore
          in
          let released = ref 0 in
          let definition =
            expect_failure
              (Plugin.define ~id:(expect_id "lifetime-plugin") ~order:0
                 ~install:(fun scope () ->
                   ignore
                     (expect_failure
                        (Plugin.Scope.on_release scope (fun () ->
                             incr released;
                             Ok ())));
                   Ok ()))
          in
          ignore
            (expect_host
               (Plugin.Host.install host ~capabilities:() definition));
          Core.Renderer.destroy renderer;
          equal int 1 !released;
          ignore (expect_host (Plugin.Host.close host));
          equal int 1 !released);
    ]
