type t = {
  red : int;
  green : int;
  blue : int;
  alpha : int;
}

let valid_channel channel = 0 <= channel && channel <= 255

let rgba ~red ~green ~blue ~alpha =
  if
    valid_channel red
    && valid_channel green
    && valid_channel blue
    && valid_channel alpha
  then Ok { red; green; blue; alpha }
  else Error Error.Invalid_argument

let rgb ~red ~green ~blue = rgba ~red ~green ~blue ~alpha:255

let black = { red = 0; green = 0; blue = 0; alpha = 255 }
let white = { red = 255; green = 255; blue = 255; alpha = 255 }
let transparent = { red = 0; green = 0; blue = 0; alpha = 0 }

let channels color = (color.red, color.green, color.blue, color.alpha)

module Private = struct
  let to_native = channels
end
