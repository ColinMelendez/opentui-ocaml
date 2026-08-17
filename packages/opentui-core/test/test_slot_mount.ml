open Windtrap

module Core = Opentui_core
module Box = Core.Renderables.Box
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

let expect_mount result =
  match result with
  | Ok value -> value
  | Error failure -> fail (Core.Plugin_failure.message failure)

let expect_mount_unit result =
  match result with
  | Ok () -> ()
  | Error (first :: _) -> fail (Core.Plugin_failure.message first)
  | Error [] -> fail "slot mount returned an empty failure list"

let expect_id value =
  match Core.Plugin_id.create value with
  | Ok id -> id
  | Error error -> fail (Core.Plugin_id.error_message error)

let assert_child_ids renderable expected =
  let rec compare actual expected =
    match actual, expected with
    | [], [] -> ()
    | actual :: actual_rest, expected :: expected_rest ->
        equal string expected (Core.Renderable.id actual);
        compare actual_rest expected_rest
    | [], _ :: _ | _ :: _, [] -> fail "unexpected slot mount child count"
  in
  compare (Core.Renderable.children renderable) expected

type produced = {
  renderable : Core.Renderable.t;
  view : Core.Slot_view.t;
  deactivated : int ref;
}

let make_view context ~id =
  let box = expect_core (Box.create context ~id ()) in
  let renderable = Box.as_renderable box in
  let deactivated = ref 0 in
  let view =
    Core.Slot_view.create
      ~on_deactivate:(fun () ->
        incr deactivated;
        Ok ())
      renderable
  in
  { renderable; view; deactivated }

let latest views =
  match !views with
  | latest :: _ -> latest
  | [] -> fail "plugin did not produce a view"

let install_contributor ~host ~sink ~id ~order ~render =
  let definition =
    expect_failure
      (Plugin.define ~id:(expect_id id) ~order
         ~install:(fun scope () ->
           ignore (expect_failure (Plugin.Scope.contribute scope sink ~render));
           Ok ()))
  in
  expect_host (Plugin.Host.install host ~capabilities:() definition)

let attach_mount renderer mount =
  ignore
    (expect_core
       (Core.Layout_children.add (Core.Renderer.children renderer)
          (Core.Slot_mount.renderable mount)))

let test_modes_and_fallback () =
  let renderer = expect_core (Core.Renderer.create ~width:20l ~height:6l) in
  let context = Core.Renderer.context renderer in
  let host = Plugin.Host.create ~renderer ~reporter:Plugin.Reporter.ignore in
  let slot_id = expect_id "mode-slot" in
  let slot, sink = expect_failure (Core.Slot.create ~host ~id:slot_id) in
  let first_views = ref [] in
  let second_views = ref [] in
  let fallback_view = ref None in
  let render_first props =
    let produced = make_view context ~id:("first-" ^ string_of_int props) in
    first_views := produced :: !first_views;
    Ok (Some produced.view)
  in
  let render_second props =
    let produced = make_view context ~id:("second-" ^ string_of_int props) in
    second_views := produced :: !second_views;
    Ok (Some produced.view)
  in
  ignore
    (install_contributor ~host ~sink ~id:"first-mode-plugin" ~order:0
       ~render:render_first);
  ignore
    (install_contributor ~host ~sink ~id:"second-mode-plugin" ~order:1
       ~render:render_second);
  let fallback () =
    let produced = make_view context ~id:"fallback" in
    fallback_view := Some produced;
    Ok [ produced.view ]
  in
  let mount =
    expect_mount
      (Core.Slot_mount.create ~renderer ~slot ~props:1
         ~mode:Core.Slot_mount.Append ~fallback ())
  in
  attach_mount renderer mount;
  equal int 1
    (Core.Renderable.child_count (Core.Renderer.root renderer));
  assert_child_ids (Core.Slot_mount.renderable mount)
    [ "fallback"; "first-1"; "second-1" ];
  (match Core.Slot_mount.mode mount with
  | Core.Slot_mount.Append -> ()
  | Core.Slot_mount.Replace | Core.Slot_mount.Single_winner ->
      fail "mount did not retain append mode");
  expect_mount_unit (Core.Slot_mount.set_mode mount Core.Slot_mount.Replace);
  assert_child_ids (Core.Slot_mount.renderable mount) [ "first-1"; "second-1" ];
  (match !fallback_view with
  | Some produced ->
      equal bool true (Core.Renderable.is_destroyed produced.renderable)
  | None -> fail "fallback was not evaluated for append mode");
  expect_mount_unit
    (Core.Slot_mount.set_mode mount Core.Slot_mount.Single_winner);
  assert_child_ids (Core.Slot_mount.renderable mount) [ "first-1" ];
  let second = latest second_views in
  equal bool true (Core.Renderable.is_destroyed second.renderable);
  (match Core.Slot_mount.mode mount with
  | Core.Slot_mount.Single_winner -> ()
  | Core.Slot_mount.Append | Core.Slot_mount.Replace ->
      fail "mount did not retain single-winner mode");
  Core.Slot_mount.destroy mount;
  ignore (expect_host (Plugin.Host.close host));
  Core.Renderer.destroy renderer

