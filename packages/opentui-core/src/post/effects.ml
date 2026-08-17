let finite value = Float.is_finite value

let dimensions buffer =
  Result.bind (Buffer.width buffer) (fun width ->
      Result.map (fun height ->
          (Int32.to_int width, Int32.to_int height))
        (Buffer.height buffer))

let clamp_unit value = Float.max 0.0 (Float.min 1.0 value)

let byte word = Int32.to_int (Int32.logand word 0xffl)

let channel colors index = float_of_int (byte colors.(index)) /. 255.0

let set_channel colors index value =
  let scaled = int_of_float (Float.round (clamp_unit value *. 255.0)) in
  let low = Int32.of_int (max 0 (min 255 scaled)) in
  colors.(index) <- Int32.logor (Int32.logand colors.(index) 0xffffff00l) low

let set_rgb colors index red green blue =
  set_channel colors index red;
  set_channel colors (index + 1) green;
  set_channel colors (index + 2) blue

let with_snapshot buffer operation =
  Result.bind (Buffer.snapshot buffer) (fun snapshot ->
      operation snapshot;
      Buffer.restore buffer snapshot)

let zero_matrix : floatarray =
  [| 0.0; 0.0; 0.0; 0.0;
     0.0; 0.0; 0.0; 0.0;
     0.0; 0.0; 0.0; 0.0;
     0.0; 0.0; 0.0; 0.0 |]

