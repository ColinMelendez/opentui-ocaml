type t = {
  pixels : bytes;
  width : int;
  height : int;
  wrap_s : [ `Repeat | `Clamp ];
  wrap_t : [ `Repeat | `Clamp ];
  filter : [ `Nearest | `Linear ];
}

let pixels t = t.pixels

let width t = t.width

let height t = t.height

let create ~(pixels : bytes) ~(width : int) ~(height : int)
    ?(wrap_s = `Repeat) ?(wrap_t = `Repeat) ?(filter = `Nearest) () :
    (t, string) result =
  if width <= 0 || height <= 0 then Error "texture dimensions must be positive"
  else if not (Int.equal (Bytes.length pixels) (width * height * 4)) then
    Error "texture needs tightly packed width * height * 4 bytes"
  else Ok { pixels; width; height; wrap_s; wrap_t; filter }
