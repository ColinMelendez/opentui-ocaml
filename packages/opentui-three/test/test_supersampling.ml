open Windtrap

module Three = Opentui_three.Three
module Cc = Three.Cell_conversion
module Wgpu = Opentui_wgpu.Wgpu
module Owned_buffer = Opentui_core.Owned_buffer

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

let expect_ok what result =
  match result with Ok value -> value | Error error -> fail (what ^ ": " ^ Wgpu.Error.message error)

let core_ok what result =
  match result with
  | Ok value -> value
  | Error error -> fail (what ^ ": " ^ Opentui_core.Error.message error)

(* Builds a stride-padded fixture: byte = f x y per rgba channel. *)
let make_fixture ~width ~height channel =
  let stride = Wgpu.readback_stride ~width in
  let data = Bytes.make (stride * height) '\000' in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let base = (y * stride) + (x * 4) in
      Bytes.set data base (Char.chr (channel ~x ~y 0 land 0xff));
      Bytes.set data (base + 1) (Char.chr (channel ~x ~y 1 land 0xff));
      Bytes.set data (base + 2) (Char.chr (channel ~x ~y 2 land 0xff));
      Bytes.set data (base + 3) (Char.chr (channel ~x ~y 3 land 0xff))
    done
  done;
  (Bytes.to_string data, stride)

let stripped ~width ~height padded_data ~stride =
  let row_bytes = width * 4 in
  let out = Bytes.create (row_bytes * height) in
  for y = 0 to height - 1 do
    for column = 0 to row_bytes - 1 do
      Bytes.set out ((y * row_bytes) + column)
        padded_data.[(y * stride) + column]
    done
  done;
  Bytes.to_string out

let snapshots_equal (a, b) =
  let ca, fa, ba, aa = a and cb, fb, bb, ab = b in
  Array.for_all2 Int32.equal ca cb
  && Array.for_all2 Int32.equal fa fb
  && Array.for_all2 Int32.equal ba bb
  && Array.for_all2 Int32.equal aa ab

(* Runs both paths over one fixture and fails unless the cells agree
   bit-for-bit. *)
let expect_oracle_match ~label ~channel ~width ~height =
  let padded, stride = make_fixture ~width ~height channel in
  let device = take_device label (Wgpu.create_device ()) in
  ignore (Wgpu.drain_diagnostics ~max:64 ());
  let engine = expect_ok "engine" (Three.Engine.create ~width ~height ()) in
  expect_ok "set gpu mode" (Three.Engine.set_super_sample engine `Gpu);
  expect_ok "upload" (Three.Engine.upload_frame engine ~data:padded ~bytes_per_row:stride);
  ignore (Wgpu.drain_diagnostics ~max:64 ());
  (* The pixel readback path is bypassed in Gpu mode; stage runs the
     compute pass and stages cell records. *)
  expect_ok "stage" (Three.Engine.stage engine);
  let records = Three.Engine.last_cells engine in

  let cpu_buffer =
    core_ok "cpu buffer"
      (Owned_buffer.create ~width:(width / 2) ~height:(height / 2) ())
  in
  core_ok "cpu write"
    (Cc.write_quadrants ~buffer:cpu_buffer
       ~snapshot:(stripped ~width ~height padded ~stride)
       ~output_width:(width / 2) ~output_height:(height / 2)
       ~render_width:width ~render_height:height ());

  let gpu_buffer =
    core_ok "gpu buffer"
      (Owned_buffer.create ~width:(width / 2) ~height:(height / 2) ())
  in
  let grid_width, _ = Three.Engine.last_cell_grid engine in
  core_ok "gpu write"
    (Cc.write_gpu_records ~buffer:gpu_buffer ~records
       ~output_width:(width / 2) ~output_height:(height / 2)
       ~record_pitch:grid_width);

  let cpu_snapshot = core_ok "cpu snapshot" (Owned_buffer.snapshot cpu_buffer) in
  let gpu_snapshot = core_ok "gpu snapshot" (Owned_buffer.snapshot gpu_buffer) in
  if not (snapshots_equal (cpu_snapshot, gpu_snapshot)) then begin
    let ca, _, _, _ = cpu_snapshot and cb, _, _, _ = gpu_snapshot in
    let dump prefix arr =
      String.concat " "
        (Array.to_list
           (Array.mapi
              (fun i w -> Printf.sprintf "%s[%d]=%08lx" prefix i w)
              arr))
    in
    fail
      (label ^ ": GPU cells diverged\nCPU: " ^ dump "c" ca ^ "\nGPU: "
       ^ dump "c" cb)
  end;

  Owned_buffer.close cpu_buffer;
  Owned_buffer.close gpu_buffer;
  Three.Engine.destroy engine;
  Wgpu.destroy_device device

let () =
  run "opentui-three-supersampling-oracle"
    [
      test "flat frames classify as full blocks identically" (fun () ->
          expect_oracle_match ~label:"flat"
            ~channel:(fun ~x:_ ~y:_ c -> if Int.equal c 3 then 255 else 96)
            ~width:16 ~height:8);

      test "gradient frames produce identical mixed glyphs" (fun () ->
          expect_oracle_match ~label:"gradient"
            ~channel:(fun ~x ~y c -> ((x * 17) + (y * 31) + (c * 61)) mod 256)
            ~width:16 ~height:8);

      test "checkerboard frames agree on every quadrant" (fun () ->
          expect_oracle_match ~label:"checker"
            ~channel:(fun ~x ~y _c ->
                if Int.equal (((x / 2) + (y / 2)) land 1) 0 then 250 else 6)
            ~width:32 ~height:16);

      test "alpha variation exercises the blend math identically" (fun () ->
          expect_oracle_match ~label:"alpha"
            ~channel:(fun ~x ~y c ->
                if Int.equal c 3 then (64 + (x * 5)) mod 256
                else (128 + y) mod 256)
            ~width:16 ~height:8);

      test "odd widths hit the out-of-bounds guard identically" (fun () ->
          expect_oracle_match ~label:"odd"
            ~channel:(fun ~x ~y c -> ((x * 23) + (y * 41) + c) mod 256)
            ~width:7 ~height:4);

      test "repeated runs are deterministic" (fun () ->
          let channel ~x ~y c = ((x * 11) + (y * 29) + c) mod 256 in
          let padded, stride = make_fixture ~width:16 ~height:8 channel in
          let device = take_device "determinism" (Wgpu.create_device ()) in
          let run_once () =
            let engine = expect_ok "engine" (Three.Engine.create ~width:16 ~height:8 ()) in
            expect_ok "mode" (Three.Engine.set_super_sample engine `Gpu);
            expect_ok "upload"
              (Three.Engine.upload_frame engine ~data:padded ~bytes_per_row:stride);
            expect_ok "stage" (Three.Engine.stage engine);
            let records = Three.Engine.last_cells engine in
            Three.Engine.destroy engine;
            records
          in
          let first = run_once () and second = run_once () in
          if not (String.equal first second) then
            fail "compute pass produced different records across runs";
          Wgpu.destroy_device device);
    ]
