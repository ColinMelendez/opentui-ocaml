(** Linear-space RGB color, matching three.js Color channels. *)

type t = { mutable r : float; mutable g : float; mutable b : float }

let create ?(r = 1.0) ?(g = 1.0) ?(b = 1.0) () = { r; g; b }

let copy t v =
  t.r <- v.r;
  t.g <- v.g;
  t.b <- v.b

let set_rgb t r g b =
  t.r <- r;
  t.g <- g;
  t.b <- b

let from_hex_int hex =
  (* Three.js Color.setHex treats integers as sRGB and converts to linear
     working space through the standard transfer function. *)
  let channel v =
    let c = Float.of_int (v land 0xff) /. 255.0 in
    if Float.compare c 0.04045 <= 0 then c /. 12.92
    else Float.pow ((c +. 0.055) /. 1.055) 2.4
  in
  { r = channel (hex lsr 16); g = channel (hex lsr 8); b = channel hex }
