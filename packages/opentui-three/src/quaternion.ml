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
  (* Shepperd's method with the positive-trace branch, reading the rotation
     block of a column-major matrix4. *)
  let m00 = Float.Array.get m 0 and m11 = Float.Array.get m 5 in
  let m22 = Float.Array.get m 10 in
  let trace = (m00 +. m11) +. m22 in
  if Float.compare trace 0.0 > 0 then begin
    let s = Float.sqrt (trace +. 1.0) *. 2.0 in
    { x = (Float.Array.get m 6 -. Float.Array.get m 9) /. s;
      y = (Float.Array.get m 8 -. Float.Array.get m 2) /. s;
      z = (Float.Array.get m 1 -. Float.Array.get m 4) /. s;
      w = 0.25 *. s }
  end
  else if Float.compare m00 (Float.max m11 m22) >= 0 then begin
    let s = Float.sqrt ((1.0 +. m00) -. m11 -. m22) *. 2.0 in
    { x = 0.25 *. s;
      y = (Float.Array.get m 4 +. Float.Array.get m 1) /. s;
      z = (Float.Array.get m 8 +. Float.Array.get m 2) /. s;
      w = (Float.Array.get m 6 -. Float.Array.get m 9) /. s }
  end
  else if Float.compare m11 m22 > 0 then begin
    let s = Float.sqrt ((1.0 +. m11) -. m00 -. m22) *. 2.0 in
    { x = (Float.Array.get m 9 +. Float.Array.get m 6) /. s;
      y = 0.25 *. s;
      z = (Float.Array.get m 6 +. Float.Array.get m 9) /. s;
      w = (Float.Array.get m 2 -. Float.Array.get m 8) /. s }
  end
  else begin
    let s = Float.sqrt ((1.0 +. m22) -. m00 -. m11) *. 2.0 in
    { x = (Float.Array.get m 8 +. Float.Array.get m 2) /. s;
      y = (Float.Array.get m 9 +. Float.Array.get m 6) /. s;
      z = 0.25 *. s;
      w = (Float.Array.get m 1 -. Float.Array.get m 4) /. s }
  end
