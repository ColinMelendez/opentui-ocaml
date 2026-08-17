open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Renderables = Core.Renderables

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_decode_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Image.decode_message error)

let expect_image_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Image.message error)

let attach renderer image =
  ignore
    (expect_ok
       (Core.Layout_children.add (Renderer.children renderer)
          (Renderables.Image.as_renderable image)))

let child_path root name = Eio.Path.(root / name)

let await_until env predicate =
  let attempts = ref 0 in
  while not (predicate ()) && Int.compare !attempts 10_000 < 0 do
    incr attempts;
    Eio.Time.Mono.sleep (Eio.Stdenv.mono_clock env) 0.001
  done;
  if not (predicate ()) then fail "image request did not reach its expected state"

let fixture_bytes () =
  Bytes.of_string
    "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x02\x00\x00\x00\x02\x01\x03\x00\x00\x00\x48\x78\x9f\x67\x00\x00\x00\x20\x63\x48\x52\x4d\x00\x00\x7a\x26\x00\x00\x80\x84\x00\x00\xfa\x00\x00\x00\x80\xe8\x00\x00\x75\x30\x00\x00\xea\x60\x00\x00\x3a\x98\x00\x00\x17\x70\x9c\xba\x51\x3c\x00\x00\x00\x06\x50\x4c\x54\x45\xff\x00\x00\xff\xff\xff\x41\x1d\x34\x11\x00\x00\x00\x01\x62\x4b\x47\x44\x01\xff\x02\x2d\xde\x00\x00\x00\x07\x74\x49\x4d\x45\x07\xea\x06\x0b\x0a\x16\x38\x1a\x47\x68\x7a\x00\x00\x00\x0c\x49\x44\x41\x54\x08\xd7\x63\x60\x60\x60\x00\x00\x00\x04\x00\x01\x27\x34\x27\x0a\x00\x00\x00\x25\x74\x45\x58\x74\x64\x61\x74\x65\x3a\x63\x72\x65\x61\x74\x65\x00\x32\x30\x32\x36\x2d\x30\x36\x2d\x31\x31\x54\x31\x30\x3a\x32\x32\x3a\x35\x36\x2b\x30\x30\x3a\x30\x30\x20\xd9\xde\x67\x00\x00\x00\x25\x74\x45\x58\x74\x64\x61\x74\x65\x3a\x6d\x6f\x64\x69\x66\x79\x00\x32\x30\x32\x36\x2d\x30\x36\x2d\x31\x31\x54\x31\x30\x3a\x32\x32\x3a\x35\x36\x2b\x30\x30\x3a\x30\x30\x51\x84\x66\xdb\x00\x00\x00\x28\x74\x45\x58\x74\x64\x61\x74\x65\x3a\x74\x69\x6d\x65\x73\x74\x61\x6d\x70\x00\x32\x30\x32\x36\x2d\x30\x36\x2d\x31\x31\x54\x31\x30\x3a\x32\x32\x3a\x35\x36\x2b\x30\x30\x3a\x30\x30\x06\x91\x47\x04\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82"

let test_core_error_mapping () =
  let unsupported_message = "the image format is unsupported" in
  equal string unsupported_message
    (Opentui_raw.Image.message Opentui_raw.Image.Unsupported_format);
  equal string unsupported_message
    (Format.asprintf "%a" Opentui_raw.Image.pp
       Opentui_raw.Image.Unsupported_format);
  (match Core.Image.decode Bytes.empty with
  | Error Core.Image.Invalid_argument -> ()
  | Error _ -> fail "empty image input lost its structured argument error"
  | Ok _ -> fail "empty image input unexpectedly decoded");
  (match Core.Image.decode (Bytes.of_string "not an image") with
  | Error (Core.Image.Native Opentui_raw.Image.Unsupported_format) -> ()
  | Error (Core.Image.Native error) ->
      fail
        (Printf.sprintf "unexpected native decode error: %s"
           (Core.Image.decode_message (Core.Image.Native error)))
  | Error _ -> fail "decode did not preserve its native error constructor"
  | Ok _ -> fail "malformed image input unexpectedly decoded");
  (match Core.Image.load (Core.Image.Encoded (Bytes.of_string "not an image")) with
  | Error
      (Core.Image.Decode (Core.Image.Native Opentui_raw.Image.Unsupported_format)) ->
      ()
  | Error _ -> fail "load collapsed the native decode error"
  | Ok _ -> fail "malformed encoded source unexpectedly loaded")

