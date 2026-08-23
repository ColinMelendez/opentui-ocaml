(** Three.js-shaped Euler angles in radians, default XYZ order. *)

type t = { mutable x : float; mutable y : float; mutable z : float }

let create ?(x = 0.0) ?(y = 0.0) ?(z = 0.0) () = { x; y; z }

let set t x y z =
  t.x <- x;
  t.y <- y;
  t.z <- z

let to_quaternion ~(order : [ `Xyz ]) (e : t) =
  ignore order;
  Quaternion.set_from_euler ~x:e.x ~y:e.y ~z:e.z

let of_quaternion q =
  (* three.js Euler.XYZ extraction from the rotation matrix. *)
  let m = Matrix4.create () in
  Quaternion.to_matrix4 q m;
  let get i = Float.Array.get m i in
  let m13 = get 8 and m23 = get 9 and m33 = get 10 in
  let m12 = get 4 and m11 = get 0 and m32 = get 6 in
  let y = Float.asin (Float.max (-1.0) (Float.min 1.0 m13)) in
  if Float.abs m13 < 0.9999999 then
    { x = Float.atan2 (-.m23) m33; y; z = Float.atan2 (-.m12) m11 }
  else begin
    let x = Float.atan2 m32 m11 in
    { x; y; z = 0.0 }
  end
