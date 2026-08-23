open Windtrap

module Wgpu = Opentui_wgpu.Wgpu


(* A missing or broken adapter is an environment property, not a code
   defect; such hosts skip loudly unless enforcement is requested via
   OPENTUI_WGPU_REQUIRE_DEVICE=1. See the three-renderer risk register,
   item 5, for the open aarch64-linux lavapipe question. *)
let take_device what result =
  match result with
  | Ok device -> device
  | Error error ->
      let message =
        "no usable WebGPU device for " ^ what ^ ": "
        ^ Wgpu.Error.message error
      in
      if Sys.getenv_opt "OPENTUI_WGPU_REQUIRE_DEVICE" = Some "1" then
        fail message
      else skip ~reason:message ()

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Wgpu.Error.message error)

type staging = {
  pixels :
    (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t;
}

let make_staging size =
  { pixels = Bigarray.Array1.create Bigarray.char Bigarray.c_layout size }

let expect_pixel ~row ~stride ~width ~column ~pixels ~expected =
  let base = (row * stride) + (column * 4) in
  List.iteri
    (fun index expected_byte ->
      let actual = Char.code (Bigarray.Array1.get pixels (base + index)) in
      if Int.abs (actual - expected_byte) > 1 then
        fail
          (Printf.sprintf
             "pixel row %d column %d channel %d: expected %d (+/-1), got %d"
             row column index expected_byte actual))
    expected

let () =
  run "opentui-wgpu-headless-roundtrip"
    [
      test "clears a render target and reads the exact pixels back" (fun () ->
                    let device = take_device "the headless round trip" (Wgpu.create_device ()) in
              (* Odd width on purpose: 61 * 4 = 244 bytes must pad to a
                 256-byte aligned stride, exercising copy-alignment handling. *)
              let width = 61 in
              let height = 33 in
              let stride = expect_ok (Ok (Wgpu.readback_stride ~width)) in
              if not (Int.equal stride 256) then
                fail (Printf.sprintf "expected padded stride 256, got %d" stride);
              let rows = height in
                            let target = expect_ok (Wgpu.create_render_target device ~width ~height) in
              let readback =
                expect_ok (Wgpu.create_readback device ~stride ~rows)
              in
              let staging = make_staging (Wgpu.readback_size readback) in
                            let red = 0.25 and green = 0.5 and blue = 0.75 in
              let color = Float.Array.make 4 0.0 in
              Float.Array.set color 0 red;
              Float.Array.set color 1 green;
              Float.Array.set color 2 blue;
              Float.Array.set color 3 1.0;
                            expect_ok
                (Wgpu.submit_clear_frame device ~target ~readback ~color ());
                                          expect_ok (Wgpu.map_read device readback);
                            expect_ok (Wgpu.copy_mapped readback staging.pixels);
                            Wgpu.unmap readback;
              expect_pixel ~row:0 ~stride ~width ~column:0
                ~pixels:staging.pixels ~expected:[ 64; 128; 191; 255 ];
              expect_pixel ~row:(height - 1) ~stride ~width ~column:(width - 1)
                ~pixels:staging.pixels ~expected:[ 64; 128; 191; 255 ];
              Wgpu.destroy_readback readback;
              Wgpu.destroy_render_target target;
              Wgpu.destroy_device device;
              (* Destroy paths are idempotent and closed objects reject work. *)
              Wgpu.destroy_readback readback;
              Wgpu.destroy_render_target target;
              (match Wgpu.create_render_target device ~width ~height with
              | Error (Closed _) -> ()
              | Error error -> fail ("expected Closed, got " ^ Wgpu.Error.message error)
              | Ok _ -> fail "expected Closed after destroy_device"));
      test "survives repeated frames without deadlock or drift" (fun () ->
          let device = take_device "repeated frames" (Wgpu.create_device ()) in
              let width = 16 and height = 8 in
              let stride = Wgpu.readback_stride ~width in
              let target =
                expect_ok (Wgpu.create_render_target device ~width ~height)
              in
              let readback =
                expect_ok (Wgpu.create_readback device ~stride ~rows:height)
              in
              let staging = make_staging (Wgpu.readback_size readback) in
              let frames = 30 in
              for frame = 0 to frames - 1 do
                let level = Float.of_int frame /. Float.of_int (frames - 1) in
                let color = Float.Array.make 4 0.0 in
                Float.Array.set color 0 level;
                Float.Array.set color 3 1.0;
                expect_ok
                  (Wgpu.submit_clear_frame device ~target ~readback ~color ());
                expect_ok (Wgpu.map_read device readback);
                expect_ok (Wgpu.copy_mapped readback staging.pixels);
                Wgpu.unmap readback;
                let expected_red = int_of_float ((level *. 255.0) +. 0.5) in
                if Int.abs
                     (Char.code (Bigarray.Array1.get staging.pixels 0)
                     - expected_red)
                   > 1 then
                  fail
                    (Printf.sprintf
                       "frame %d red channel drifted: expected %d (+/-1), got %d"
                       frame expected_red
                       (Char.code (Bigarray.Array1.get staging.pixels 0)))
              done;
              Wgpu.destroy_readback readback;
              Wgpu.destroy_render_target target;
              Wgpu.destroy_device device;
              if not (Wgpu.is_closed device) then fail "device should be closed");
      test "rejects invalid arguments and lifecycle misuse" (fun () ->
          let device = take_device "validation checks" (Wgpu.create_device ()) in
              let expect_error ~what result =
                match result with
                | Error _ -> ()
                | Ok _ -> fail (what ^ " unexpectedly succeeded")
              in
              let stride = Wgpu.readback_stride ~width:16 in
              let target = expect_ok (Wgpu.create_render_target device ~width:16 ~height:8) in
              let readback = expect_ok (Wgpu.create_readback device ~stride ~rows:8) in
              let staging = make_staging (Wgpu.readback_size readback) in
              let color = Float.Array.make 4 1.0 in
              expect_error ~what:"zero-width target"
                (Wgpu.create_render_target device ~width:0 ~height:8);
              expect_error ~what:"negative-height target"
                (Wgpu.create_render_target device ~width:16 ~height:(-1));
              expect_error ~what:"unaligned stride"
                (Wgpu.create_readback device ~stride:100 ~rows:8);
              expect_error ~what:"zero rows"
                (Wgpu.create_readback device ~stride ~rows:0);
              let narrow =
                expect_ok (Wgpu.create_readback device ~stride ~rows:8)
              in
              (* A 64-pixel row and any narrower row share the same
                 256-byte minimum stride, so only a wider target can make an
                 existing readback too small. *)
              let wide_target =
                expect_ok (Wgpu.create_render_target device ~width:128 ~height:8)
              in
              expect_error ~what:"readback too narrow for target"
                (Wgpu.submit_clear_frame device ~target:wide_target
                   ~readback:narrow ~color ());
              Wgpu.destroy_readback narrow;
              Wgpu.destroy_render_target wide_target;
              expect_error ~what:"short clear color"
                (Wgpu.submit_clear_frame device ~target ~readback
                   ~color:(Float.Array.make 3 1.0) ());
              expect_error ~what:"copy before map"
                (Wgpu.copy_mapped readback staging.pixels);
              expect_ok (Wgpu.map_read device readback);
              expect_error ~what:"double map"
                (Wgpu.map_read device readback);
              expect_error ~what:"undersized copy destination"
                (Wgpu.copy_mapped readback (make_staging 4).pixels);
              expect_ok (Wgpu.copy_mapped readback staging.pixels);
              (* destroy_readback while mapped unmaps before releasing. *)
              Wgpu.destroy_readback readback;
              Wgpu.destroy_readback readback;
              expect_error ~what:"map after destroy"
                (Wgpu.map_read device readback);
              expect_error ~what:"submit after destroy"
                (Wgpu.submit_clear_frame device ~target ~readback ~color ());
              Wgpu.destroy_render_target target;
              Wgpu.destroy_render_target target;
              Wgpu.destroy_device device;
      );

      test "draws an unlit triangle through a full pipeline" (fun () ->
          let device = take_device "pipeline draw" (Wgpu.create_device ()) in
          ignore (Wgpu.drain_diagnostics ~max:64 ());
          let width = 8 and height = 8 in
          let target =
            expect_ok (Wgpu.create_render_target device ~width ~height)
          in
          let stride = Wgpu.readback_stride ~width in
          let readback =
            expect_ok (Wgpu.create_readback device ~stride ~rows:height)
          in
          let staging = make_staging (Wgpu.readback_size readback) in

          let wgsl =
            {wgsl| struct Uniforms {
                      mvp : mat4x4<f32>,
                      model : mat4x4<f32>,
                      color : vec4<f32>,
                    };
                    @group(0) @binding(0) var<uniform> u : Uniforms;
                    struct VSOut {
                      @builtin(position) pos : vec4<f32>,
                      @location(0) normal : vec3<f32>,
                    };
                    @vertex fn vs_main(@location(0) pos : vec3<f32>,
                                       @location(1) nrm : vec3<f32>) -> VSOut {
                      var out : VSOut;
                      out.pos = u.mvp * vec4<f32>(pos, 1.0);
                      out.normal = nrm;
                      return out;
                    }
                    @fragment fn fs_main(in : VSOut) -> @location(0) vec4<f32> {
                      return u.color;
                    }
                    |wgsl}
          in
          let shader =
            expect_ok (Wgpu.create_shader_module device ~wgsl)
          in
          let bgl = expect_ok (Wgpu.create_uniform_bind_group_layout device) in
          let playout = expect_ok (Wgpu.create_pipeline_layout device bgl) in
          let pipeline =
            expect_ok
              (Wgpu.create_render_pipeline device ~layout:playout ~shader
                 ~vs_entry:"vs_main" ~fs_entry:"fs_main"
                 ~target_format:Wgpu.texture_format_rgba8_unorm)
          in

          let vertices =
            Float.Array.of_list
              [ -1.0; -1.0; 0.2;  0.0; 1.0; 0.0;
                 3.0; -1.0; 0.2;  0.0; 1.0; 0.0;
                -1.0;  3.0; 0.2;  0.0; 1.0; 0.0 ]
          in
          let indices = [| 0; 1; 2 |] in
          let vertex_bytes = Wgpu.pack_f32_le vertices in
          let index_bytes = Wgpu.pack_indices_u16 indices in
          let vertex_buffer =
            expect_ok
              (Wgpu.create_buffer device
                 ~size:(String.length vertex_bytes)
                 ~usage:(Int64.logor Wgpu.buffer_usage_vertex
                           Wgpu.buffer_usage_copy_destination))
          in
          let index_buffer =
            expect_ok
              (Wgpu.create_buffer device
                 ~size:(Wgpu.align4 (String.length index_bytes))
                 ~usage:(Int64.logor Wgpu.buffer_usage_index
                           Wgpu.buffer_usage_copy_destination))
          in
          let uniform_size = 160 in
          let uniform_buffer =
            expect_ok
              (Wgpu.create_buffer device ~size:uniform_size
                 ~usage:(Int64.logor Wgpu.buffer_usage_uniform
                           Wgpu.buffer_usage_copy_destination))
          in
          expect_ok
            (Wgpu.write_buffer_string device vertex_buffer ~offset:0
               vertex_bytes);
          expect_ok
            (Wgpu.write_buffer_string device index_buffer ~offset:0
               index_bytes);

          let identity =
            [| 1.0; 0.0; 0.0; 0.0; 0.0; 1.0; 0.0; 0.0;
               0.0; 0.0; 1.0; 0.0; 0.0; 0.0; 0.0; 1.0 |]
          in
          let uniforms = Float.Array.make 40 0.0 in
          Array.iteri (fun i v -> Float.Array.set uniforms i v) identity;
          Array.iteri
            (fun i v -> Float.Array.set uniforms (16 + i) v)
            identity;
          (* color vec4 at byte offset 128 = float slot 32 *)
          Float.Array.set uniforms 32 1.0;
          Float.Array.set uniforms 33 0.25;
          Float.Array.set uniforms 34 0.5;
          Float.Array.set uniforms 35 1.0;
          expect_ok
            (Wgpu.write_buffer_string device uniform_buffer ~offset:0
               (Wgpu.pack_f32_le uniforms));
          let group =
            expect_ok
              (Wgpu.create_uniform_bind_group device bgl uniform_buffer
                 ~size:uniform_size)
          in

          expect_ok
            (Wgpu.submit_draw_frame device ~target ~readback
               ~clear:(0.0, 0.0, 0.0, 1.0)
               ~draw:
                 { pipeline;
                   group;
                   vertex_buffer;
                   vertex_size = String.length vertex_bytes;
                   index_buffer;
                   index_size = String.length index_bytes;
                   index_count = Array.length indices }
               ());
          expect_ok (Wgpu.map_read device readback);
          expect_ok (Wgpu.copy_mapped readback staging.pixels);
          Wgpu.unmap readback;

          (* unlit red through identity transforms *)
          expect_pixel ~row:(height / 2) ~stride ~width
            ~column:(width / 2) ~pixels:staging.pixels
            ~expected:[ 255; 64; 128; 255 ];
          (* full-screen triangle covers every cell of the target *)
          expect_pixel ~row:0 ~stride ~width ~column:(width - 1)
            ~pixels:staging.pixels ~expected:[ 255; 64; 128; 255 ];

          if List.exists
               (fun line ->
                 String.length line >= 18
                 && String.sub line 0 18 = "uncaptured gpu err")
               (Wgpu.drain_diagnostics ())
          then fail "uncaptured GPU errors were recorded";

          Wgpu.destroy_bind_group group;
          Wgpu.destroy_bind_group_layout bgl;
          Wgpu.destroy_pipeline_layout playout;
          Wgpu.destroy_shader_module shader;
          Wgpu.destroy_render_pipeline pipeline;
          Wgpu.destroy_buffer vertex_buffer;
          Wgpu.destroy_buffer index_buffer;
          Wgpu.destroy_buffer uniform_buffer;
          Wgpu.destroy_readback readback;
          Wgpu.destroy_render_target target;
          Wgpu.destroy_device device);
    ]
