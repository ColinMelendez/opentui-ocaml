module O = Opentui_core

let color_of_hex hex =
  match O.Lib.Rgba.of_hex hex with
  | Error message -> invalid_arg ("invalid hex color " ^ hex ^ ": " ^ message)
  | Ok rgba -> (
      match O.Lib.Rgba.to_color rgba with
      | Ok color -> color
      | Error error ->
          invalid_arg
            ("hex color could not be converted: " ^ hex ^ ": " ^ O.Native.Error.message error))

let color_of_hsv hue saturation value =
  let rgba = O.Lib.Rgba.hsv_to_rgb hue saturation value in
  match O.Lib.Rgba.to_color rgba with
  | Ok color -> color
  | Error error ->
      invalid_arg
        (Printf.sprintf "hsv %f/%f/%f could not be converted: %s" hue saturation value
           (O.Native.Error.message error))

let hex_of_rgb red green blue =
  Printf.sprintf "#%02X%02X%02X" red green blue

let hex_of_color color =
  let red, green, blue, _ = O.Color.channels color in
  hex_of_rgb red green blue