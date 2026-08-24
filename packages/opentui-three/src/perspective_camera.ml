let state node =
  match Object3d.kind node with
  | Object3d.Perspective_camera state -> state
  | _ ->
      raise (Invalid_argument "Perspective_camera.state: node is not a camera")

let fov_degrees node = (state node).fov_degrees

let set_fov_degrees node fov = (state node).fov_degrees <- fov

let aspect node = (state node).aspect

let set_aspect node aspect = (state node).aspect <- aspect

let update_projection_matrix node =
  let s = state node in
  Matrix4.perspective ~fov_degrees:s.fov_degrees ~aspect:s.aspect ~near:s.near
    ~far:s.far
    (Object3d.projection_matrix node)

let create ?(fov_degrees = 50.0) ?(aspect = 1.0) ?(near = 0.1)
    ?(far = 1000.0) ?name () =
  let node =
    Object3d.make ?name
      ~kind:(Object3d.Perspective_camera { fov_degrees; aspect; near; far })
      ()
  in
  (* three.js PerspectiveCamera builds its projection in the constructor so
     the camera renders correctly before any explicit update call. *)
  update_projection_matrix node;
  node

let update_matrices ?(force = false) node =
  ignore (state node);
  (* three.js Camera.updateMatrixWorld: the ordinary object update, then the
     inverse world matrix every camera carries for view construction. *)
  Object3d.update_matrix_world ~force node;
  (* A singular world matrix cannot define a view; Matrix4.invert leaves the
     previous inverse untouched there instead of writing garbage. *)
  ignore
    (Matrix4.invert (Object3d.matrix_world node)
       (Object3d.matrix_world_inverse node))
