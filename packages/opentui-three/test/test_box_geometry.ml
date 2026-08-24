open Windtrap

module Three = Opentui_three.Three

let close ~tolerance a b = Float.abs (a -. b) < tolerance

(* Every triangle must be wound counter-clockwise when viewed from outside:
   cross(v1 - v0, v2 - v0) dotted with the stored face normal is positive.
   The renderer culls back faces with no depth buffer, so a single wrong
   winding shows up as a hole in the rendered solid. *)
let () =
  run "opentui-three-box-geometry"
    [
      test "unit box has 24 vertices and 36 indices" (fun () ->
          let g = Three.Box_geometry.create () in
          if
            not
              (Int.equal
                 (Float.Array.length (Three.Geometry.interleaved g))
                 144)
          then fail "expected 24 interleaved vertices";
          if not (Int.equal (Array.length (Three.Geometry.indices g)) 36) then
            fail "expected 36 indices");

      test "every index stays inside the vertex range" (fun () ->
          let g = Three.Box_geometry.create () in
          Array.iter
            (fun i ->
              if i < 0 || i >= 24 then
                fail (Printf.sprintf "index %d out of range" i))
            (Three.Geometry.indices g));

      test "triangles wind CCW against their outward normals" (fun () ->
          let g = Three.Box_geometry.create () in
          let v = Three.Geometry.interleaved g in
          let get slot component = Float.Array.get v ((slot * 6) + component) in
          for triangle = 0 to 11 do
            let base = triangle * 3 in
            let indices = Three.Geometry.indices g in
            let ia = indices.(base + 0) in
            let ib = indices.(base + 1) in
            let ic = indices.(base + 2) in
            let e1x = get ib 0 -. get ia 0 in
            let e1y = get ib 1 -. get ia 1 in
            let e1z = get ib 2 -. get ia 2 in
            let e2x = get ic 0 -. get ia 0 in
            let e2y = get ic 1 -. get ia 1 in
            let e2z = get ic 2 -. get ia 2 in
            let cx = (e1y *. e2z) -. (e1z *. e2y) in
            let cy = (e1z *. e2x) -. (e1x *. e2z) in
            let cz = (e1x *. e2y) -. (e1y *. e2x) in
            let dot =
              (cx *. get ia 3) +. (cy *. get ia 4) +. (cz *. get ia 5)
            in
            if not (close ~tolerance:1e-9 dot ((cx *. cx) +. (cy *. cy) +. (cz *. cz)))
            then
              fail
                (Printf.sprintf
                   "triangle %d is not perpendicular to its face normal (dot %.6f)"
                   triangle dot)
          done);

      test "face normals are axis-aligned and sit on the box surface" (fun () ->
          let g = Three.Box_geometry.create () in
          let v = Three.Geometry.interleaved g in
          for vertex = 0 to 23 do
            let px = Float.Array.get v ((vertex * 6) + 0) in
            let py = Float.Array.get v ((vertex * 6) + 1) in
            let pz = Float.Array.get v ((vertex * 6) + 2) in
            let nx = Float.Array.get v ((vertex * 6) + 3) in
            let ny = Float.Array.get v ((vertex * 6) + 4) in
            let nz = Float.Array.get v ((vertex * 6) + 5) in
            (* Unit normals along one axis; each face plane satisfies
               p . n = half extent. *)
            let axis_sum =
              Float.abs nx +. Float.abs ny +. Float.abs nz
            in
            if not (close ~tolerance:1e-9 axis_sum 1.0) then
              fail (Printf.sprintf "vertex %d normal is not axis aligned" vertex);
            let plane = (px *. nx) +. (py *. ny) +. (pz *. nz) in
            if not (close ~tolerance:1e-9 plane 0.5) then
              fail (Printf.sprintf "vertex %d does not lie on its face plane" vertex)
          done);
    ]
