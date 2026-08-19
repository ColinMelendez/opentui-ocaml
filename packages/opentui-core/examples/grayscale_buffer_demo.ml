(* Port of vendor/opentui/packages/examples/src/grayscale-buffer-demo.ts.

   The demo keeps the reference's two-panel comparison: the left panel draws
   one grayscale intensity per terminal cell, while the right panel feeds a
   2x supersampled intensity field to the native buffer implementation. *)

module O = Opentui_core
module Frame_buffer = O.Renderables.Frame_buffer
module Owned_buffer = O.Owned_buffer
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let expect_unit result =
  match result with
  | Ok () -> ()
  | Error error -> invalid_arg (O.Error.message error)

let rgba red green blue =
  match O.Color.rgba ~red ~green ~blue ~alpha:255 with
  | Ok color -> color
  | Error error -> invalid_arg (O.Native.Error.message error)

let background_color = rgba 20 20 30
let header_background = rgba 40 40 60
let divider_color = rgba 60 60 80
let info_color = rgba 150 150 170
let label_color = rgba 200 200 220
let highlight_color = rgba 100 200 255

let pattern_names = [| "Plasma"; "Ripples"; "Waves"; "Starburst"; "Dots"; "Checkers" |]

type demo = {
  renderer : O.Renderer.t;
  frame : Frame_buffer.t;
  buffer : Owned_buffer.t;
  mutable time : float;
  mutable paused : bool;
  mutable pattern_mode : int;
  mutable left_buffer : floatarray option;
  mutable right_buffer : floatarray option;
  live_lease : O.Renderer.live_lease;
  mutable key_subscription : O.Event_subscription.t option;
  mutable resize_subscription : O.Event_subscription.t option;
  mutable pre_render : O.Renderer.pre_render_driver option;
  mutable destroyed : bool;
}

let generate_plasma ~x ~y ~width ~height ~time =
  let nx = float_of_int x /. float_of_int width in
  let ny = float_of_int y /. float_of_int height in
  let v1 = sin (nx *. 10.0 +. time) in
  let v2 = sin (ny *. 10.0 +. (time *. 0.7)) in
  let v3 = sin ((nx +. ny) *. 8.0 +. (time *. 1.3)) in
  let distance = sqrt (((nx -. 0.5) *. (nx -. 0.5)) +. ((ny -. 0.5) *. (ny -. 0.5))) in
  let v4 = sin (distance *. 12.0 -. (time *. 2.0)) in
  (v1 +. v2 +. v3 +. v4 +. 4.0) /. 8.0

let generate_ripples ~x ~y ~width ~height ~time =
  let cx = float_of_int width /. 2.0 in
  let cy = float_of_int height /. 2.0 in
  let dx = float_of_int x -. cx in
  let dy = float_of_int y -. cy in
  let distance = sqrt ((dx *. dx) +. (dy *. dy)) in
  let wave = (sin (distance *. 0.5 -. (time *. 3.0)) *. 0.5) +. 0.5 in
  let fade = 1.0 -. Float.min (distance /. Float.max (float_of_int width) (float_of_int height)) 1.0 in
  wave *. fade

let generate_waves ~x ~y ~width ~height ~time =
  let nx = float_of_int x /. float_of_int width in
  let ny = float_of_int y /. float_of_int height in
  let diagonal = (nx +. ny) *. 6.0 -. (time *. 2.0) in
  let cross = sin (nx *. 8.0 +. time) *. sin (ny *. 8.0 +. (time *. 0.8)) in
  ((sin diagonal *. 0.5) +. 0.5) *. 0.6
  +. ((cross *. 0.5) +. 0.5) *. 0.4

let generate_starburst ~x ~y ~width ~height ~time =
  let cx = float_of_int width /. 2.0 in
  let cy = float_of_int height /. 2.0 in
  let dx = float_of_int x -. cx in
  let dy = float_of_int y -. cy in
  let angle = atan2 dy dx +. (time *. 0.5) in
  let ray_angle = angle *. 12.0 /. (2.0 *. Float.pi) in
  let ray_intensity = Float.abs (sin (ray_angle *. Float.pi)) in
  if Float.compare ray_intensity 0.7 > 0 then 1.0 else 0.0

let positive_mod value divisor =
  let remainder = mod_float value divisor in
  if Float.compare remainder 0.0 < 0 then remainder +. divisor else remainder

