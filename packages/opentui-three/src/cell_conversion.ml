(* Cell emission, ported from the reference supersampling.wgsl quadrant
   algorithm and canvas.ts readPixelsIntoBuffer.

   Color-space note (locked decision): pixels staged from the GPU are linear
   working space bytes; every color written into a terminal cell converts
   linear -> sRGB exactly once here. The reference instead truncates raw
   framebuffer bytes; the mid-gray unit test locks our value (linear 0.5
   encodes as byte 188, not 128). *)

let full_block = 0x2588l

let space = 0x20l

let srgb_channel v =
  if Float.compare v 0.0031308 <= 0 then v *. 12.92
  else (Float.pow v (1.0 /. 2.4) *. 1.055) -. 0.055

let linear_to_srgb_byte v =
  let clamped = Float.min 1.0 (Float.max 0.0 v) in
  Int.of_float ((srgb_channel clamped *. 255.0) +. 0.5)

let alpha_byte a =
  Int.of_float ((Float.min 1.0 (Float.max 0.0 a) *. 255.0) +. 0.5)

type pixel = {
  r : float;
  g : float;
  b : float;
  a : float;
}

let color_of p =
  match
    Opentui_core.Color.rgba ~red:(linear_to_srgb_byte p.r)
      ~green:(linear_to_srgb_byte p.g) ~blue:(linear_to_srgb_byte p.b)
      ~alpha:(alpha_byte p.a)
  with
  | Ok color -> color
  | Error _ -> invalid_arg "cell_conversion: channel out of range"

let pixel_count ~width ~height = width * height * 4

let sample snapshot ~width ~(x : int) ~(y : int) : pixel =
  (* Linear-channel floats straight from the staged rgba8unorm bytes. *)
  let base = ((y * width) + x) * 4 in
  { r = Float.of_int (Char.code snapshot.[base]) /. 255.0;
    g = Float.of_int (Char.code snapshot.[base + 1]) /. 255.0;
    b = Float.of_int (Char.code snapshot.[base + 2]) /. 255.0;
    a = Float.of_int (Char.code snapshot.[base + 3]) /. 255.0 }

let write_none ~(buffer : Opentui_core.Owned_buffer.t) ~snapshot ~width ~height :
    (unit, Opentui_core.Error.t) result =
  (* One rendered pixel becomes one full-block cell; alpha stays ignored,
     matching the reference None path. *)
  if String.length snapshot < pixel_count ~width ~height then
    invalid_arg "cell_conversion: snapshot smaller than declared dimensions";
  let rec rows y =
    if y >= height then Ok ()
    else begin
      let rec columns x =
        if x >= width then Ok ()
        else begin
          let p = sample snapshot ~width ~x ~y in
          match
            Opentui_core.Owned_buffer.set_cell_with_alpha_blending buffer ~x ~y
              ~character:full_block
              ~foreground:(color_of { p with a = 1.0 })
              ~background:Opentui_core.Color.black ~attributes:0l
          with
          | Ok () -> columns (x + 1)
          | Error _ as failure -> failure
        end
      in
      match columns 0 with
      | Ok () -> rows (y + 1)
      | Error _ as failure -> failure
    end
  in
  rows 0

(* --- Quadrant supersampling (Cpu mode; Gpu aliases Cpu until phase 2) --- *)

let quadrant_chars =
  [| 0x20l; 0x2597l; 0x2596l; 0x2584l; 0x259Dl; 0x2590l; 0x259El; 0x259Fl;
     0x2598l; 0x259Al; 0x258Cl; 0x2599l; 0x2580l; 0x259Cl; 0x259Bl; 0x2588l |]

let distance_squared a b =
  let dr = a.r -. b.r and dg = a.g -. b.g and db = a.b -. b.b in
  (dr *. dr) +. (dg *. dg) +. (db *. db)

let luminance p = (0.2126 *. p.r) +. (0.7152 *. p.g) +. (0.0722 *. p.b)

