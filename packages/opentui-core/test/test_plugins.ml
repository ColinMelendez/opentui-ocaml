open Windtrap

module Core = Opentui_core
module Plugin = Core.Plugin
module Slot = Core.Slot

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
  run "opentui-core-plugins"
    [
      test "typed plugin installation and uninstallation are transactional" (fun () ->
          let renderer = expect_core (Core.Renderer.create ~width:2l ~height:1l) in
          let host = Plugin.Host.create ~renderer ~reporter:Plugin.Reporter.ignore in
          let slot_id = expect_id "status" in
          let slot, sink = expect_failure (Slot.create ~host ~id:slot_id) in
          ignore slot;
          let plugin_id = expect_id "status-plugin" in
          let released = ref 0 in
          let definition =
            expect_failure
              (Plugin.define ~id:plugin_id ~order:0
                 ~install:(fun scope () ->
                   ignore
                     (expect_failure
                        (Plugin.Scope.on_release scope (fun () ->
                             incr released;
                             Ok ())));
                   Plugin.Scope.contribute scope sink ~render:(fun () -> Ok None)))
          in
          let instance = expect_host (Plugin.Host.install host ~capabilities:() definition) in
          equal int 0 !released;
          ignore (expect_failure (Plugin.Instance.set_order instance 2));
          ignore (expect_host (Plugin.Instance.uninstall instance));
          equal int 1 !released;
          ignore (expect_host (Plugin.Instance.uninstall instance));
          equal int 1 !released;
          ignore (expect_host (Plugin.Host.close host));
          Core.Renderer.destroy renderer);
      test "duplicate plugin identifiers are rejected before setup" (fun () ->
          let renderer = expect_core (Core.Renderer.create ~width:1l ~height:1l) in
          let host = Plugin.Host.create ~renderer ~reporter:Plugin.Reporter.ignore in
          let id = expect_id "same-plugin" in
          let definition = expect_failure (Plugin.define ~id ~order:0 ~install:(fun _ () -> Ok ())) in
          ignore (expect_host (Plugin.Host.install host ~capabilities:() definition));
          (match Plugin.Host.install host ~capabilities:() definition with
          | Error (failure, _) ->
              (match failure.Core.Plugin_failure.cause with
              | Core.Plugin_failure.Duplicate_plugin _ -> ()
              | _ -> fail "duplicate identifier returned the wrong failure")
          | Ok instance ->
              ignore (Plugin.Instance.uninstall instance);
              fail "duplicate plugin identifier was installed");
          ignore (expect_host (Plugin.Host.close host));
          Core.Renderer.destroy renderer);
    ]
