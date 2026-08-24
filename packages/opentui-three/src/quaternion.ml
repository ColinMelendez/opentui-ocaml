type t = { mutable x : float; mutable y : float; mutable z : float; mutable w : float }

let identity () = { x = 0.0; y = 0.0; z = 0.0; w = 1.0 }

let set t x y z w =
  t.x <- x;
  t.y <- y;
  t.z <- z;
  t.w <- w

let copy t v =
  t.x <- v.x;
  t.y <- v.y;
  t.z <- v.z;
  t.w <- v.w

let from_axis_angle ~(axis : Vector3.t) ~angle =
  (* axis must be normalized by the caller; three.js makes the same demand
     through Quaternion.setFromAxisAngle after normalizing on their side, and
     our public callers normalize first. *)
  let half = angle /. 2.0 in
  let s = Float.sin half in
  {
    x = axis.x *. s;
    y = axis.y *. s;
    z = axis.z *. s;
    w = Float.cos half;
  }

let normalize t =
  let l2 =
    ((t.x *. t.x) +. (t.y *. t.y)) +. ((t.z *. t.z) +. (t.w *. t.w))
  in
  if Float.compare l2 0.0 > 0 then begin
    let inv = 1.0 /. Float.sqrt l2 in
    t.x <- t.x *. inv;
    t.y <- t.y *. inv;
    t.z <- t.z *. inv;
    t.w <- t.w *. inv
  end;
  t

let multiply out a b =
  (* out = a * b (apply b first), matching three.js Quaternion.multiply. *)
  let ax = a.x and ay = a.y and az = a.z and aw = a.w in
  let bx = b.x and by = b.y and bz = b.z and bw = b.w in
  out.x <- (aw *. bx) +. (ax *. bw) +. (ay *. bz) -. (az *. by);
  out.y <- (aw *. by) -. (ax *. bz) +. (ay *. bw) +. (az *. bx);
  out.z <- (aw *. bz) +. (ax *. by) -. (ay *. bx) +. (az *. bw);
  out.w <- (aw *. bw) -. (ax *. bx) -. (ay *. by) -. (az *. bz)

let premultiply t ~a =
  (* t = a * t with [a] read before any write, so [a] may alias [t]. *)
  let ax = a.x and ay = a.y and az = a.z and aw = a.w in
  let tx = t.x and ty = t.y and tz = t.z and tw = t.w in
  t.x <- (aw *. tx) +. (ax *. tw) +. (ay *. tz) -. (az *. ty);
  t.y <- (aw *. ty) -. (ax *. tz) +. (ay *. tw) +. (az *. tx);
  t.z <- (aw *. tz) +. (ax *. ty) -. (ay *. tx) +. (az *. tw);
  t.w <- (aw *. tw) -. (ax *. tx) -. (ay *. ty) -. (az *. tz)

let postmultiply t b =
  (* t = t * b with [b] read before any write, so [b] may alias [t]. *)
  let bx = b.x and by = b.y and bz = b.z and bw = b.w in
  let tx = t.x and ty = t.y and tz = t.z and tw = t.w in
  t.x <- (tw *. bx) +. (tx *. bw) +. (ty *. bz) -. (tz *. by);
  t.y <- (tw *. by) -. (tx *. bz) +. (ty *. bw) +. (tz *. bx);
  t.z <- (tw *. bz) +. (tx *. by) -. (ty *. bx) +. (tz *. bw);
  t.w <- (tw *. bw) -. (tx *. bx) -. (ty *. by) -. (tz *. bz)

let invert t =
  (* Conjugate then normalize: exact inverse for unit-length quaternions,
     graceful for drifted ones; zero length stays untouched per our
     normalize tolerance. *)
  t.x <- -.t.x;
  t.y <- -.t.y;
  t.z <- -.t.z;
  ignore (normalize t);
  t

