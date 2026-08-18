open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Renderables = Core.Renderables

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_image_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Image.message error)

let expect_decode_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Image.decode_message error)

let expect_color_ok result =
  match result with
  | Ok value -> value
  | Error _ -> fail "color construction failed"

let attach renderer renderable =
  ignore
    (expect_ok
       (Core.Layout_children.add (Renderer.children renderer) renderable))

let rgba_pixels () =
  Bytes.of_string
    (String.init 8 (fun index ->
         match index with
         | 0 -> Char.chr 255
         | 1 -> Char.chr 0
         | 2 -> Char.chr 0
         | 3 -> Char.chr 255
         | 4 -> Char.chr 0
         | 5 -> Char.chr 0
         | 6 -> Char.chr 255
         | _ -> Char.chr 255))

let test_image_owner () =
  let pixels = rgba_pixels () in
  let image =
    expect_decode_ok
      (Core.Image.from_rgba ~pixels ~width:2 ~height:1 ~stride:8)
  in
  let info = expect_image_ok (Core.Image.get_info image) in
  equal int 2 info.width;
  equal int 1 info.height;
  equal int 2 info.source_width;
  equal int 1 info.source_height;
  equal bool false info.has_alpha;
  let copied, stride = expect_image_ok (Core.Image.copy image ()) in
  equal int 8 stride;
  equal string (Bytes.to_string pixels) (Bytes.to_string copied);
  let resized = expect_image_ok (Core.Image.resize image ~width:4 ~height:2 ()) in
  let resized_info = expect_image_ok (Core.Image.get_info resized) in
  equal int 4 resized_info.width;
  equal int 2 resized_info.height;
  let proportional = expect_image_ok (Core.Image.resize image ~width:4 ()) in
  equal int 2 (expect_image_ok (Core.Image.height proportional));
  let transferred = expect_image_ok (Core.Image.take_raw proportional ()) in
  equal int 4 transferred.width;
  equal int 2 transferred.height;
  equal int 16 transferred.stride;
  equal bool false transferred.bgra;
  let cropped = expect_image_ok (Core.Image.extract resized ~left:1 ~top:0 ~width:2 ~height:1) in
  let cropped_info = expect_image_ok (Core.Image.get_info cropped) in
  equal int 2 cropped_info.width;
  equal int 1 cropped_info.height;
  let extended = expect_image_ok (Core.Image.extend cropped ~right:1 ()) in
  equal int 3 (expect_image_ok (Core.Image.width extended));
  let transformed = expect_image_ok (Core.Image.transform image `Rotate_180) in
  equal int 2 (expect_image_ok (Core.Image.width transformed));
  let retained = expect_image_ok (Core.Image.retain image) in
  Core.Image.close image;
  (match Core.Image.get_info image with
  | Error Core.Image.Closed -> ()
  | Error _ -> fail "closed image returned the wrong error"
  | Ok _ -> fail "closed image remained readable");
  equal int 2 (expect_image_ok (Core.Image.width retained));
  Core.Image.close retained;
  Core.Image.close resized;
  (match Core.Image.width proportional with
  | Error Core.Image.Closed -> ()
  | Error _ -> fail "transferred image returned the wrong close error"
  | Ok _ -> fail "take_raw left the image owner open");
  Core.Image.close cropped;
  Core.Image.close extended;
  Core.Image.close transformed;
  (match Core.Image.decode Bytes.empty with
  | Error Core.Image.Invalid_argument -> ()
  | Error _ -> fail "empty encoded image returned the wrong error"
  | Ok _ -> fail "empty encoded image decoded")

let test_image_source_boundary () =
  Eio_main.run @@ fun env ->
  let path = Eio.Path.(env#fs / "__opentui_visual_runtime_missing_image__") in
  match Core.Image.load (Core.Image.Path path) with
  | Error (Core.Image.Read _) -> ()
  | Error _ -> fail "Eio image source returned the wrong read error"
  | Ok image ->
      Core.Image.close image;
      fail "missing Eio image source unexpectedly loaded"

let test_image_renderable () =
  let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:12l ~height:4l ()) in
  let source =
    expect_decode_ok
      (Core.Image.from_rgba ~pixels:(rgba_pixels ()) ~width:2 ~height:1 ~stride:8)
  in
  let image =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer)
         ~source:(Renderables.Image.Native source)
         ~fit:Renderables.Image.Fill ~protocol:Core.Image.Blocks ~width:4 ~height:2
         ())
  in
  attach renderer (Renderables.Image.as_renderable image);
  (match Renderables.Image.effective_protocol image with
  | Core.Image.Blocks -> ()
  | Core.Image.Auto | Core.Image.Kitty | Core.Image.Sixel ->
      fail "explicit blocks protocol was not preserved");
  let fitted =
    Renderables.Image.get_fitted_size image ~target_width:4 ~target_height:2 ()
  in
  (match fitted with
  | 4, 2 -> ()
  | width, height ->
      fail (Printf.sprintf "unexpected fitted size %d x %d" width height));
  (match Core.Image.take_raw source () with
  | Error (Core.Image.Native Opentui_raw.Image.Invalid_argument) -> ()
  | Error _ -> fail "retained image transfer returned the wrong error"
  | Ok _ -> fail "retained image transfer ignored native ownership");
  Core.Image.close source;
  ignore (expect_ok (Renderer.render renderer ~force:true));
  (match Renderables.Image.image image with
  | None -> fail "renderable lost its retained image after source close"
  | Some retained -> equal int 2 (expect_image_ok (Core.Image.width retained)));
  ignore (expect_ok (Renderables.Image.set_source image None));
  (match Renderables.Image.image image with
  | None -> ()
  | Some _ -> fail "clearing image source retained a native image");
  let buffered_source =
    expect_decode_ok
      (Core.Image.from_rgba ~pixels:(rgba_pixels ()) ~width:2 ~height:1 ~stride:8)
  in
  let buffered =
    expect_ok
      (Renderables.Image.create (Renderer.context renderer)
         ~source:(Renderables.Image.Native buffered_source) ~buffered:true
         ~protocol:Core.Image.Blocks ~width:4 ~height:2 ())
  in
  equal bool true (Renderables.Image.buffered buffered);
  attach renderer (Renderables.Image.as_renderable buffered);
  ignore (expect_ok (Renderer.render renderer ~force:true));
  ignore (expect_ok (Renderables.Image.set_source buffered None));
  ignore (expect_ok (Renderer.render renderer ~force:true));
  Core.Image.close buffered_source;
  Renderables.Image.destroy buffered;
  Renderables.Image.destroy image;
  Renderer.destroy renderer

let test_post_filters_and_effects () =
  let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:6l ~height:3l ()) in
  let buffer = expect_ok (Renderer.next_buffer renderer) in
  let red = expect_color_ok (Core.Color.rgb ~red:255 ~green:0 ~blue:0) in
  ignore
    (expect_ok
       (Core.Buffer.set_cell buffer ~x:0l ~y:0l ~character:65l
          ~foreground:red ~background:Core.Color.black ~attributes:0l));
  let snapshot = expect_ok (Core.Buffer.snapshot buffer) in
  let chars, foreground, _background, _attributes = snapshot in
  equal int 72 (Array.length foreground);
  equal int 18 (Array.length chars);
  ignore
    (expect_ok
       (Core.Post.Filters.apply_invert buffer ~strength:1.0 ()));
  ignore
    (expect_ok
       (Core.Post.Filters.apply_scanlines buffer ~strength:0.5 ~step:2 ()));
  ignore
    (expect_ok
       (Core.Post.Filters.apply_noise buffer ~strength:0.05 ()));
  ignore
    (expect_ok
       (Core.Post.Filters.apply_brightness buffer ~brightness:0.1 ()));
  ignore
    (expect_ok
       (Core.Post.Filters.apply_gain buffer ~gain:0.9 ()));
  ignore
    (expect_ok
       (Core.Post.Filters.apply_saturation buffer ~strength:0.4 ()));
  ignore
    (expect_ok
       (Core.Post.Filters.apply_chromatic_aberration buffer ~strength:1.0 ()));
  ignore
    (expect_ok
       (Core.Post.Filters.apply_ascii_art buffer ~ramp:" .#" ()));
  let bloom = Core.Post.Filters.Bloom_effect.create ~radius:1 () in
  ignore (expect_ok (Core.Post.Filters.Bloom_effect.apply bloom buffer));
  let vignette = Core.Post.Effects.Vignette_effect.create () in
  ignore (expect_ok (Core.Post.Effects.Vignette_effect.apply vignette buffer));
  let clouds = Core.Post.Effects.Clouds_effect.create () in
  ignore (expect_ok (Core.Post.Effects.Clouds_effect.apply clouds buffer ~delta_time:0.016));
  let flames = Core.Post.Effects.Flames_effect.create () in
  ignore (expect_ok (Core.Post.Effects.Flames_effect.apply flames buffer ~delta_time:0.016));
  let crt = Core.Post.Effects.Crt_rolling_bar_effect.create () in
  ignore (expect_ok (Core.Post.Effects.Crt_rolling_bar_effect.apply crt buffer ~delta_time:0.016));
  let rainbow = Core.Post.Effects.Rainbow_text_effect.create () in
  ignore (expect_ok (Core.Post.Effects.Rainbow_text_effect.apply rainbow buffer ~delta_time:0.016));
  let distortion = Core.Post.Effects.Distortion_effect.create ~glitch_chance_per_second:0.0 () in
  ignore (expect_ok (Core.Post.Effects.Distortion_effect.apply distortion buffer ~delta_time:0.016));
  ignore (expect_ok (Core.Buffer.push_opacity buffer 0.5));
  equal (float 0.0001) 0.5 (expect_ok (Core.Buffer.current_opacity buffer));
  ignore (expect_ok (Core.Buffer.pop_opacity buffer));
  ignore (expect_ok (Core.Buffer.clear_opacity buffer));
  ignore
    (expect_ok
       (Core.Buffer.push_scissor_rect buffer ~x:0l ~y:0l ~width:3l ~height:2l));
  ignore (expect_ok (Core.Buffer.pop_scissor_rect buffer));
  ignore (expect_ok (Core.Buffer.clear_scissor_rects buffer));
  let calls = ref 0 in
  let post_id =
    expect_ok
      (Renderer.add_post_process renderer (fun _buffer ~delta_time ->
           if not (Int.equal (Float.compare delta_time 0.25) 0) then
             Error Core.Error.Invalid_argument
           else begin
             calls := !calls + 1;
             Ok ()
           end))
  in
  ignore (expect_ok (Renderer.render ~delta_time:0.25 renderer ~force:true));
  equal int 1 !calls;
  ignore (expect_ok (Renderer.remove_post_process renderer post_id));
  ignore (expect_ok (Renderer.render ~delta_time:0.25 renderer ~force:true));
  equal int 1 !calls;
  (match Renderer.render ~delta_time:(-1.0) renderer ~force:true with
  | Error Core.Error.Invalid_argument -> ()
  | Error error -> fail (Core.Error.message error)
  | Ok _ -> fail "negative renderer delta was accepted");
  Renderer.destroy renderer

let test_console_owner () =
  let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:20l ~height:6l ()) in
  let console = Renderer.console renderer in
  ignore (expect_ok (Core.Console.info console "hello"));
  ignore (expect_ok (Core.Console.error console "failure"));
  ignore (expect_ok (Core.Console.log console "third"));
  ignore (expect_ok (Core.Console.log console "fourth"));
  ignore (expect_ok (Core.Console.show console));
  let bounds = expect_ok (Core.Console.bounds console) in
  equal int 1 bounds.height;
  equal int 20 bounds.width;
  equal int 4 (List.length (expect_ok (Core.Console.entries console)));
  ignore (expect_ok (Core.Console.select console ~start_line:0 ~start_column:0 ~end_line:0 ~end_column:6));
  equal bool true (expect_ok (Core.Console.has_selection console));
  equal string "[INFO]" (expect_ok (Core.Console.selected_text console));
  equal bool true (expect_ok (Core.Console.scroll_top console) > 0);
  ignore (expect_ok (Core.Console.scroll_to_top console));
  equal int 0 (expect_ok (Core.Console.scroll_top console));
  ignore (expect_ok (Core.Console.scroll_down console));
  let mouse_bounds = expect_ok (Core.Console.bounds console) in
  ignore
    (expect_ok
       (Core.Console.handle_mouse console ~action:Core.Console.Mouse_down
          ~button:0 ~x:(mouse_bounds.x + 1) ~y:(mouse_bounds.y + 1)));
  ignore (expect_ok (Renderer.render renderer ~force:true));
  ignore
    (expect_ok
       (Core.Console.handle_mouse console ~action:Core.Console.Mouse_drag
          ~button:0 ~x:(mouse_bounds.x + 4) ~y:(mouse_bounds.y + 1)));
  ignore
    (expect_ok
       (Core.Console.handle_mouse console ~action:Core.Console.Mouse_up
          ~button:0 ~x:(mouse_bounds.x + 4) ~y:(mouse_bounds.y + 1)));
  equal bool true (expect_ok (Core.Console.has_selection console));
  ignore (expect_ok (Core.Console.set_size_percent console 100));
  equal int 6 (expect_ok (Core.Console.bounds console)).height;
  ignore (expect_ok (Renderer.render renderer ~force:true));
  ignore (expect_ok (Renderer.resize renderer ~width:10l ~height:4l));
  let resized_bounds = expect_ok (Core.Console.bounds console) in
  equal int 10 resized_bounds.width;
  ignore (expect_ok (Core.Console.hide console));
  equal bool false (expect_ok (Core.Console.visible console));
  Renderer.destroy renderer;
  (match Core.Console.log console "after destroy" with
  | Error Core.Error.Destroyed -> ()
  | Error error -> fail (Core.Error.message error)
  | Ok () -> fail "destroyed renderer console accepted a log")

let () =
  run "opentui-core-visual-runtime"
    [ test "native image owner preserves dimensions and lifetime" test_image_owner;
      test "image loading stays inside the Eio source boundary" test_image_source_boundary;
      test "image renderable retains and releases native image sources" test_image_renderable;
      test "post filters and effects operate through typed buffer seams" test_post_filters_and_effects;
      test "diagnostic console is renderer-owned and non-global" test_console_owner ]