let test_props_refresh_replaces_views () =
  let renderer = expect_core (Core.Renderer.create ~width:16l ~height:4l) in
  let context = Core.Renderer.context renderer in
  let host = Plugin.Host.create ~renderer ~reporter:Plugin.Reporter.ignore in
  let slot, sink =
    expect_failure
      (Core.Slot.create ~host ~id:(expect_id "props-slot"))
  in
  let views = ref [] in
  let render props =
    let produced = make_view context ~id:("value-" ^ string_of_int props) in
    views := produced :: !views;
    Ok (Some produced.view)
  in
  ignore
    (install_contributor ~host ~sink ~id:"props-plugin" ~order:0 ~render);
  let mount = expect_mount (Core.Slot_mount.create ~renderer ~slot ~props:1 ()) in
  attach_mount renderer mount;
  let first = latest views in
  assert_child_ids (Core.Slot_mount.renderable mount) [ "value-1" ];
  expect_mount_unit (Core.Slot_mount.set_props mount 2);
  let second = latest views in
  assert_child_ids (Core.Slot_mount.renderable mount) [ "value-2" ];
  equal bool true (Core.Renderable.is_destroyed first.renderable);
  equal int 1 !(first.deactivated);
  expect_mount_unit (Core.Slot_mount.set_props mount 2);
  let third = latest views in
  assert_child_ids (Core.Slot_mount.renderable mount) [ "value-2" ];
  equal bool true (Core.Renderable.is_destroyed second.renderable);
  equal int 1 !(second.deactivated);
  equal bool false (Core.Renderable.is_destroyed third.renderable);
  equal int 3 (List.length !views);
  Core.Slot_mount.destroy mount;
  ignore (expect_host (Plugin.Host.close host));
  Core.Renderer.destroy renderer

