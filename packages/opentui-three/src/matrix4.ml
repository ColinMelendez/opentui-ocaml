(** Column-major 4x4 matrix with three.js storage order. *)

type t = floatarray

let size = 16

let create () = Float.Array.make size 0.0

let identity out =
  Float.Array.fill out 0 size 0.0;
  Float.Array.set out 0 1.0;
  Float.Array.set out 5 1.0;
  Float.Array.set out 10 1.0;
  Float.Array.set out 15 1.0;
  out

let of_array values =
  let m = create () in
  let n = Array.length values in
  let limit = if n > size then size else n in
  for i = 0 to limit - 1 do
    Float.Array.set m i values.(i)
  done;
  m

let make_translation out x y z =
  ignore (identity out);
  Float.Array.set out 12 x;
  Float.Array.set out 13 y;
  Float.Array.set out 14 z;
  out

let copy out src = Float.Array.blit src 0 out 0 size

let multiply out a b =
  (* [out] must not alias [a] or [b]. Column-major product:
     out[c*4+r] = sum_k a[k*4+r] * b[c*4+k]. *)
  let tmp = create () in
  for c = 0 to 3 do
    for r = 0 to 3 do
      let sum = ref 0.0 in
      for k = 0 to 3 do
        sum := !sum +. (Float.Array.get a ((k * 4) + r) *. Float.Array.get b ((c * 4) + k))
      done;
      Float.Array.set tmp ((c * 4) + r) !sum
    done
  done;
  Float.Array.blit tmp 0 out 0 size

let compose out (position : Vector3.t) (quaternion : Quaternion.t)
    (scale : Vector3.t) =
  (* three.js Matrix4.compose: translation, quaternion rotation, and scale
     fused into one column-major write, derived directly from the quaternion
     so no Euler conversion intervenes. *)
  let x = quaternion.x and y = quaternion.y and z = quaternion.z and w = quaternion.w in
  let x2 = x +. x and y2 = y +. y and z2 = z +. z in
  let xx = x *. x2 and xy = x *. y2 and xz = x *. z2 in
  let yy = y *. y2 and yz = y *. z2 and zz = z *. z2 in
  let wx = w *. x2 and wy = w *. y2 and wz = w *. z2 in
  let sx = scale.x and sy = scale.y and sz = scale.z in
  Float.Array.set out 0 (((1.0 -. yy) -. zz) *. sx);
  Float.Array.set out 1 ((xy +. wz) *. sx);
  Float.Array.set out 2 ((xz -. wy) *. sx);
  Float.Array.set out 3 0.0;
  Float.Array.set out 4 ((xy -. wz) *. sy);
  Float.Array.set out 5 (((1.0 -. xx) -. zz) *. sy);
  Float.Array.set out 6 ((yz +. wx) *. sy);
  Float.Array.set out 7 0.0;
  Float.Array.set out 8 ((xz +. wy) *. sz);
  Float.Array.set out 9 ((yz -. wx) *. sz);
  Float.Array.set out 10 (((1.0 -. xx) -. yy) *. sz);
  Float.Array.set out 11 0.0;
  Float.Array.set out 12 position.x;
  Float.Array.set out 13 position.y;
  Float.Array.set out 14 position.z;
  Float.Array.set out 15 1.0

let perspective ~fov_degrees ~aspect ?(near = 0.1) ?(far = 1000.0) out =
  (* Right-handed view volume looking down -Z, matching three.js
     PerspectiveCamera.updateProjectionMatrix except the depth range:
     WebGPU maps [near..far] onto NDC [0..1], so the z row is
     far/(near-far) and the translation far*near/(near-far). *)
  let near = Float.abs near and far = Float.abs far in
  let focal_length = 1.0 /. Float.tan (fov_degrees *. Float.pi /. 360.0) in
  let range = 1.0 /. (near -. far) in
  Float.Array.fill out 0 size 0.0;
  Float.Array.set out 0 (focal_length /. aspect);
  Float.Array.set out 5 focal_length;
  Float.Array.set out 10 (far *. range);
  Float.Array.set out 11 (-1.0);
  Float.Array.set out 14 (far *. near *. range)