let test_sync_snapshot_and_direct_destroy () =
  let renderer = expect_ok (Renderer.create ~width:8l ~height:4l) in
  let pixels = Bytes.of_string "\255\000\000\255" in
  let expected = Bytes.copy pixels in
  let loaded =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer)
         ~source:
           (Renderables.Image.Source
              (Core.Image.Rgba { pixels; width = 1; height = 1; stride = 4 }))
         ~buffered:true ())
  in
  Bytes.fill pixels 0 (Bytes.length pixels) '\000';
  attach renderer loaded;
  (match Renderables.Image.state loaded with
  | Renderables.Image.Ready -> ()
  | Renderables.Image.Empty | Renderables.Image.Loading
  | Renderables.Image.Failed _ -> fail "synchronous RGBA source was not ready");
  equal bool false (Renderables.Image.loading loaded);
  equal bool false (Option.is_some (Renderables.Image.load_error loaded));
  let retained =
    match Renderables.Image.image loaded with
    | Some image -> image
    | None -> fail "synchronous RGBA source was not retained"
  in
  let copied, _stride = expect_image_ok (Core.Image.copy retained ()) in
  equal string (Bytes.to_string expected) (Bytes.to_string copied);
  let exposed_pixels =
    match Renderables.Image.source loaded with
    | Some
        (Renderables.Image.Source
          (Core.Image.Rgba { pixels; width = 1; height = 1; stride = 4 })) ->
        pixels
    | Some _ | None -> fail "RGBA source snapshot was not retained"
  in
  Bytes.fill exposed_pixels 0 (Bytes.length exposed_pixels) '\000';
  (match Renderables.Image.source loaded with
  | Some
      (Renderables.Image.Source
        (Core.Image.Rgba { pixels; width = 1; height = 1; stride = 4 })) ->
      equal string (Bytes.to_string expected) (Bytes.to_string pixels)
  | Some _ | None -> fail "source getter mutation changed the retained snapshot");
  Renderable.destroy (Renderables.Image.as_renderable loaded);
  (match Core.Image.get_info retained with
  | Error Core.Image.Closed -> ()
  | Error _ -> fail "direct renderable destruction returned the wrong image error"
  | Ok _ -> fail "direct renderable destruction leaked the native image");
  let renderer_buffer = expect_ok (Renderer.next_buffer renderer) in
  (match
     Core.Buffer.draw_image renderer_buffer ~image:retained ~x:0l ~y:0l
       ~width:1l ~height:1l ~pixel_width:0l ~pixel_height:0l ()
   with
  | Error
      (Core.Error.Native_image Opentui_raw.Image.Invalid_handle) ->
      ()
  | Error error ->
      fail
        (Printf.sprintf "renderer buffer collapsed a closed image error: %s"
           (Core.Error.message error))
  | Ok () -> fail "renderer buffer drew a closed image owner");
  let owned_buffer =
    expect_ok (Core.Owned_buffer.create ~width:1 ~height:1 ())
  in
  (match
     Core.Owned_buffer.draw_image owned_buffer ~image:retained ~x:0 ~y:0
       ~width:1 ~height:1 ~pixel_width:0 ~pixel_height:0 ()
   with
  | Error
      (Core.Error.Native_image Opentui_raw.Image.Invalid_handle) ->
      ()
  | Error error ->
      fail
        (Printf.sprintf "owned buffer collapsed a closed image error: %s"
           (Core.Error.message error))
  | Ok () -> fail "owned buffer drew a closed image owner");
  Core.Owned_buffer.close owned_buffer;
  Renderer.destroy renderer