let test_placeholder_for_failed_plugin () =
  let renderer = expect_core (Core.Renderer.create ~width:16l ~height:4l) in
  let context = Core.Renderer.context renderer in
  let reported = ref [] in
  let reporter =
    Plugin.Reporter.create (fun failure -> reported := failure :: !reported)
  in
  let host = Plugin.Host.create ~renderer ~reporter in
  let slot, sink =
    expect_failure
      (Core.Slot.create ~host ~id:(expect_id "placeholder-slot"))
  in
  let placeholder_failure = ref None in
  let placeholder_view = ref None in
  let render _props =
    Error
      (Core.Plugin_failure.make ~phase:Core.Plugin_failure.Render
         ~origin:Core.Plugin_failure.Plugin ~cause:Core.Plugin_failure.Busy ())
  in
  ignore
    (install_contributor ~host ~sink ~id:"failing-plugin" ~order:0 ~render);
  let placeholder failure =
    placeholder_failure := Some failure;
    let produced = make_view context ~id:"placeholder" in
    placeholder_view := Some produced;
    Ok [ produced.view ]
  in
  let mount =
    expect_mount
      (Core.Slot_mount.create ~renderer ~slot ~props:()
         ~mode:Core.Slot_mount.Replace ~placeholder ())
  in
  attach_mount renderer mount;
  assert_child_ids (Core.Slot_mount.renderable mount) [ "placeholder" ];
  (match !placeholder_failure with
  | Some failure ->
      (match failure.Core.Plugin_failure.phase with
      | Core.Plugin_failure.Render -> ()
      | _ -> fail "placeholder received the wrong failure phase")
  | None -> fail "placeholder was not called for a failed contribution");
  equal int 1 (List.length !reported);
  (match !placeholder_view with
  | Some produced ->
      Core.Slot_mount.destroy mount;
      equal bool true (Core.Renderable.is_destroyed produced.renderable)
  | None -> fail "placeholder did not produce a view");
  ignore (expect_host (Plugin.Host.close host));
  Core.Renderer.destroy renderer

let test_renderer_ownership_is_enforced () =
  let renderer = expect_core (Core.Renderer.create ~width:12l ~height:4l) in
  let foreign_renderer =
    expect_core (Core.Renderer.create ~width:12l ~height:4l)
  in
  let foreign_host =
    Plugin.Host.create ~renderer:foreign_renderer
      ~reporter:Plugin.Reporter.ignore
  in
  let foreign_slot, _foreign_sink =
    expect_failure
      (Core.Slot.create ~host:foreign_host ~id:(expect_id "foreign-slot"))
  in
  (match Core.Slot_mount.create ~renderer ~slot:foreign_slot ~props:() () with
  | Error failure ->
      (match failure.Core.Plugin_failure.cause with
      | Core.Plugin_failure.Renderer_error Core.Error.Owner_mismatch -> ()
      | _ -> fail "wrong-renderer mount returned the wrong failure")
  | Ok mount ->
      Core.Slot_mount.destroy mount;
      fail "wrong-renderer mount was accepted");
  let reported = ref [] in
  let host =
    Plugin.Host.create ~renderer
      ~reporter:(Plugin.Reporter.create (fun failure -> reported := failure :: !reported))
  in
  let slot, sink =
    expect_failure
      (Core.Slot.create ~host ~id:(expect_id "owned-slot"))
  in
  let foreign_views = ref [] in
  let render _props =
    let box = expect_core (Box.create (Core.Renderer.context foreign_renderer) ()) in
    let renderable = Box.as_renderable box in
    let view = Core.Slot_view.create renderable in
    foreign_views := renderable :: !foreign_views;
    Ok (Some view)
  in
  ignore
    (install_contributor ~host ~sink ~id:"foreign-view-plugin" ~order:0 ~render);
  let mount = expect_mount (Core.Slot_mount.create ~renderer ~slot ~props:() ()) in
  equal int 0 (Core.Renderable.child_count (Core.Slot_mount.renderable mount));
  (match !reported with
  | failure :: _ ->
      (match failure.Core.Plugin_failure.cause with
      | Core.Plugin_failure.Invalid_view Core.Plugin_failure.View_wrong_renderer ->
          ()
      | _ -> fail "wrong-renderer view returned the wrong failure")
  | [] -> fail "wrong-renderer view was not reported");
  (match !foreign_views with
  | renderable :: _ ->
      equal bool true (Core.Renderable.is_destroyed renderable)
  | [] -> fail "foreign view callback was not called");
  Core.Slot_mount.destroy mount;
  ignore (expect_host (Plugin.Host.close host));
  ignore (expect_host (Plugin.Host.close foreign_host));
  Core.Renderer.destroy renderer;
  Core.Renderer.destroy foreign_renderer