let generate_dots ~x ~y ~width ~height ~time =
  let grid_size = Float.min (float_of_int width) (float_of_int height) /. 6.0 in
  let gx = positive_mod (float_of_int x +. (time *. 3.0)) grid_size -. (grid_size /. 2.0) in
  let gy = positive_mod (float_of_int y +. (time *. 2.0)) grid_size -. (grid_size /. 2.0) in
  let distance = sqrt ((gx *. gx) +. (gy *. gy)) in
  if Float.compare distance (grid_size *. 0.35) < 0 then 1.0 else 0.0

let generate_checkers ~x ~y ~width ~height ~time =
  let cx = float_of_int width /. 2.0 in
  let cy = float_of_int height /. 2.0 in
  let dx = float_of_int x -. cx in
  let dy = float_of_int y -. cy in
  let cosine = cos (time *. 0.3) in
  let sine = sin (time *. 0.3) in
  let rx = (dx *. cosine) -. (dy *. sine) in
  let ry = (dx *. sine) +. (dy *. cosine) in
  let size = Float.min (float_of_int width) (float_of_int height) /. 8.0 in
  let check_x = int_of_float (floor (rx /. size)) in
  let check_y = int_of_float (floor (ry /. size)) in
  if (check_x + check_y) mod 2 = 0 then 1.0 else 0.0

let intensity demo ~x ~y ~width ~height ~time =
  match demo.pattern_mode with
  | 0 -> generate_plasma ~x ~y ~width ~height ~time
  | 1 -> generate_ripples ~x ~y ~width ~height ~time
  | 2 -> generate_waves ~x ~y ~width ~height ~time
  | 3 -> generate_starburst ~x ~y ~width ~height ~time
  | 4 -> generate_dots ~x ~y ~width ~height ~time
  | 5 -> generate_checkers ~x ~y ~width ~height ~time
  | _ -> generate_plasma ~x ~y ~width ~height ~time

let set_ascii_text buffer ~screen_width ~screen_height ~x ~y ~text ~foreground
    ~background =
  for index = 0 to String.length text - 1 do
    let column = x + index in
    if column >= 0 && column < screen_width && y >= 0 && y < screen_height then
      expect_unit
        (Owned_buffer.set_cell buffer ~x:column ~y
           ~character:(Int32.of_int (Char.code (String.get text index)))
           ~foreground ~background ~attributes:0l)
  done

let centered_offset width text_length =
  int_of_float
    (floor
       (float_of_int width /. 2.0 -. (float_of_int text_length /. 2.0)))

let ensure_buffer buffer size =
  match buffer with
  | Some values when Float.Array.length values = size -> values
  | Some _ | None -> Float.Array.make size 0.0

let render_demo demo =
  if not demo.destroyed then begin
    let total_width = Frame_buffer.width demo.frame in
    let total_height = Frame_buffer.height demo.frame in
    let header_height = 3 in
    let panel_height = total_height - header_height in
    let panel_width = (total_width - 3) / 2 in
    if panel_width >= 10 && panel_height >= 5 then begin
      expect_unit
        (Owned_buffer.fill_rect demo.buffer ~x:0 ~y:0 ~width:total_width
           ~height:total_height ~background:background_color);

      let left_size = panel_width * panel_height in
      let left_buffer = ensure_buffer demo.left_buffer left_size in
      demo.left_buffer <- Some left_buffer;
      for y = 0 to panel_height - 1 do
        for x = 0 to panel_width - 1 do
          Float.Array.set left_buffer (y * panel_width + x)
            (intensity demo ~x ~y ~width:panel_width ~height:panel_height
               ~time:demo.time)
        done
      done;
      expect_unit
        (Owned_buffer.draw_grayscale_buffer demo.buffer ~x:0 ~y:header_height
           ~intensities:left_buffer ~width:panel_width ~height:panel_height ());

      let right_x = panel_width + 3 in
      let supersampled_width = panel_width * 2 in
      let supersampled_height = panel_height * 2 in
      let right_size = supersampled_width * supersampled_height in
      let right_buffer = ensure_buffer demo.right_buffer right_size in
      demo.right_buffer <- Some right_buffer;
      for y = 0 to supersampled_height - 1 do
        for x = 0 to supersampled_width - 1 do
          Float.Array.set right_buffer (y * supersampled_width + x)
            (intensity demo ~x ~y ~width:supersampled_width
               ~height:supersampled_height ~time:demo.time)
        done
      done;
      expect_unit
        (Owned_buffer.draw_grayscale_buffer_supersampled demo.buffer ~x:right_x
           ~y:header_height ~intensities:right_buffer ~width:supersampled_width
           ~height:supersampled_height ());

      let divider_x = panel_width + 1 in
      for y = header_height to total_height - 1 do
        expect_unit
          (Owned_buffer.set_cell demo.buffer ~x:divider_x ~y ~character:124l
             ~foreground:divider_color ~background:background_color
             ~attributes:0l)
      done;

      expect_unit
        (Owned_buffer.fill_rect demo.buffer ~x:0 ~y:0 ~width:total_width
           ~height:header_height ~background:header_background);
      let left_label = "1:1 Standard" in
      let left_label_x = centered_offset panel_width (String.length left_label) in
      set_ascii_text demo.buffer ~screen_width:total_width
        ~screen_height:total_height ~x:left_label_x ~y:1 ~text:left_label
        ~foreground:label_color ~background:header_background;
      let right_label = "2x Supersampled" in
      let right_label_x = right_x + centered_offset panel_width (String.length right_label) in
      set_ascii_text demo.buffer ~screen_width:total_width
        ~screen_height:total_height ~x:right_label_x ~y:1 ~text:right_label
        ~foreground:highlight_color ~background:header_background;
      let info =
        Printf.sprintf "[%s] SPACE:pause P:pattern" pattern_names.(demo.pattern_mode)
      in
      let info_x = centered_offset total_width (String.length info) in
      set_ascii_text demo.buffer ~screen_width:total_width
        ~screen_height:total_height ~x:info_x ~y:0 ~text:info
        ~foreground:info_color ~background:header_background
    end
  end

