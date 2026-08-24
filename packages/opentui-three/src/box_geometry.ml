let create ?(width = 1.0) ?(height = 1.0) ?(depth = 1.0) () =
  (* Each face is defined by an origin corner [o], edge vectors [u] and [v]
     chosen so that cross(u, v) equals the outward normal [n], and the quad
     o, o+u, o+u+v, o+v triangulated as (0, 1, 2) and (0, 2, 3). That winding
     is counter-clockwise when viewed from outside the box, which is what the
     renderer's back-face culling requires. *)
  let hx = width /. 2.0 and hy = height /. 2.0 and hz = depth /. 2.0 in
  let faces =
    [ ( ( -.hx, -.hy, hz ),
        ( width, 0.0, 0.0 ),
        ( 0.0, height, 0.0 ),
        ( 0.0, 0.0, 1.0 ) );
      ( ( hx, -.hy, -.hz ),
        ( -.width, 0.0, 0.0 ),
        ( 0.0, height, 0.0 ),
        ( 0.0, 0.0, -1.0 ) );
      ( ( hx, -.hy, hz ),
        ( 0.0, 0.0, -.depth ),
        ( 0.0, height, 0.0 ),
        ( 1.0, 0.0, 0.0 ) );
      ( ( -.hx, -.hy, -.hz ),
        ( 0.0, 0.0, depth ),
        ( 0.0, height, 0.0 ),
        ( -1.0, 0.0, 0.0 ) );
      ( ( -.hx, hy, hz ),
        ( width, 0.0, 0.0 ),
        ( 0.0, 0.0, -.depth ),
        ( 0.0, 1.0, 0.0 ) );
      ( ( -.hx, -.hy, -.hz ),
        ( width, 0.0, 0.0 ),
        ( 0.0, 0.0, depth ),
        ( 0.0, -1.0, 0.0 ) ) ]
  in
  let interleaved = Float.Array.make (6 * 4 * 6) 0.0 in
  let indices = Array.make (6 * 6) 0 in
  List.iteri
    (fun face_index ((ox, oy, oz), (ux, uy, uz), (vx, vy, vz), normal) ->
      let base_vertex = face_index * 4 in
      let corners =
        [| (ox, oy, oz);
           (ox +. ux, oy +. uy, oz +. uz);
           (ox +. ux +. vx, oy +. uy +. vy, oz +. uz +. vz);
           (ox +. vx, oy +. vy, oz +. vz) |]
      in
      Array.iteri
        (fun corner_index (cx, cy, cz) ->
          let slot = ((base_vertex + corner_index) * 6) in
          Float.Array.set interleaved slot cx;
          Float.Array.set interleaved (slot + 1) cy;
          Float.Array.set interleaved (slot + 2) cz;
          let nx, ny, nz = normal in
          Float.Array.set interleaved (slot + 3) nx;
          Float.Array.set interleaved (slot + 4) ny;
          Float.Array.set interleaved (slot + 5) nz)
        corners;
      let base_index = face_index * 6 in
      indices.(base_index) <- base_vertex;
      indices.(base_index + 1) <- base_vertex + 1;
      indices.(base_index + 2) <- base_vertex + 2;
      indices.(base_index + 3) <- base_vertex;
      indices.(base_index + 4) <- base_vertex + 2;
      indices.(base_index + 5) <- base_vertex + 3)
    faces;
  { Geometry.interleaved; indices }