let test_mount_destruction_releases_views () =
  let renderer = expect_core (Core.Renderer.create ~width:12l ~height:4l) in
  let context = Core.Renderer.context renderer in
  let host = Plugin.Host.create ~renderer ~reporter:Plugin.Reporter.ignore in
  let slot, sink =
    expect_failure
      (Core.Slot.create ~host ~id:(expect_id "destroy-slot"))
  in
  let views = ref [] in
  let render _props =
    let produced = make_view context ~id:"owned" in
    views := produced :: !views;
    Ok (Some produced.view)
  in
  ignore
    (install_contributor ~host ~sink ~id:"destroy-plugin" ~order:0 ~render);
  let mount =
    expect_mount (Core.Slot_mount.create ~renderer ~slot ~props:() ())
  in
  attach_mount renderer mount;
  let mount_renderable = Core.Slot_mount.renderable mount in
  let child = latest views in
  equal int 1 (Core.Renderable.child_count mount_renderable);
  equal int 1 (Core.Renderable.child_count (Core.Renderer.root renderer));
  Core.Slot_mount.destroy mount;
  equal bool true (Core.Slot_mount.is_destroyed mount);
  equal bool true (Core.Renderable.is_destroyed mount_renderable);
  equal bool true (Core.Renderable.is_destroyed child.renderable);
  equal int 1 !(child.deactivated);
  equal int 0 (Core.Renderable.child_count (Core.Renderer.root renderer));
  Core.Slot_mount.destroy mount;
  equal int 1 !(child.deactivated);
  (match Core.Slot_mount.refresh mount with
  | Error (first :: _) ->
      (match first.Core.Plugin_failure.cause with
      | Core.Plugin_failure.Host_closed -> ()
      | _ -> fail "destroyed mount returned the wrong refresh failure")
  | Error [] -> fail "destroyed mount returned no refresh failure"
  | Ok () -> fail "destroyed mount refreshed successfully");
  ignore (expect_host (Plugin.Host.close host));
  Core.Renderer.destroy renderer

let test_host_close_cleans_attached_mount () =
  let renderer = expect_core (Core.Renderer.create ~width:12l ~height:4l) in
  let context = Core.Renderer.context renderer in
  let host = Plugin.Host.create ~renderer ~reporter:Plugin.Reporter.ignore in
  let slot, sink =
    expect_failure
      (Core.Slot.create ~host ~id:(expect_id "host-close-slot"))
  in
  let views = ref [] in
  let render _props =
    let produced = make_view context ~id:"host-owned" in
    views := produced :: !views;
    Ok (Some produced.view)
  in
  ignore
    (install_contributor ~host ~sink ~id:"host-close-plugin" ~order:0 ~render);
  let mount =
    expect_mount (Core.Slot_mount.create ~renderer ~slot ~props:() ())
  in
  attach_mount renderer mount;
  let child = latest views in
  ignore (expect_host (Plugin.Host.close host));
  equal int 0 (Core.Renderable.child_count (Core.Slot_mount.renderable mount));
  equal bool true (Core.Renderable.is_destroyed child.renderable);
  (match Core.Slot_mount.refresh mount with
  | Error (first :: _) ->
      (match first.Core.Plugin_failure.cause with
      | Core.Plugin_failure.Host_closed -> ()
      | _ -> fail "closed host returned the wrong refresh failure")
  | Error [] -> fail "closed host returned no refresh failure"
  | Ok () -> fail "closed host refreshed successfully");
  Core.Slot_mount.destroy mount;
  Core.Renderer.destroy renderer

let () =
  run "opentui-core-slot-mount"
    [
      test "append, replace, and single-winner modes manage fallback and order"
        test_modes_and_fallback;
      test "props refresh replaces accepted views, including equal props"
        test_props_refresh_replaces_views;
      test "failed contributions render their placeholder"
        test_placeholder_for_failed_plugin;
      test "slot mounts and views enforce renderer ownership"
        test_renderer_ownership_is_enforced;
      test "destroying a mount releases its retained views"
        test_mount_destruction_releases_views;
      test "closing a host cleans its attached mounts"
        test_host_close_cleans_attached_mount;
    ]
