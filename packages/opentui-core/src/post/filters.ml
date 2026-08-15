let finite value = Float.is_finite value

let dimensions buffer =
  Result.bind (Buffer.width buffer) (fun width ->
      Result.map (fun height ->
          (Int32.to_int width, Int32.to_int height))
        (Buffer.height buffer))

let mask length = Float.Array.make length 0.0

let matrix_scale scale : floatarray =
  [| scale; 0.0; 0.0; 0.0;
     0.0; scale; 0.0; 0.0;
     0.0; 0.0; scale; 0.0;
     0.0; 0.0; 0.0; 1.0 |]

let matrix_brightness brightness : floatarray =
  [| 1.0; 0.0; 0.0; brightness;
     0.0; 1.0; 0.0; brightness;
     0.0; 0.0; 1.0; brightness;
     0.0; 0.0; 0.0; 1.0 |]

let matrix_saturation strength : floatarray =
  let s = Float.max 0.0 strength in
  let sr = 0.299 *. (1.0 -. s) in
  let sg = 0.587 *. (1.0 -. s) in
  let sb = 0.114 *. (1.0 -. s) in
  [| sr +. s; sg; sb; 0.0;
     sr; sg +. s; sb; 0.0;
     sr; sg; sb +. s; 0.0;
     0.0; 0.0; 0.0; 1.0 |]

let ensure_finite values =
  let valid = ref true in
  let index = ref 0 in
  while !valid && !index < Float.Array.length values do
    if not (finite (Float.Array.get values !index)) then valid := false;
    index := !index + 1
  done;
  !valid

let apply_matrix buffer matrix ~cell_mask ~strength ~target =
  if not (finite strength) || not (ensure_finite matrix)
     || not (ensure_finite cell_mask)
  then Error Error.Invalid_argument
  else if Float.compare strength 0.0 = 0 then Ok ()
  else Buffer.color_matrix buffer ~matrix ~cell_mask ~strength ~target

let apply_matrix_uniform buffer matrix ~strength ~target =
  if not (finite strength) || not (ensure_finite matrix) then
    Error Error.Invalid_argument
  else if Float.compare strength 0.0 = 0 then Ok ()
  else Buffer.color_matrix_uniform buffer ~matrix ~strength ~target

let apply_scanlines buffer ?(strength = 0.8) ?(step = 2) () =
  if not (finite strength) || step < 1 then Ok ()
  else if Float.compare strength 1.0 = 0 then Ok ()
  else
    Result.bind (dimensions buffer) (fun (width, height) ->
        let affected_rows = (height + step - 1) / step in
        let values = mask (width * affected_rows * 3) in
        let index = ref 0 in
        let y = ref 0 in
        while !y < height do
          for x = 0 to width - 1 do
            Float.Array.set values !index (float_of_int x);
            Float.Array.set values (!index + 1) (float_of_int !y);
            Float.Array.set values (!index + 2) 1.0;
            index := !index + 3
          done;
          y := !y + step
        done;
        apply_matrix buffer (matrix_scale strength) ~cell_mask:values
          ~strength:1.0 ~target:Buffer.Background)

let apply_invert buffer ?(strength = 1.0) () =
  if not (finite strength) then Error Error.Invalid_argument
  else
    apply_matrix_uniform buffer Matrices.invert_matrix ~strength
      ~target:Buffer.Both

let deterministic_noise index =
  let value = sin (float_of_int (index + 1) *. 12.9898 +. 78.233) in
  let fractional = value -. floor value in
  (fractional *. 2.0) -. 1.0

let apply_noise buffer ?(strength = 0.1) () =
  if not (finite strength) then Error Error.Invalid_argument
  else if Float.compare strength 0.0 = 0 then Ok ()
  else
    Result.bind (dimensions buffer) (fun (width, height) ->
        let values = mask (width * height * 3) in
        let index = ref 0 in
        for y = 0 to height - 1 do
          for x = 0 to width - 1 do
            let cell = y * width + x in
            Float.Array.set values !index (float_of_int x);
            Float.Array.set values (!index + 1) (float_of_int y);
            Float.Array.set values (!index + 2) (deterministic_noise cell);
            index := !index + 3
          done
        done;
        apply_matrix buffer (matrix_scale (1.0 +. strength)) ~cell_mask:values
          ~strength:1.0 ~target:Buffer.Both)

let int_clamp value = max 0 (min 255 value)

let byte word = Int32.to_int (Int32.logand word 0xffl)

let channel colors index = float_of_int (byte colors.(index)) /. 255.0