module Distortion_effect = struct
  type glitch = Shift of int * int | Flip of int | Color of int * int * int

  type t = {
    mutable glitch_chance_per_second : float;
    mutable max_glitch_lines : int;
    mutable min_glitch_duration : float;
    mutable max_glitch_duration : float;
    mutable max_shift_amount : int;
    mutable shift_flip_ratio : float;
    mutable color_glitch_chance : float;
    mutable last_glitch_time : float;
    mutable glitch_duration : float;
    mutable active_glitches : glitch list;
    mutable seed : int64;
  }

  let nonnegative value = Float.max 0.0 value
  let ratio value = clamp_unit value

  let create ?(glitch_chance_per_second = 0.5) ?(max_glitch_lines = 3)
      ?(min_glitch_duration = 0.05) ?(max_glitch_duration = 0.2)
      ?(max_shift_amount = 10) ?(shift_flip_ratio = 0.6)
      ?(color_glitch_chance = 0.2) () =
    {
      glitch_chance_per_second = nonnegative glitch_chance_per_second;
      max_glitch_lines = max 0 max_glitch_lines;
      min_glitch_duration = nonnegative min_glitch_duration;
      max_glitch_duration = nonnegative max_glitch_duration;
      max_shift_amount = max 0 max_shift_amount;
      shift_flip_ratio = ratio shift_flip_ratio;
      color_glitch_chance = ratio color_glitch_chance;
      last_glitch_time = 0.0;
      glitch_duration = 0.0;
      active_glitches = [];
      seed = 0x1234abcdL;
    }

  let glitch_chance_per_second value = value.glitch_chance_per_second
  let set_glitch_chance_per_second value next = value.glitch_chance_per_second <- nonnegative next
  let max_glitch_lines value = value.max_glitch_lines
  let set_max_glitch_lines value next = value.max_glitch_lines <- max 0 next
  let min_glitch_duration value = value.min_glitch_duration
  let set_min_glitch_duration value next = value.min_glitch_duration <- nonnegative next
  let max_glitch_duration value = value.max_glitch_duration
  let set_max_glitch_duration value next = value.max_glitch_duration <- nonnegative next
  let max_shift_amount value = value.max_shift_amount
  let set_max_shift_amount value next = value.max_shift_amount <- max 0 next
  let shift_flip_ratio value = value.shift_flip_ratio
  let set_shift_flip_ratio value next = value.shift_flip_ratio <- ratio next
  let color_glitch_chance value = value.color_glitch_chance
  let set_color_glitch_chance value next = value.color_glitch_chance <- ratio next

  let next_unit value =
    value.seed <-
      Int64.logand
        (Int64.add (Int64.mul value.seed 6364136223846793005L) 1442695040888963407L)
        0x7fffffffffffffffL;
    Int64.to_float value.seed /. Int64.to_float 0x7fffffffffffffffL

  let distinct_line lines line =
    not (List.exists (fun value -> Int.equal value line) lines)

  let make_glitches value ~width ~height =
    if width <= 0 || height <= 0 || value.max_glitch_lines <= 0 then []
    else
      let lines = ref [] in
      let result = ref [] in
      let attempts = ref 0 in
      while List.length !result < value.max_glitch_lines && !attempts < value.max_glitch_lines * 4 do
        let line = int_of_float (next_unit value *. float_of_int height) in
        if distinct_line !lines line then begin
          lines := line :: !lines;
          let type_roll = next_unit value in
          if Float.compare type_roll value.color_glitch_chance < 0 then begin
            let start = int_of_float (next_unit value *. float_of_int width) in
            let remaining = max 1 (width - start) in
            let length = 1 + int_of_float (next_unit value *. float_of_int remaining) in
            result := Color (line, start, min remaining length) :: !result
          end else if
            Float.compare
              ((type_roll -. value.color_glitch_chance)
               /. Float.max 0.000001 (1.0 -. value.color_glitch_chance))
              value.shift_flip_ratio < 0
          then
            let amount =
              int_of_float
                ((next_unit value *. 2.0 -. 1.0)
                 *. float_of_int value.max_shift_amount)
            in
            result := Shift (line, amount) :: !result
          else result := Flip line :: !result
        end;
        attempts := !attempts + 1
      done;
      !result

  let apply_glitches glitches ~width ~height foreground background characters attributes =
    List.iter
      (function
        | Flip y when y >= 0 && y < height ->
            let first = y * width in
            let chars = Array.sub characters first width in
            let attrs = Array.sub attributes first width in
            let fg = Array.sub foreground (first * 4) (width * 4) in
            let bg = Array.sub background (first * 4) (width * 4) in
            for x = 0 to width - 1 do
              let source = width - 1 - x in
              characters.(first + x) <- chars.(source);
              attributes.(first + x) <- attrs.(source);
              for channel_index = 0 to 3 do
                foreground.((first + x) * 4 + channel_index) <- fg.(source * 4 + channel_index);
                background.((first + x) * 4 + channel_index) <- bg.(source * 4 + channel_index)
              done
            done
        | Shift (y, amount) when y >= 0 && y < height && width > 0 ->
            let first = y * width in
            let chars = Array.sub characters first width in
            let attrs = Array.sub attributes first width in
            let fg = Array.sub foreground (first * 4) (width * 4) in
            let bg = Array.sub background (first * 4) (width * 4) in
            let normalized = ((amount mod width) + width) mod width in
            for x = 0 to width - 1 do
              let source = (x - normalized + width) mod width in
              characters.(first + x) <- chars.(source);
              attributes.(first + x) <- attrs.(source);
              for channel_index = 0 to 3 do
                foreground.((first + x) * 4 + channel_index) <- fg.(source * 4 + channel_index);
                background.((first + x) * 4 + channel_index) <- bg.(source * 4 + channel_index)
              done
            done
        | Color (y, start, length) when y >= 0 && y < height ->
            let first = y * width in
            for x = max 0 start to min width (start + length) - 1 do
              let cell = (first + x) * 4 in
              let value = float_of_int ((x + y) mod 3) /. 2.0 in
              set_rgb foreground cell value (1.0 -. value) 1.0;
              set_rgb background cell (1.0 -. value) value 0.5
            done
        | Flip _ | Shift _ | Color _ -> ())
      glitches

  let apply value buffer ~delta_time =
    if not (finite delta_time) || Float.compare delta_time 0.0 < 0 then
      Error Error.Invalid_argument
    else
      Result.bind (dimensions buffer) (fun (width, height) ->
          value.last_glitch_time <- value.last_glitch_time +. delta_time;
          let has_active_glitches =
            match value.active_glitches with [] -> false | _ -> true
          in
          if has_active_glitches
             && Float.compare value.last_glitch_time value.glitch_duration >= 0
          then begin
            value.active_glitches <- [];
            value.glitch_duration <- 0.0
          end;
          let has_active_glitches =
            match value.active_glitches with [] -> false | _ -> true
          in
          if not has_active_glitches
             && value.max_glitch_lines > 0
             && (Float.compare value.glitch_chance_per_second 1.0 >= 0
                 || Float.compare (next_unit value)
                      (value.glitch_chance_per_second *. delta_time) < 0)
          then begin
            value.last_glitch_time <- 0.0;
            value.glitch_duration <-
              value.min_glitch_duration
              +. next_unit value
                 *. Float.max 0.0 (value.max_glitch_duration -. value.min_glitch_duration);
            value.active_glitches <- make_glitches value ~width ~height
          end;
          (match value.active_glitches with
          | [] -> Ok ()
          | glitches ->
              with_snapshot buffer
                (fun (characters, foreground, background, attributes) ->
                  apply_glitches glitches ~width ~height foreground background
                    characters attributes)))
