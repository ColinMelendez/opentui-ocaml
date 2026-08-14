type t = {
  raw : Opentui_raw.Text_buffer_view.t;
}

let of_raw raw = { raw }
let raw view = view.raw