let set_channel colors index value =
  let scaled = int_of_float (Float.round (Float.max 0.0 (Float.min 1.0 value) *. 255.0)) in
  let low = Int32.of_int (int_clamp scaled) in
  colors.(index) <- Int32.logor (Int32.logand colors.(index) 0xffffff00l) low

let set_rgb colors index red green blue =
  set_channel colors index red;
  set_channel colors (index + 1) green;
  set_channel colors (index + 2) blue

let with_snapshot buffer operation =
  Result.bind (Buffer.snapshot buffer) (fun snapshot ->
      Result.bind (operation snapshot) (fun () -> Buffer.restore buffer snapshot))

let apply_chromatic_aberration buffer ?(strength = 1.0) () =
  if not (finite strength) then Error Error.Invalid_argument
  else
    Result.bind (dimensions buffer) (fun (width, height) ->
        with_snapshot buffer (fun (_chars, foreground, _background, _attributes) ->
            let original = Array.copy foreground in
            let center_x = float_of_int width /. 2.0 in
            let center_y = float_of_int height /. 2.0 in
            let denominator = Float.max center_x center_y in
            for y = 0 to height - 1 do
              for x = 0 to width - 1 do
                let dx = float_of_int x -. center_x in
                let dy = float_of_int y -. center_y in
                let distance = sqrt (dx *. dx +. dy *. dy) in
                let offset =
                  if Float.compare denominator 0.0 = 0 then 0
                  else int_of_float (Float.round (distance /. denominator *. strength))
                in
                let left = max 0 (min (width - 1) (x - offset)) in
                let right = max 0 (min (width - 1) (x + offset)) in
                let destination = (y * width + x) * 4 in
                let red = channel original ((y * width + left) * 4) in
                let green = channel original ((y * width + x) * 4 + 1) in
                let blue = channel original ((y * width + right) * 4 + 2) in
                set_rgb foreground destination red green blue
              done
            done;
            Ok ()))

let default_ascii_ramp =
  " .'`^\"\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$"

let apply_ascii_art buffer ?(ramp = default_ascii_ramp)
    ?(fg_color = (1.0, 1.0, 1.0)) ?(bg_color = (0.0, 0.0, 0.0)) () =
  let (fg_red, fg_green, fg_blue) = fg_color in
  let (bg_red, bg_green, bg_blue) = bg_color in
  if String.length ramp = 0 || not (finite fg_red) || not (finite fg_green)
     || not (finite fg_blue) || not (finite bg_red) || not (finite bg_green)
     || not (finite bg_blue)
  then Error Error.Invalid_argument
  else
    Result.bind (dimensions buffer) (fun (width, height) ->
        let result =
          with_snapshot buffer (fun (characters, _foreground, background, _attributes) ->
              let ramp_length = String.length ramp in
              for y = 0 to height - 1 do
                for x = 0 to width - 1 do
                  let cell = y * width + x in
                  let color = cell * 4 in
                  let red = channel background color in
                  let green = channel background (color + 1) in
                  let blue = channel background (color + 2) in
                  let luminance = 0.299 *. red +. 0.587 *. green +. 0.114 *. blue in
                  let ramp_index =
                    max 0 (min (ramp_length - 1)
                             (int_of_float (Float.floor (luminance *. float_of_int ramp_length))))
                  in
                  characters.(cell) <- Int32.of_int (Char.code (String.get ramp ramp_index))
                done
              done;
              Ok ())
        in
        Result.bind result (fun () ->
            let fg_matrix : floatarray =
              [| 0.0; 0.0; 0.0; fg_red;
                 0.0; 0.0; 0.0; fg_green;
                 0.0; 0.0; 0.0; fg_blue;
                 0.0; 0.0; 0.0; 1.0 |]
            in
            let bg_matrix : floatarray =
              [| 0.0; 0.0; 0.0; bg_red;
                 0.0; 0.0; 0.0; bg_green;
                 0.0; 0.0; 0.0; bg_blue;
                 0.0; 0.0; 0.0; 1.0 |]
            in
            Result.bind
              (apply_matrix_uniform buffer fg_matrix ~strength:1.0
                 ~target:Buffer.Foreground)
              (fun () ->
                apply_matrix_uniform buffer bg_matrix ~strength:1.0
                  ~target:Buffer.Background)))

let apply_brightness buffer ?(brightness = 0.0)
    ?(cell_mask : floatarray = [||]) () =
  if not (finite brightness) then Error Error.Invalid_argument
  else if Float.compare brightness 0.0 = 0 then Ok ()
  else if Float.Array.length cell_mask = 0 then
    apply_matrix_uniform buffer (matrix_brightness brightness) ~strength:1.0
      ~target:Buffer.Both
  else
    apply_matrix buffer (matrix_brightness brightness) ~cell_mask ~strength:1.0
      ~target:Buffer.Both