end

module Vignette_effect = struct
  type t = { mutable strength : float }

  let create ?(strength = 0.5) () = { strength = Float.max 0.0 strength }
  let strength value = value.strength
  let set_strength value next = value.strength <- Float.max 0.0 next

  let apply value buffer =
    if not (finite value.strength) then Error Error.Invalid_argument
    else
      Result.bind (dimensions buffer) (fun (width, height) ->
          let values = Float.Array.make (width * height * 3) 0.0 in
          let center_x = float_of_int width /. 2.0 in
          let center_y = float_of_int height /. 2.0 in
          let denominator = center_x *. center_x +. center_y *. center_y in
          let denominator = if Float.compare denominator 0.0 = 0 then 1.0 else denominator in
          let index = ref 0 in
          for y = 0 to height - 1 do
            for x = 0 to width - 1 do
              let dx = float_of_int x -. center_x in
              let dy = float_of_int y -. center_y in
              let attenuation =
                Float.min 1.0 ((dx *. dx +. dy *. dy) /. denominator)
                *. value.strength
              in
              Float.Array.set values !index (float_of_int x);
              Float.Array.set values (!index + 1) (float_of_int y);
              Float.Array.set values (!index + 2) attenuation;
              index := !index + 3
            done
          done;
          Buffer.color_matrix buffer ~matrix:zero_matrix ~cell_mask:values
            ~strength:1.0 ~target:Buffer.Both)
end

let perlin_permutation =
  [| 151; 160; 137; 91; 90; 15; 131; 13; 201; 95; 96; 53; 194; 233; 7; 225;
     140; 36; 103; 30; 69; 142; 8; 99; 37; 240; 21; 10; 23; 190; 6; 148;
     247; 120; 234; 75; 0; 26; 197; 62; 94; 252; 219; 203; 117; 35; 11; 32;
     57; 177; 33; 88; 237; 149; 56; 87; 174; 20; 125; 136; 171; 168; 68;
     175; 74; 165; 71; 134; 139; 48; 27; 166; 77; 146; 158; 231; 83; 111;
     229; 122; 60; 211; 133; 230; 220; 105; 92; 41; 55; 46; 245; 40; 244;
     102; 143; 54; 65; 25; 63; 161; 1; 216; 80; 73; 209; 76; 132; 187; 208;
     89; 18; 169; 200; 196; 135; 130; 116; 188; 159; 86; 164; 100; 109; 198;
     173; 186; 3; 64; 52; 217; 226; 250; 124; 123; 5; 202; 38; 147; 118; 126;
     255; 82; 85; 212; 207; 206; 59; 227; 47; 16; 58; 17; 182; 189; 28; 42;
     223; 183; 170; 213; 119; 248; 152; 2; 44; 154; 163; 70; 221; 153; 101;
     155; 167; 43; 172; 9; 129; 22; 39; 253; 19; 98; 108; 110; 79; 113; 224;
     232; 178; 185; 112; 104; 218; 246; 97; 228; 251; 34; 242; 193; 238; 210;
     144; 12; 191; 179; 162; 241; 81; 51; 145; 235; 249; 14; 239; 107; 49;
     192; 214; 31; 181; 199; 106; 157; 184; 84; 204; 176; 115; 121; 50; 45;
     127; 4; 150; 254; 138; 236; 205; 93; 222; 114; 67; 29; 24; 72; 243; 141;
     128; 195; 78; 66; 215; 61; 156; 180 |]

let perlin_gradients =
  [| 1, 1, 0; -1, 1, 0; 1, -1, 0; -1, -1, 0;
     1, 0, 1; -1, 0, 1; 1, 0, -1; -1, 0, -1;
     0, 1, 1; 0, -1, 1; 0, 1, -1; 0, -1, -1 |]