let look_at ~(up : Vector3.t) ~(eye : Vector3.t) ~(target : Vector3.t) out =
  (* Builds the view matrix directly: camera at eye looking toward target
     with the reference right-handed convention. Degenerate directions are
     ignored, leaving [out] untouched, matching Object3D.lookAt tolerance. *)
  let zx = eye.x -. target.x in
  let zy = eye.y -. target.y in
  let zz = eye.z -. target.z in
  let zl = Float.sqrt ((zx *. zx) +. (zy *. zy) +. (zz *. zz)) in
  if Float.compare zl 1e-12 > 0 then begin
    let zxn = zx /. zl and zyn = zy /. zl and zzn = zz /. zl in
    let xx = (up.y *. zzn) -. (up.z *. zyn) in
    let xy = (up.z *. zxn) -. (up.x *. zzn) in
    let xz = (up.x *. zyn) -. (up.y *. zxn) in
    let xl = Float.sqrt ((xx *. xx) +. (xy *. xy) +. (xz *. xz)) in
    if Float.compare xl 1e-12 > 0 then begin
      let xxn = xx /. xl and xyn = xy /. xl and xzn = xz /. xl in
      let yx = (zyn *. xzn) -. (zzn *. xyn) in
      let yy = (zzn *. xxn) -. (zxn *. xzn) in
      let yz = (zxn *. xyn) -. (zyn *. xxn) in
      Float.Array.set out 0 xxn;
      Float.Array.set out 1 yx;
      Float.Array.set out 2 zxn;
      Float.Array.set out 3 0.0;
      Float.Array.set out 4 xyn;
      Float.Array.set out 5 yy;
      Float.Array.set out 6 zyn;
      Float.Array.set out 7 0.0;
      Float.Array.set out 8 xzn;
      Float.Array.set out 9 yz;
      Float.Array.set out 10 zzn;
      Float.Array.set out 11 0.0;
      Float.Array.set out 12
        (-. ((xxn *. eye.x) +. (xyn *. eye.y) +. (xzn *. eye.z)));
      Float.Array.set out 13
        (-. ((yx *. eye.x) +. (yy *. eye.y) +. (yz *. eye.z)));
      Float.Array.set out 14
        (-. ((zxn *. eye.x) +. (zyn *. eye.y) +. (zzn *. eye.z)));
      Float.Array.set out 15 1.0
    end
  end

let invert input output =
  (* Gauss-Jordan elimination with partial pivoting. Returns false when the
     matrix is singular, leaving [output] untouched. *)
  let a = Array.init 4 (fun r ->
      Array.init 4 (fun c -> Float.Array.get input ((c * 4) + r)))
  in
  let inv = Array.make_matrix 4 4 0.0 in
  for i = 0 to 3 do
    inv.(i).(i) <- 1.0
  done;
  let singular = ref false in
  for col = 0 to 3 do
    if not !singular then begin
      let best = ref col in
      for row = col + 1 to 3 do
        if
          Float.compare (Float.abs a.(!best).(col)) (Float.abs a.(row).(col)) < 0
        then best := row
      done;
      if Float.compare (Float.abs a.(!best).(col)) 1e-12 < 0 then singular := true
      else begin
        if not (Int.equal !best col) then begin
          let tmp = a.(col) in
          a.(col) <- a.(!best);
          a.(!best) <- tmp;
          let itmp = inv.(col) in
          inv.(col) <- inv.(!best);
          inv.(!best) <- itmp
        end;
        let pivot = a.(col).(col) in
        for j = 0 to 3 do
          a.(col).(j) <- a.(col).(j) /. pivot;
          inv.(col).(j) <- inv.(col).(j) /. pivot
        done;
        for row = 0 to 3 do
          if not (Int.equal row col) then begin
            let factor = a.(row).(col) in
            if not (Float.equal factor 0.0) then begin
              for j = 0 to 3 do
                a.(row).(j) <- a.(row).(j) -. (factor *. a.(col).(j));
                inv.(row).(j) <- inv.(row).(j) -. (factor *. inv.(col).(j))
              done
            end
          end
        done
      end
    end
  done;
  if not !singular then
    for r = 0 to 3 do
      for c = 0 to 3 do
        Float.Array.set output ((c * 4) + r) inv.(r).(c)
      done
    done;
  not !singular

let transform_point (m : t) (v : Vector3.t) =
  let g i = Float.Array.get m i in
  let x = v.x and y = v.y and z = v.z in
  let w = (((g 3 *. x) +. (g 7 *. y)) +. (g 11 *. z)) +. g 15 in
  v.x <- (((g 0 *. x) +. (g 4 *. y)) +. (g 8 *. z)) +. g 12;
  v.y <- (((g 1 *. x) +. (g 5 *. y)) +. (g 9 *. z)) +. g 13;
  v.z <- (((g 2 *. x) +. (g 6 *. y)) +. (g 10 *. z)) +. g 14;
  if (not (Float.equal w 1.0)) && Float.compare (Float.abs w) 1e-12 > 0 then begin
    let inv_w = 1.0 /. w in
    v.x <- v.x *. inv_w;
    v.y <- v.y *. inv_w;
    v.z <- v.z *. inv_w
  end;
  v