let apply_gain buffer ?(gain = 1.0) ?(cell_mask : floatarray = [||]) () =
  if not (finite gain) then Error Error.Invalid_argument
  else if Float.compare gain 1.0 = 0 then Ok ()
  else
    let value = Float.max 0.0 gain in
    if Float.Array.length cell_mask = 0 then
      apply_matrix_uniform buffer (matrix_scale value) ~strength:1.0
        ~target:Buffer.Both
    else
      apply_matrix buffer (matrix_scale value) ~cell_mask ~strength:1.0
        ~target:Buffer.Both

let apply_saturation buffer ?(cell_mask : floatarray = [||])
    ?(strength = 1.0) () =
  if not (finite strength) then Error Error.Invalid_argument
  else if Float.compare strength 1.0 = 0 || Float.compare strength 0.0 = 0 then
    Ok ()
  else if Float.Array.length cell_mask = 0 then
    apply_matrix_uniform buffer (matrix_saturation strength) ~strength:1.0
      ~target:Buffer.Both
  else
    apply_matrix buffer (matrix_saturation strength) ~cell_mask ~strength:1.0
      ~target:Buffer.Both

module Bloom_effect = struct
  type t = {
    mutable threshold : float;
    mutable strength : float;
    mutable radius : int;
  }

  let clamp_threshold value = Float.max 0.0 (Float.min 1.0 value)

  let create ?(threshold = 0.8) ?(strength = 0.2) ?(radius = 2) () =
    {
      threshold = clamp_threshold threshold;
      strength = Float.max 0.0 strength;
      radius = max 0 radius;
    }

  let threshold value = value.threshold
  let set_threshold value next = value.threshold <- clamp_threshold next
  let strength value = value.strength
  let set_strength value next = value.strength <- Float.max 0.0 next
  let radius value = value.radius
  let set_radius value next = value.radius <- max 0 next

  let apply value buffer =
    if not (finite value.threshold) || not (finite value.strength) then
      Error Error.Invalid_argument
    else if Float.compare value.strength 0.0 <= 0 || value.radius <= 0 then Ok ()
    else
      Result.bind (dimensions buffer) (fun (width, height) ->
          with_snapshot buffer (fun (_chars, foreground, background, _attributes) ->
              let source_foreground = Array.copy foreground in
              let source_background = Array.copy background in
              let threshold = value.threshold in
              let strength = value.strength in
              let radius = value.radius in
              let bright_pixels = ref [] in
              for y = 0 to height - 1 do
                for x = 0 to width - 1 do
                  let source = (y * width + x) * 4 in
                  let fg_luminance =
                    0.299 *. channel source_foreground source
                    +. 0.587 *. channel source_foreground (source + 1)
                    +. 0.114 *. channel source_foreground (source + 2)
                  in
                  let bg_luminance =
                    0.299 *. channel source_background source
                    +. 0.587 *. channel source_background (source + 1)
                    +. 0.114 *. channel source_background (source + 2)
                  in
                  let luminance = Float.max fg_luminance bg_luminance in
                  if Float.compare luminance threshold > 0 then
                    let intensity =
                      (luminance -. threshold) /. (1.0 -. threshold +. 0.000001)
                    in
                    bright_pixels := (x, y, Float.max 0.0 intensity) :: !bright_pixels
                done
              done;
              List.iter
                (fun (bright_x, bright_y, intensity) ->
                  for offset_y = -radius to radius do
                    for offset_x = -radius to radius do
                      if not (Int.equal offset_x 0 && Int.equal offset_y 0) then
                        let sample_x = bright_x + offset_x in
                        let sample_y = bright_y + offset_y in
                        let distance_squared =
                          offset_x * offset_x + offset_y * offset_y
                        in
                        if sample_x >= 0 && sample_x < width && sample_y >= 0
                           && sample_y < height
                           && distance_squared <= radius * radius then
                          let falloff =
                            1.0
                            -. (float_of_int distance_squared
                               /. float_of_int (radius * radius))
                          in
                          let amount = intensity *. strength *. falloff in
                          let destination = (sample_y * width + sample_x) * 4 in
                          set_rgb foreground destination
                            (channel foreground destination +. amount)
                            (channel foreground (destination + 1) +. amount)
                            (channel foreground (destination + 2) +. amount);
                          set_rgb background destination
                            (channel background destination +. amount)
                            (channel background (destination + 1) +. amount)
                            (channel background (destination + 2) +. amount)
                    done
                  done)
                !bright_pixels;
              Ok ()))
end

module BloomEffect = Bloom_effect