let perlin_at x y z =
  let floor_x = floor x in
  let floor_y = floor y in
  let floor_z = floor z in
  let unit_x = x -. floor_x in
  let unit_y = y -. floor_y in
  let unit_z = z -. floor_z in
  let coordinate value =
    let value = int_of_float value mod 256 in
    if value < 0 then value + 256 else value
  in
  let xi = coordinate floor_x in
  let yi = coordinate floor_y in
  let zi = coordinate floor_z in
  let permutation index = perlin_permutation.(index mod 256) in
  let gradient hash dx dy dz =
    let gx, gy, gz = perlin_gradients.(hash mod 12) in
    float_of_int gx *. dx +. float_of_int gy *. dy +. float_of_int gz *. dz
  in
  let fade value = value *. value *. value *. (value *. (value *. 6.0 -. 15.0) +. 10.0) in
  let mix left right amount = left +. (right -. left) *. amount in
  let u = fade unit_x in
  let v = fade unit_y in
  let w = fade unit_z in
  let a = permutation (permutation xi + yi) in
  let aa = permutation (a + zi) in
  let ab = permutation (a + 1 + zi) in
  let b = permutation (permutation (xi + 1) + yi) in
  let ba = permutation (b + zi) in
  let bb = permutation (b + 1 + zi) in
  let x1 =
    mix
      (gradient (permutation aa) unit_x unit_y unit_z)
      (gradient (permutation ba) (unit_x -. 1.0) unit_y unit_z) u
  in
  let x2 =
    mix
      (gradient (permutation ab) unit_x (unit_y -. 1.0) unit_z)
      (gradient (permutation bb) (unit_x -. 1.0) (unit_y -. 1.0) unit_z) u
  in
  let y1 = mix x1 x2 v in
  let x3 =
    mix
      (gradient (permutation (aa + 1)) unit_x unit_y (unit_z -. 1.0))
      (gradient (permutation (ba + 1)) (unit_x -. 1.0) unit_y (unit_z -. 1.0)) u
  in
  let x4 =
    mix
      (gradient (permutation (ab + 1)) unit_x (unit_y -. 1.0) (unit_z -. 1.0))
      (gradient (permutation (bb + 1)) (unit_x -. 1.0) (unit_y -. 1.0)
         (unit_z -. 1.0)) u
  in
  mix y1 (mix x3 x4 v) w

let fractal_noise ~x ~y ~time ~scale ~octaves ~z_scale ~y_scale =
  let total = ref 0.0 in
  let amplitude = ref 1.0 in
  let frequency = ref 1.0 in
  let maximum = ref 0.0 in
  for _octave = 0 to octaves - 1 do
    let nx = (float_of_int x *. scale *. !frequency +. time) *. 0.5 in
    let ny = float_of_int y *. scale *. !frequency *. y_scale *. 0.5 in
    let nz = time *. z_scale in
    total := !total +. perlin_at nx ny nz *. !amplitude;
    maximum := !maximum +. !amplitude;
    amplitude := !amplitude *. 0.5;
    frequency := !frequency *. 2.0
  done;
  if Float.compare !maximum 0.0 = 0 then 0.5
  else (!total /. !maximum +. 1.0) *. 0.5

module Clouds_effect = struct
  type t = {
    mutable scale : float;
    mutable speed : float;
    mutable density : float;
    mutable darkness : float;
    mutable time : float;
  }

  let create ?(scale = 0.02) ?(speed = 0.5) ?(density = 0.6)
      ?(darkness = 0.7) () =
    {
      scale = Float.max 0.001 scale;
      speed = Float.max 0.0 speed;
      density = clamp_unit density;
      darkness = clamp_unit darkness;
      time = 0.0;
    }

  let scale value = value.scale
  let set_scale value next = value.scale <- Float.max 0.001 next
  let speed value = value.speed
  let set_speed value next = value.speed <- Float.max 0.0 next
  let density value = value.density
  let set_density value next = value.density <- clamp_unit next
  let darkness value = value.darkness
  let set_darkness value next = value.darkness <- clamp_unit next

  let apply value buffer ~delta_time =
    if not (finite delta_time) || Float.compare delta_time 0.0 < 0 then
      Error Error.Invalid_argument
    else
      Result.bind (dimensions buffer) (fun (width, height) ->
          value.time <- value.time +. delta_time *. value.speed;
          let values = Float.Array.make (width * height * 3) 0.0 in
          let index = ref 0 in
          for y = 0 to height - 1 do
            for x = 0 to width - 1 do
              let noise =
                fractal_noise ~x ~y ~time:value.time ~scale:value.scale
                  ~octaves:4 ~z_scale:0.3 ~y_scale:1.0
              in
              let cloud = Float.max 0.0 (noise -. (1.0 -. value.density)) in
              Float.Array.set values !index (float_of_int x);
              Float.Array.set values (!index + 1) (float_of_int y);
              Float.Array.set values (!index + 2) (cloud *. value.darkness);
              index := !index + 3
            done
          done;
          Buffer.color_matrix buffer ~matrix:zero_matrix ~cell_mask:values
            ~strength:1.0 ~target:Buffer.Background)