let set_from_euler ~x ~y ~z =
  (* Three.js default Euler order XYZ: rotations applied about X, then Y,
     then Z in the parent frame. Additional named orders land when a
     consumer needs them rather than as speculative formulas. *)
  let cx = Float.cos (x /. 2.0) and sx = Float.sin (x /. 2.0) in
  let cy = Float.cos (y /. 2.0) and sy = Float.sin (y /. 2.0) in
  let cz = Float.cos (z /. 2.0) and sz = Float.sin (z /. 2.0) in
  {
    x = (sx *. cy *. cz) +. (cx *. sy *. sz);
    y = (cx *. sy *. cz) -. (sx *. cy *. sz);
    z = (cx *. cy *. sz) +. (sx *. sy *. cz);
    w = (cx *. cy *. cz) -. (sx *. sy *. sz);
  }

let to_matrix4 t out =
  let x = t.x and y = t.y and z = t.z and w = t.w in
  let x2 = x +. x and y2 = y +. y and z2 = z +. z in
  let xx = x *. x2 and xy = x *. y2 and xz = x *. z2 in
  let yy = y *. y2 and yz = y *. z2 and zz = z *. z2 in
  let wx = w *. x2 and wy = w *. y2 and wz = w *. z2 in
  Float.Array.set out 0 (1.0 -. (yy +. zz));
  Float.Array.set out 1 (xy +. wz);
  Float.Array.set out 2 (xz -. wy);
  Float.Array.set out 3 0.0;
  Float.Array.set out 4 (xy -. wz);
  Float.Array.set out 5 (1.0 -. (xx +. zz));
  Float.Array.set out 6 (yz +. wx);
  Float.Array.set out 7 0.0;
  Float.Array.set out 8 (xz +. wy);
  Float.Array.set out 9 (yz -. wx);
  Float.Array.set out 10 (1.0 -. (xx +. yy));
  Float.Array.set out 11 0.0;
  Float.Array.set out 12 0.0;
  Float.Array.set out 13 0.0;
  Float.Array.set out 14 0.0;
  Float.Array.set out 15 1.0

let from_euler_matrix m =
  (* Shepperd's method, term-for-term from three.js r177
     Quaternion.setFromRotationMatrix. Beware the upstream naming trap:
     three.js's local m11/m22/m33 mean elements 0/5/10 (diagonal), while
     m13 etc. count sequentially through the rotation block - every
     off-diagonal pair below was verified against pure axis rotations of
     150 degrees, whose non-positive trace forces these arms. *)
  let g i = Float.Array.get m i in
  let e00 = g 0 and e05 = g 5 and e10 = g 10 in
  let trace = (e00 +. e05) +. e10 in
  if Float.compare trace 0.0 > 0 then begin
    let s = Float.sqrt (trace +. 1.0) *. 2.0 in
    { x = (g 6 -. g 9) /. s;
      y = (g 8 -. g 2) /. s;
      z = (g 1 -. g 4) /. s;
      w = 0.25 *. s }
  end
  else if Float.compare e00 (Float.max e05 e10) >= 0 then begin
    let s = Float.sqrt ((1.0 +. e00) -. e05 -. e10) *. 2.0 in
    { x = 0.25 *. s;
      y = (g 4 +. g 1) /. s;
      z = (g 8 +. g 2) /. s;
      w = (g 6 -. g 9) /. s }
  end
  else if Float.compare e05 e10 > 0 then begin
    let s = Float.sqrt ((1.0 +. e05) -. e00 -. e10) *. 2.0 in
    { x = (g 4 +. g 1) /. s;
      y = 0.25 *. s;
      z = (g 9 +. g 6) /. s;
      w = (g 8 -. g 2) /. s }
  end
  else begin
    let s = Float.sqrt ((1.0 +. e10) -. e00 -. e05) *. 2.0 in
    { x = (g 8 +. g 2) /. s;
      y = (g 9 +. g 6) /. s;
      z = 0.25 *. s;
      w = (g 1 -. g 4) /. s }
  end
