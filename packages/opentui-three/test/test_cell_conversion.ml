open Windtrap

module Three = Opentui_three.Three
module Cc = Three.Cell_conversion
module Owned_buffer = Opentui_core.Owned_buffer

let expect_ok what result =
  match result with
  | Ok value -> value
  | Error error -> fail (what ^ ": " ^ Opentui_core.Error.message error)

let make_buffer ~width ~height =
  expect_ok "buffer" (Owned_buffer.create ~width ~height ())

let rgb r g b =
  match Opentui_core.Color.rgb ~red:r ~green:g ~blue:b with
  | Ok color -> color
  | Error error -> fail ("color: " ^ Opentui_core.Native.Error.message error)

(* Compares the whole buffer against a probe whose single cell was written
   through the public API with expected values. Only valid for 1x1 buffers,
   which every quadrant fixture below uses; this pins exact glyph, color,
   and attribute encoding without depending on native snapshot layout. *)
let expect_single_cell ~character ~foreground ~background buffer =
  let probe = make_buffer ~width:1 ~height:1 in
  expect_ok "probe"
    (Owned_buffer.set_cell probe ~x:0 ~y:0 ~character ~foreground ~background
       ~attributes:0l);
  let actual = expect_ok "snapshot" (Owned_buffer.snapshot buffer) in
  let expected = expect_ok "probe snapshot" (Owned_buffer.snapshot probe) in
  let chars_actual, fore_actual, back_actual, attrs_actual = actual in
  let chars_expected, fore_expected, back_expected, attrs_expected = expected in
  Array.iteri
    (fun i expected_word ->
      if
        (not (Int32.equal expected_word chars_actual.(i)))
        || not (Int32.equal fore_expected.(i) fore_actual.(i))
        || not (Int32.equal back_expected.(i) back_actual.(i))
        || not (Int32.equal attrs_expected.(i) attrs_actual.(i))
      then fail "cell encoding diverged from the API-written expectation")
    chars_expected;
  Owned_buffer.close probe

let black_pixel_bytes = String.init 4 (fun i -> if Int.equal i 3 then '\255' else '\000')

let white_pixel_bytes = String.init 4 (fun _ -> '\255')

let () =
  run "opentui-three-cell-conversion"
    [
      test "linear-to-sRGB emission locks the mid-gray reference value"
        (fun () ->
          List.iter
            (fun (linear, expected) ->
              let actual = Cc.linear_to_srgb_byte linear in
              if Int.abs (actual - expected) > 1 then
                fail
                  (Printf.sprintf "linear %.6f encoded as %d, expected %d (+/-1)"
                     linear actual expected))
            [ (0.0, 0); (1.0, 255); (0.5, 188); (0.25, 137); (0.625, 207) ]);

      test "blend colors compose alpha-over exactly like the shader"
        (fun () ->
          let opaque = { Cc.r = 1.0; g = 1.0; b = 1.0; a = 1.0 } in
          let clear = { Cc.r = 0.0; g = 0.0; b = 0.0; a = 0.0 } in
          let half = { Cc.r = 1.0; g = 0.0; b = 0.0; a = 0.5 } in
          let blended = Cc.blend_colors half half in
          if
            Float.abs (blended.a -. 0.75) > 1e-9
            || Float.abs (blended.r -. 1.0) > 1e-9
          then fail "self-blend did not compose to alpha 3/4";
          let kept = Cc.blend_colors opaque clear in
          if Float.abs (kept.a -. 1.0) > 1e-9 || Float.abs (kept.r -. 1.0) > 1e-9
          then fail "transparent partner altered the base color");

      test "none mode writes one full-block cell per linear pixel" (fun () ->
          let buffer = make_buffer ~width:1 ~height:1 in
          (* One linear mid-gray pixel: byte 128/255 converts to sRGB 188. *)
          let snapshot =
            String.init 4 (fun i -> if Int.equal i 0 then '\128' else '\000')
          in
          expect_ok "write_none"
            (Cc.write_none ~buffer ~snapshot ~width:1 ~height:1);
          expect_single_cell buffer ~character:Cc.full_block
            ~foreground:(rgb 188 0 0)
            ~background:Opentui_core.Color.black;
          Owned_buffer.close buffer);

      test "quadrant mode classifies an all-dark block as a full block"
        (fun () ->
          let buffer = make_buffer ~width:1 ~height:1 in
          let snapshot = String.make 16 (Char.chr 64) in
          expect_ok "write_quadrants"
            (Cc.write_quadrants ~buffer ~snapshot ~output_width:1
               ~output_height:1);
          (* All-dark branch: full block of the alpha-blended average - four
             identical samples stay at linear 64/255, which emits as sRGB
             137 - over the light candidate, which equals the same sample. *)
          let average = rgb 137 137 137 in
          expect_single_cell buffer ~character:Cc.full_block
            ~foreground:average ~background:average;
          Owned_buffer.close buffer);

      test "quadrant mode picks glyphs by distance and luminance" (fun () ->
          let buffer = make_buffer ~width:1 ~height:1 in
          let snapshot =
            black_pixel_bytes ^ white_pixel_bytes ^ white_pixel_bytes
            ^ white_pixel_bytes
          in
          expect_ok "write_quadrants"
            (Cc.write_quadrants ~buffer ~snapshot ~output_width:1
               ~output_height:1);
          (* TL is the only dark quadrant: bit 8 selects U+2598, inked in the
             dark candidate over the light candidate. *)
          expect_single_cell buffer ~character:0x2598l ~foreground:(rgb 0 0 0)
            ~background:(rgb 255 255 255);
          Owned_buffer.close buffer);

      test "mixed quadrant blocks carry dark ink over the light candidate"
        (fun () ->
          let buffer = make_buffer ~width:1 ~height:1 in
          let snapshot =
            black_pixel_bytes ^ white_pixel_bytes ^ black_pixel_bytes
            ^ white_pixel_bytes
          in
          expect_ok "write_quadrants"
            (Cc.write_quadrants ~buffer ~snapshot ~output_width:1
               ~output_height:1);
          (* TL+BL dark -> bits 8+2 = 10 -> U+258C left half block. *)
          expect_single_cell buffer ~character:0x258Cl ~foreground:(rgb 0 0 0)
            ~background:(rgb 255 255 255);
          Owned_buffer.close buffer);

      test "luminance ordering decides which side holds the ink" (fun () ->
          let buffer = make_buffer ~width:1 ~height:1 in
          let dim_bytes =
            String.init 4 (fun i -> if Int.equal i 3 then '\255' else Char.chr 200)
          in
          let snapshot =
            white_pixel_bytes ^ dim_bytes ^ white_pixel_bytes ^ dim_bytes
          in
          expect_ok "write_quadrants"
            (Cc.write_quadrants ~buffer ~snapshot ~output_width:1
               ~output_height:1);
          (* Dim samples sit on the right and lose the luminance ordering,
             so they become the dark ink: TR+BR -> bits 5 -> U+2590 right
             half block. *)
          expect_single_cell buffer ~character:0x2590l ~foreground:(rgb 229 229 229)
            ~background:(rgb 255 255 255);
          Owned_buffer.close buffer);
    ]
