type t = {
  raw : Opentui_raw.Buffer.t;
}

let of_raw raw = { raw }
let raw buffer = buffer.raw