let blend_colors c1 c2 =
  (* Verbatim blendColors from supersampling.wgsl. *)
  let a1 = c1.a and a2 = c2.a in
  if Float.equal a1 0.0 && Float.equal a2 0.0 then { r = 0.0; g = 0.0; b = 0.0; a = 0.0 }
  else
    let out_alpha = a1 +. a2 -. (a1 *. a2) in
    if Float.equal out_alpha 0.0 then { r = 0.0; g = 0.0; b = 0.0; a = 0.0 }
    else
      { r = ((c1.r *. a1) +. (c2.r *. a2 *. (1.0 -. a1))) /. out_alpha;
        g = ((c1.g *. a1) +. (c2.g *. a2 *. (1.0 -. a1))) /. out_alpha;
        b = ((c1.b *. a1) +. (c2.b *. a2 *. (1.0 -. a1))) /. out_alpha;
        a = out_alpha }

let average_colors_with_alpha p0 p1 p2 p3 =
  blend_colors (blend_colors p0 p1) (blend_colors p2 p3)

let write_quadrants ~(buffer : Opentui_core.Owned_buffer.t) ~snapshot
    ~(output_width : int) ~(output_height : int) :
    (unit, Opentui_core.Error.t) result =
  (* Render dimensions are 2x the cell grid; each cell consumes one 2x2
     pixel block exactly as the compute pass does. *)
  let render_width = output_width * 2 and render_height = output_height * 2 in
  if
    String.length snapshot < pixel_count ~width:render_width ~height:render_height
  then invalid_arg "cell_conversion: snapshot smaller than declared dimensions";
  let order_dark_first p q =
    if Float.compare (luminance p) (luminance q) <= 0 then (p, q) else (q, p)
  in
  let rec rows cy =
    if cy >= output_height then Ok ()
    else begin
      let rec columns cx =
        if cx >= output_width then Ok ()
        else begin
          let rx = cx * 2 and ry = cy * 2 in
          let tl = sample snapshot ~width:render_width ~x:rx ~y:ry in
          let tr = sample snapshot ~width:render_width ~x:(rx + 1) ~y:ry in
          let bl = sample snapshot ~width:render_width ~x:rx ~y:(ry + 1) in
          let br = sample snapshot ~width:render_width ~x:(rx + 1) ~y:(ry + 1) in
          let pixels = [| tl; tr; bl; br |] in
          (* Most-distant pair; strict comparison keeps the first pair on
             ties, matching the WGSL scan order. *)
          let max_dist = ref (distance_squared tl tr) in
          let idx_a = ref 0 and idx_b = ref 1 in
          for i = 0 to 3 do
            for j = i + 1 to 3 do
              let d = distance_squared pixels.(i) pixels.(j) in
              if Float.compare d !max_dist > 0 then begin
                max_dist := d;
                idx_a := i;
                idx_b := j
              end
            done
          done;
          let chosen_dark, chosen_light =
            order_dark_first pixels.(!idx_a) pixels.(!idx_b)
          in
          let bit_values = [| 8; 4; 2; 1 |] in
          let bits = ref 0 in
          Array.iteri
            (fun i p ->
              if
                Float.compare
                  (distance_squared p chosen_dark)
                  (distance_squared p chosen_light)
                <= 0
              then bits := !bits lor bit_values.(i))
            pixels;
          let character, foreground, background =
            match !bits with
            | 0 ->
                (* All light: space glyph, dark candidate as ink over the
                   alpha-blended average. *)
                (space, chosen_dark, average_colors_with_alpha tl tr bl br)
            | 15 ->
                (* All dark: full block of the blended average over the light
                   candidate. *)
                ( full_block,
                  average_colors_with_alpha tl tr bl br,
                  chosen_light )
            | bits -> (quadrant_chars.(bits), chosen_dark, chosen_light)
          in
          match
            Opentui_core.Owned_buffer.set_cell_with_alpha_blending buffer ~x:cx
              ~y:cy ~character
              ~foreground:(color_of foreground)
              ~background:(color_of background)
              ~attributes:0l
          with
          | Ok () -> columns (cx + 1)
          | Error _ as failure -> failure
        end
      in
      match columns 0 with
      | Ok () -> rows (cy + 1)
      | Error _ as failure -> failure
    end
  in
  rows 0