end

module Flames_effect = struct
  type t = {
    mutable scale : float;
    mutable speed : float;
    mutable intensity : float;
    mutable time : float;
  }

  let create ?(scale = 0.03) ?(speed = 0.02) ?(intensity = 0.8) () =
    {
      scale = Float.max 0.001 scale;
      speed = Float.max 0.0 speed;
      intensity = clamp_unit intensity;
      time = 0.0;
    }

  let scale value = value.scale
  let set_scale value next = value.scale <- Float.max 0.001 next
  let speed value = value.speed
  let set_speed value next = value.speed <- Float.max 0.0 next
  let intensity value = value.intensity
  let set_intensity value next = value.intensity <- clamp_unit next

  let apply value buffer ~delta_time =
    if not (finite delta_time) || Float.compare delta_time 0.0 < 0 then
      Error Error.Invalid_argument
    else
      Result.bind (dimensions buffer) (fun (width, height) ->
          value.time <- value.time +. delta_time *. value.speed;
          with_snapshot buffer (fun (_characters, _foreground, background, _attributes) ->
              for y = 0 to height - 1 do
                let height_factor = 1.0 -. float_of_int y /. float_of_int (max 1 height) in
                for x = 0 to width - 1 do
                  let noise =
                    fractal_noise ~x ~y:(height - y) ~time:(value.time *. 2.0)
                      ~scale:value.scale ~octaves:3 ~z_scale:1.0 ~y_scale:2.0
                  in
                  let flame = noise *. height_factor *. value.intensity in
                  if Float.compare flame 0.0 > 0 then begin
                    let red, green, blue =
                      if Float.compare flame 0.7 > 0 then
                        (1.0, 1.0, Float.min 1.0 (0.3 +. (flame -. 0.7) *. 2.3))
                      else if Float.compare flame 0.4 > 0 then
                        (1.0, 0.5 +. (flame -. 0.4) *. 1.67, 0.0)
                      else (0.3 +. flame *. 1.75, flame *. 0.5, 0.0)
                    in
                    let color = (y * width + x) * 4 in
                    set_rgb background color
                      (Float.max (channel background color) (red *. flame))
                      (Float.max (channel background (color + 1)) (green *. flame))
                      (Float.max (channel background (color + 2)) (blue *. flame))
                  end
                done
              done))
end

module Crt_rolling_bar_effect = struct
  type t = {
    mutable speed : float;
    mutable height : float;
    mutable intensity : float;
    mutable fade_distance : float;
    mutable position : float;
  }

  let create ?(speed = 0.5) ?(height = 0.15) ?(intensity = 0.3)
      ?(fade_distance = 0.3) () =
    {
      speed;
      height = Float.max 0.01 (Float.min 0.5 height);
      intensity = clamp_unit intensity;
      fade_distance = clamp_unit fade_distance;
      position = 0.0;
    }

  let speed value = value.speed
  let set_speed value next = value.speed <- next
  let height value = value.height
  let set_height value next = value.height <- Float.max 0.01 (Float.min 0.5 next)
  let intensity value = value.intensity
  let set_intensity value next = value.intensity <- clamp_unit next
  let fade_distance value = value.fade_distance
  let set_fade_distance value next = value.fade_distance <- clamp_unit next

  let apply value buffer ~delta_time =
    if not (finite delta_time) || Float.compare delta_time 0.0 < 0 then
      Error Error.Invalid_argument
    else
      Result.bind (dimensions buffer) (fun (width, height) ->
          let cycle_height = float_of_int height +. value.height *. float_of_int height *. 2.0 in
          value.position <-
            if Float.compare cycle_height 0.0 = 0 then 0.0
            else
              mod_float (value.position +. delta_time *. value.speed) cycle_height;
          let bar_height = value.height *. float_of_int height in
          let fade_distance = value.fade_distance *. bar_height in
          let total_height = bar_height +. fade_distance *. 2.0 in
          let center = value.position -. total_height /. 2.0 +. bar_height /. 2.0 in
          with_snapshot buffer (fun (_characters, foreground, background, _attributes) ->
              for y = 0 to height - 1 do
                let distance = Float.abs (float_of_int y -. center) in
                let factor =
                  if Float.compare total_height 0.0 <= 0
                     || Float.compare distance (total_height /. 2.0) > 0
                  then 0.0
                  else cos (distance /. (total_height /. 2.0) *. Float.pi /. 2.0)
                in
                if Float.compare factor 0.001 > 0 then begin
                  let multiplier = 1.0 +. value.intensity *. factor in
                  for x = 0 to width - 1 do
                    let color = (y * width + x) * 4 in
                    set_rgb foreground color
                      (channel foreground color *. multiplier)
                      (channel foreground (color + 1) *. multiplier)
                      (channel foreground (color + 2) *. multiplier);
                    set_rgb background color
                      (channel background color *. multiplier)
                      (channel background (color + 1) *. multiplier)
                      (channel background (color + 2) *. multiplier)
                  done
                end
              done))
