open Windtrap

module Wgpu = Opentui_wgpu.Wgpu


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
                    match Wgpu.create_device () with
          | Error error ->
              fail ("no usable WebGPU device for the headless round trip: "
                   ^ Wgpu.Error.message error)
          | Ok device ->
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
          match Wgpu.create_device () with
          | Error error ->
              fail ("no usable WebGPU device for repeated frames: "
                   ^ Wgpu.Error.message error)
          | Ok device ->
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
          match Wgpu.create_device () with
          | Error error ->
              fail ("no usable WebGPU device for validation checks: "
                   ^ Wgpu.Error.message error)
          | Ok device ->
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
    ]
