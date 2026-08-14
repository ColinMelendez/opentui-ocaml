type t = Opentui_raw.Color.t

let map_error result =
  match result with
  | Ok value -> Ok value
  | Error error -> Error (Native.Error.Native error)

let rgba ~red ~green ~blue ~alpha =
  map_error (Opentui_raw.Color.rgba ~red ~green ~blue ~alpha)

let rgb ~red ~green ~blue = map_error (Opentui_raw.Color.rgb ~red ~green ~blue)

let black = Opentui_raw.Color.black
let white = Opentui_raw.Color.white
let transparent = Opentui_raw.Color.transparent
let channels = Opentui_raw.Color.channels

module Private = struct
  let to_raw color = color
end
