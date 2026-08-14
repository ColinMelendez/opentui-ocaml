type t = {
  raw : Opentui_raw.Text_buffer.t;
}

let of_raw raw = { raw }
let raw buffer = buffer.raw