let test_bounded_reads_and_async_replacement () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let root = Eio.Stdenv.cwd env in
  let valid_path = child_path root "__opentui_phase6_valid_image.png" in
  let missing_path = child_path root "__opentui_phase6_missing_image.png" in
  let oversized_path = child_path root "__opentui_phase6_oversized_image.bin" in
  Eio.Path.save ~create:(`Or_truncate 0o600) valid_path
    (Bytes.to_string (fixture_bytes ()));
  Eio.Switch.run @@ fun file_sw ->
  let file =
    Eio.Path.open_out ~sw:file_sw ~create:(`Or_truncate 0o600) oversized_path
  in
  Eio.File.truncate file
    (Optint.Int63.of_int (Core.Image.max_path_bytes + 1));
  (match Core.Image.load (Core.Image.Path missing_path) with
  | Error (Core.Image.Read (Core.Image.Io { operation = Core.Image.Stat; _ })) ->
      ()
  | Error _ -> fail "missing image path returned the wrong structured read error"
  | Ok image ->
      Core.Image.close image;
      fail "missing image path unexpectedly loaded");
  (match Core.Image.load (Core.Image.Path oversized_path) with
  | Error (Core.Image.Read (Core.Image.Too_large { limit })) ->
      equal int Core.Image.max_path_bytes limit
  | Error _ -> fail "oversized image path did not report the byte limit"
  | Ok image ->
      Core.Image.close image;
      fail "oversized image path unexpectedly loaded");
  let renderer = expect_ok (Renderer.create ~width:8l ~height:4l) in
  let decode_failure = ref None in
  let failed =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer)
         ~on_error:(fun error -> decode_failure := Some error)
         ~source:
           (Renderables.Image.Source
              (Core.Image.Encoded (Bytes.of_string "not an image"))) ())
  in
  (match Renderables.Image.state failed with
  | Renderables.Image.Failed
      (Core.Image.Decode
        (Core.Image.Native Opentui_raw.Image.Unsupported_format)) ->
      ()
  | Renderables.Image.Empty | Renderables.Image.Loading
  | Renderables.Image.Ready | Renderables.Image.Failed _ ->
      fail "invalid encoded source returned the wrong renderable state");
  (match !decode_failure with
  | Some
      (Core.Image.Decode
        (Core.Image.Native Opentui_raw.Image.Unsupported_format)) ->
      ()
  | Some _ -> fail "decode callback lost the exact native error"
  | None -> fail "decode failure did not invoke on_error");
  Renderables.Image.destroy failed;
  (match
     Renderables.Image.create (Renderer.context renderer)
       ~source:(Renderables.Image.Source (Core.Image.Path valid_path)) ()
   with
  | Error Core.Error.Missing_async_lifetime -> ()
  | Error error ->
      fail
        (Printf.sprintf "Path admission returned the wrong lifetime error: %s"
           (Core.Error.message error))
  | Ok image ->
      Renderables.Image.destroy image;
      fail "Path admission unexpectedly created without an Eio switch");
  let errors = ref 0 in
  let last_error = ref None in
  let image =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer) ~sw
         ~on_error:(fun error -> incr errors; last_error := Some error) ())
  in
  attach renderer image;
  expect_ok
    (Renderables.Image.set_source image
       (Some (Renderables.Image.Source (Core.Image.Path valid_path))));
  (match Renderables.Image.state image with
  | Renderables.Image.Loading -> ()
  | Renderables.Image.Empty | Renderables.Image.Ready
  | Renderables.Image.Failed _ -> fail "path source did not enter Loading state");
  equal bool true (Renderables.Image.loading image);
  await_until env (fun () ->
      match Renderables.Image.state image with
      | Renderables.Image.Ready -> true
      | Renderables.Image.Empty | Renderables.Image.Loading
      | Renderables.Image.Failed _ -> false);
  equal bool false (Renderables.Image.loading image);
  equal int 0 !errors;
  let displayed =
    match Renderables.Image.image image with
    | Some value -> value
    | None -> fail "successful path load has no displayed image"
  in
  expect_ok
    (Renderables.Image.set_source image
       (Some (Renderables.Image.Source (Core.Image.Path missing_path))));
  await_until env (fun () -> Option.is_some (Renderables.Image.load_error image));
  (match Renderables.Image.state image with
  | Renderables.Image.Failed (Core.Image.Read _) -> ()
  | Renderables.Image.Empty | Renderables.Image.Loading
  | Renderables.Image.Ready | Renderables.Image.Failed _ ->
      fail "missing replacement did not enter Failed state");
  (match !last_error with
  | Some (Core.Image.Read (Core.Image.Io { operation = Core.Image.Stat; _ })) ->
      ()
  | Some _ -> fail "read callback lost the structured stat error"
  | None -> fail "missing replacement did not invoke on_error");
  (match Renderables.Image.image image with
  | Some current when current == displayed -> ()
  | Some _ -> fail "failed replacement replaced the displayed image"
  | None -> fail "failed replacement discarded the displayed image");
  equal int 1 !errors;
  expect_ok (Renderables.Image.set_source image None);
  (match Renderables.Image.state image, Renderables.Image.image image with
  | Renderables.Image.Empty, None -> ()
  | _, _ -> fail "clearing the source did not clear the image state");
  (match Core.Image.get_info displayed with
  | Error Core.Image.Closed -> ()
  | Error _ -> fail "clearing the source returned the wrong close error"
  | Ok _ -> fail "clearing the source leaked the displayed image");
  Renderables.Image.destroy image;
  let error_callback_image = ref None in
  let error_callback_calls = ref 0 in
  let recovery_pixels = Bytes.of_string "\000\255\000\255" in
  let recovered =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer) ~sw
         ~on_error:(fun _error ->
           incr error_callback_calls;
           match !error_callback_image with
           | None -> fail "on_error ran before image creation returned"
           | Some value ->
               expect_ok
                 (Renderables.Image.set_source value
                    (Some
                       (Renderables.Image.Source
                          (Core.Image.Rgba
                             {
                               pixels = recovery_pixels;
                               width = 1;
                               height = 1;
                               stride = 4;
                             }))))) ())
  in
  error_callback_image := Some recovered;
  expect_ok
    (Renderables.Image.set_source recovered
       (Some (Renderables.Image.Source (Core.Image.Path missing_path))));
  await_until env (fun () ->
      match Renderables.Image.state recovered with
      | Renderables.Image.Ready -> true
      | Renderables.Image.Empty | Renderables.Image.Loading
      | Renderables.Image.Failed _ -> false);
  equal int 1 !error_callback_calls;
  equal bool false (Option.is_some (Renderables.Image.load_error recovered));
  (match Renderables.Image.image recovered with
  | Some _ -> ()
  | None -> fail "re-entrant on_error replacement lost its recovered image");
  Renderables.Image.destroy recovered;
  Renderer.destroy renderer;
  Eio.Path.unlink ~missing_ok:true valid_path;
  Eio.Path.unlink ~missing_ok:true missing_path;
  Eio.Path.unlink ~missing_ok:true oversized_path