end

module Rainbow_text_effect = struct
  type t = {
    mutable speed : float;
    mutable saturation : float;
    mutable value : float;
    mutable repeats : float;
    mutable time : float;
  }

  let create ?(speed = 0.01) ?(saturation = 1.0) ?(value = 1.0)
      ?(repeats = 3.0) () =
    {
      speed = Float.max 0.0 speed;
      saturation = clamp_unit saturation;
      value = clamp_unit value;
      repeats = Float.max 0.1 repeats;
      time = 0.0;
    }

  let speed value = value.speed
  let set_speed value next = value.speed <- Float.max 0.0 next
  let saturation value = value.saturation
  let set_saturation value next = value.saturation <- clamp_unit next
  let value value = value.value
  let set_value value next = value.value <- clamp_unit next
  let repeats value = value.repeats
  let set_repeats value next = value.repeats <- Float.max 0.1 next

  let hsv_to_rgb hue saturation value =
    let i = int_of_float (Float.floor (hue *. 6.0)) mod 6 in
    let f = hue *. 6.0 -. Float.floor (hue *. 6.0) in
    let p = value *. (1.0 -. saturation) in
    let q = value *. (1.0 -. f *. saturation) in
    let t = value *. (1.0 -. (1.0 -. f) *. saturation) in
    match i with
    | 0 -> value, t, p
    | 1 -> q, value, p
    | 2 -> p, value, t
    | 3 -> p, q, value
    | 4 -> t, p, value
    | _ -> value, p, q

  let apply value buffer ~delta_time =
    if not (finite delta_time) || Float.compare delta_time 0.0 < 0 then
      Error Error.Invalid_argument
    else
      Result.bind (dimensions buffer) (fun (width, height) ->
          value.time <- value.time +. delta_time *. value.speed;
          with_snapshot buffer (fun (_characters, foreground, _background, _attributes) ->
              let angle = 25.0 *. Float.pi /. 180.0 in
              let cosine = cos angle in
              let sine = sin angle in
              let maximum = float_of_int width *. cosine +. float_of_int height *. sine in
              for y = 0 to height - 1 do
                for x = 0 to width - 1 do
                  let color = (y * width + x) * 4 in
                  if channel foreground color >= 0.9
                     && channel foreground (color + 1) >= 0.9
                     && channel foreground (color + 2) >= 0.9
                     && Float.compare maximum 0.0 > 0
                  then
                    let projection = float_of_int x *. cosine +. float_of_int y *. sine in
                    let raw_hue = projection /. maximum *. value.repeats +. value.time *. 0.1 in
                    let hue = raw_hue -. floor raw_hue in
                    let red, green, blue = hsv_to_rgb hue value.saturation value.value in
                    set_rgb foreground color red green blue
                done
              done))
end

module DistortionEffect = Distortion_effect
module VignetteEffect = Vignette_effect
module CloudsEffect = Clouds_effect
module FlamesEffect = Flames_effect
module CRTRollingBarEffect = Crt_rolling_bar_effect
module RainbowTextEffect = Rainbow_text_effect