let request_render demo = ignore (expect_ok (O.Renderer.request_render demo.renderer))

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    Option.iter O.Event_subscription.cancel demo.resize_subscription;
    Option.iter O.Renderer.detach_pre_render demo.pre_render;
    O.Renderer.release_live_lease demo.live_lease;
    ignore
      (expect_ok
         (O.Layout_children.remove (O.Renderer.children demo.renderer)
            (Frame_buffer.as_renderable demo.frame)));
    Frame_buffer.destroy demo.frame;
    demo.key_subscription <- None;
    demo.resize_subscription <- None;
    demo.pre_render <- None;
    demo.left_buffer <- None;
    demo.right_buffer <- None;
    demo.pattern_mode <- 0
  end

let handle_key demo key_event =
  if Handler.key_event_kind key_event = Handler.Keypress then begin
    let modifiers = Handler.key_modifiers key_event in
    if not modifiers.ctrl && not modifiers.meta then
      match Handler.key key_event with
      | Key.Named Key.Space ->
          demo.paused <- not demo.paused;
          request_render demo
      | Key.Character bytes
        when String.equal (String.lowercase_ascii (Bytes.to_string bytes)) "p" ->
          demo.pattern_mode <- (demo.pattern_mode + 1) mod Array.length pattern_names;
          request_render demo
      | Key.Named _ | Key.Character _ -> ()
  end

let run renderer =
  let width = Int32.to_int (expect_ok (O.Renderer.terminal_width renderer)) in
  let height = Int32.to_int (expect_ok (O.Renderer.terminal_height renderer)) in
  let frame =
    expect_ok
      (Frame_buffer.create (O.Renderer.context renderer) ~id:"grayscale-demo"
         ~width ~height ())
  in
  ignore
    (expect_ok
       (O.Layout_children.add (O.Renderer.children renderer)
          (Frame_buffer.as_renderable frame)));
  let live_lease = expect_ok (O.Renderer.acquire_live_lease renderer) in
  let demo =
    {
      renderer;
      frame;
      buffer = Frame_buffer.frame_buffer frame;
      time = 0.0;
      paused = false;
      pattern_mode = 0;
      left_buffer = None;
      right_buffer = None;
      live_lease;
      key_subscription = None;
      resize_subscription = None;
      pre_render = None;
      destroyed = false;
    }
  in
  let key_subscription =
    expect_ok (O.Renderer.on_keypress renderer (handle_key demo))
  in
  demo.key_subscription <- Some key_subscription;
  let resize_subscription =
    expect_ok
      (O.Renderer.on_resize renderer (fun { O.Renderer.width; height } ->
           expect_unit
             (Frame_buffer.resize demo.frame ~width:(Int32.to_int width)
                ~height:(Int32.to_int height));
           request_render demo))
  in
  demo.resize_subscription <- Some resize_subscription;
  let pre_render =
    expect_ok
      (O.Renderer.attach_pre_render renderer (fun delta_seconds ->
           if not demo.paused then demo.time <- demo.time +. (delta_seconds *. 0.8);
           render_demo demo))
  in
  demo.pre_render <- Some pre_render;
  ignore
    (expect_ok
       (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo)))

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~target_frames_per_second:30
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      ignore copy_to_clipboard;
      run renderer;
      Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
        ~on_ctrl_c:exit)
