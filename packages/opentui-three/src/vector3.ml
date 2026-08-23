(** Mutable three-component vector with three.js semantics. *)

type t = { mutable x : float; mutable y : float; mutable z : float }

let create ?(x = 0.0) ?(y = 0.0) ?(z = 0.0) () = { x; y; z }

let copy t v =
  t.x <- v.x;
  t.y <- v.y;
  t.z <- v.z

let clone t = create ~x:t.x ~y:t.y ~z:t.z ()

let set t x y z =
  t.x <- x;
  t.y <- y;
  t.z <- z

let add t v =
  t.x <- t.x +. v.x;
  t.y <- t.y +. v.y;
  t.z <- t.z +. v.z

let sub t v =
  t.x <- t.x -. v.x;
  t.y <- t.y -. v.y;
  t.z <- t.z -. v.z

let multiply_scalar t s =
  t.x <- t.x *. s;
  t.y <- t.y *. s;
  t.z <- t.z *. s

let dot a b = (a.x *. b.x) +. (a.y *. b.y) +. (a.z *. b.z)

let cross_into a b out =
  let ax = a.x and ay = a.y and az = a.z in
  let bx = b.x and by = b.y and bz = b.z in
  out.x <- (ay *. bz) -. (az *. by);
  out.y <- (az *. bx) -. (ax *. bz);
  out.z <- (ax *. by) -. (ay *. bx)

let length t = Float.sqrt (dot t t)

let normalize t =
  let l = length t in
  if Float.compare l 0.0 > 0 then multiply_scalar t (1.0 /. l);
  t

let transform_direction t (m : floatarray) =
  (* Rotate/scale only: the upper 3x3 of a column-major matrix4, no
     translation, no perspective divide - matches three.js
     Vector3.transformDirection. *)
  let x = t.x and y = t.y and z = t.z in
  t.x <-
    ((Float.Array.get m 0 *. x) +. (Float.Array.get m 4 *. y))
    +. (Float.Array.get m 8 *. z);
  t.y <-
    ((Float.Array.get m 1 *. x) +. (Float.Array.get m 5 *. y))
    +. (Float.Array.get m 9 *. z);
  t.z <-
    ((Float.Array.get m 2 *. x) +. (Float.Array.get m 6 *. y))
    +. (Float.Array.get m 10 *. z);
  normalize t