let test_stale_success_and_reentrant_callbacks () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let path = child_path (Eio.Stdenv.cwd env) "__opentui_phase6_stale_image.png" in
  Eio.Path.save ~create:(`Or_truncate 0o600) path
    (Bytes.to_string (fixture_bytes ()));
  let renderer = expect_ok (Renderer.create ~width:8l ~height:4l) in
  let replacement_calls = ref 0 in
  let replacement =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer) ~sw
         ~on_load:(fun _info -> incr replacement_calls) ())
  in
  expect_ok
    (Renderables.Image.set_source replacement
       (Some (Renderables.Image.Source (Core.Image.Path path))));
  expect_ok
    (Renderables.Image.set_source replacement
       (Some (Renderables.Image.Source (Core.Image.Path path))));
  await_until env (fun () ->
      match Renderables.Image.state replacement with
      | Renderables.Image.Ready -> true
      | Renderables.Image.Empty | Renderables.Image.Loading
      | Renderables.Image.Failed _ -> false);
  equal int 1 !replacement_calls;
  Renderables.Image.destroy replacement;
  let stale_calls = ref 0 in
  let stale =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer) ~sw
         ~on_load:(fun _info -> incr stale_calls) ())
  in
  attach renderer stale;
  expect_ok
    (Renderables.Image.set_source stale
       (Some (Renderables.Image.Source (Core.Image.Path path))));
  expect_ok (Renderables.Image.set_source stale None);
  Eio.Fiber.yield ();
  Eio.Fiber.yield ();
  equal int 0 !stale_calls;
  (match Renderables.Image.state stale, Renderables.Image.image stale with
  | Renderables.Image.Empty, None -> ()
  | _, _ -> fail "stale path completion resurrected a cleared source");
  Renderables.Image.destroy stale;
  let destroyed_calls = ref 0 in
  let doomed =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer) ~sw
         ~on_load:(fun _info -> incr destroyed_calls)
         ~on_error:(fun _error -> incr destroyed_calls) ())
  in
  expect_ok
    (Renderables.Image.set_source doomed
       (Some (Renderables.Image.Source (Core.Image.Path path))));
  Renderable.destroy (Renderables.Image.as_renderable doomed);
  Eio.Fiber.yield ();
  Eio.Fiber.yield ();
  equal int 0 !destroyed_calls;
  (match Renderables.Image.state doomed, Renderables.Image.image doomed with
  | Renderables.Image.Empty, None -> ()
  | _, _ -> fail "direct renderable destruction left an image request alive");
  let callback_image = ref None in
  let callback_calls = ref 0 in
  let reentrant =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer) ~sw
         ~on_load:(fun info ->
           equal int 2 info.width;
           equal int 2 info.height;
           incr callback_calls;
           match !callback_image with
           | None -> fail "image callback ran before creation returned"
           | Some value -> ignore (Renderables.Image.set_source value None)) ())
  in
  callback_image := Some reentrant;
  attach renderer reentrant;
  expect_ok
    (Renderables.Image.set_source reentrant
       (Some (Renderables.Image.Source (Core.Image.Path path))));
  await_until env (fun () -> Int.equal !callback_calls 1);
  (match Renderables.Image.state reentrant, Renderables.Image.image reentrant with
  | Renderables.Image.Empty, None -> ()
  | _, _ -> fail "re-entrant on_load replacement was overwritten afterward");
  Renderables.Image.destroy reentrant;
  Renderer.destroy renderer;
  Eio.Path.unlink ~missing_ok:true path

let () =
  run "opentui-core-image-loading"
    [ test "Core image errors preserve native decode and read distinctions"
        test_core_error_mapping;
      test "synchronous image admission snapshots bytes and direct destruction closes owners"
        test_sync_snapshot_and_direct_destroy;
      test "bounded path reads and asynchronous replacement preserve displayed images"
        test_bounded_reads_and_async_replacement;
      test "stale path results and re-entrant callbacks remain inert"
        test_stale_success_and_reentrant_callbacks ]
