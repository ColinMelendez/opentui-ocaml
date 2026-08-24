type camera_state = {
  mutable fov_degrees : float;
  mutable aspect : float;
  near : float;
  far : float;
}

type light_state = {
  color : Color.t;
  mutable intensity : float;
}

type point_state = {
  color : Color.t;
  mutable intensity : float;
  mutable distance : float;
}

type t = {
  mutable name : string option;
  mutable parent : t option;
  mutable children : t list;
  mutable visible : bool;
  position : Vector3.t;
  rotation : Euler.t;
  quaternion : Quaternion.t;
  scale : Vector3.t;
  up : Vector3.t;
  matrix : Matrix4.t;
  matrix_world : Matrix4.t;
  matrix_world_inverse : Matrix4.t;
  projection_matrix : Matrix4.t;
  mutable matrix_auto_update : bool;
  mutable matrix_world_auto_update : bool;
  mutable matrix_world_needs_update : bool;
  mutable synced_rotation : float * float * float;
  mutable kind : kind;
}
and kind =
  | Group
  | Scene_root
  | Mesh of Geometry.t * Material.t
  | Perspective_camera of camera_state
  | Directional_light of light_state * t
  | Point_light of point_state
  | Ambient_light of light_state

let make ?name ?(kind = Group) () =
  let rotation = Euler.create () in
  { name;
    parent = None;
    children = [];
    visible = true;
    position = Vector3.create ();
    rotation;
    quaternion = Quaternion.identity ();
    scale = Vector3.create ~x:1.0 ~y:1.0 ~z:1.0 ();
    up = Vector3.create ~x:0.0 ~y:1.0 ~z:0.0 ();
    matrix = Matrix4.identity (Matrix4.create ());
    matrix_world = Matrix4.identity (Matrix4.create ());
    matrix_world_inverse = Matrix4.identity (Matrix4.create ());
    projection_matrix = Matrix4.identity (Matrix4.create ());
    matrix_auto_update = true;
    matrix_world_auto_update = true;
    matrix_world_needs_update = false;
    synced_rotation = (0.0, 0.0, 0.0);
    kind }

let name t = t.name

let set_name t name = t.name <- name

let parent t = t.parent

let children t = t.children

let kind t = t.kind

let visible t = t.visible

let set_visible t visible = t.visible <- visible

let position t = t.position

let rotation t = t.rotation

let quaternion t = t.quaternion

let scale t = t.scale

let matrix t = t.matrix

let matrix_world t = t.matrix_world

let matrix_world_inverse t = t.matrix_world_inverse

let projection_matrix t = t.projection_matrix

let is_ancestor ancestor node =
  let rec reachable candidate =
    candidate == ancestor
    ||
    if List.exists reachable candidate.children then true
    else false
  in
  reachable node

let remove_from_parent node =
  match node.parent with
  | None -> ()
  | Some p ->
      p.children <-
        List.filter (fun c -> not (c == node)) p.children;
      node.parent <- None

let add t child =
  if child == t then
    raise
      (Invalid_argument
         "Object3D.add: object can't be added as a child of itself")
  else if is_ancestor t child then
    raise
      (Invalid_argument
         "Object3D.add: object can't be added as a descendant of itself")
  else begin
    remove_from_parent child;
    t.children <- t.children @ [ child ];
    child.parent <- Some t
  end

let remove t child =
  match child.parent with
  | Some p -> if p == t then remove_from_parent child
  | None -> ()

let clear t =
  List.iter (fun c -> c.parent <- None) t.children;
  t.children <- []

let get_object_by_name name t =
  let rec search node =
    match (node.name, node.children) with
    | Some n, _ when String.equal n name -> Some node
    | _ -> (
        let rec scan = function
          | [] -> None
          | child :: rest -> (
              match search child with Some found -> Some found | None -> scan rest)
        in
        scan node.children)
  in
  search t

let traverse f t =
  let rec walk node = f node; List.iter walk node.children in
  walk t

let sync_rotation t =
  let x, y, z = t.synced_rotation in
  if
    Float.compare t.rotation.x x <> 0
    || Float.compare t.rotation.y y <> 0
    || Float.compare t.rotation.z z <> 0
  then begin
    let q = Quaternion.set_from_euler ~x:t.rotation.x ~y:t.rotation.y ~z:t.rotation.z in
    Quaternion.copy t.quaternion q;
    t.synced_rotation <- (t.rotation.x, t.rotation.y, t.rotation.z)
  end

let update_matrix t =
  if t.matrix_auto_update then begin
    sync_rotation t;
    Matrix4.compose t.matrix t.position t.quaternion t.scale
  end;
  t.matrix_world_needs_update <- true

let rec update_matrix_world ?(force = false) t =
  let force = ref force in
  if t.matrix_auto_update then update_matrix t;
  if t.matrix_world_needs_update || !force then begin
    match t.parent with
    | None -> Matrix4.copy t.matrix_world t.matrix
    | Some p -> Matrix4.multiply t.matrix_world p.matrix_world t.matrix
  end;
  if t.matrix_world_needs_update || !force then begin
    t.matrix_world_needs_update <- false;
    force := true
  end;
  List.iter
    (fun child ->
      if child.matrix_world_auto_update || !force then
        update_matrix_world ~force:!force child)
    t.children
let rec update_world_matrix ~(parents : bool) ~(children : bool) t =
  (match (parents, t.parent) with
  | true, Some p -> update_world_matrix ~parents:true ~children:false p
  | _ -> ());
  update_matrix t;
  if t.matrix_world_needs_update then begin
    match t.parent with
    | None -> Matrix4.copy t.matrix_world t.matrix
    | Some p -> Matrix4.multiply t.matrix_world p.matrix_world t.matrix
  end;
  if t.matrix_world_needs_update then t.matrix_world_needs_update <- false;
  if children then
    List.iter (fun child -> update_world_matrix ~parents:false ~children:true child)
      t.children

let world_position ?into t =
  let out = match into with Some v -> v | None -> Vector3.create () in
  update_world_matrix ~parents:true ~children:false t;
  out.x <- Float.Array.get t.matrix_world 12;
  out.y <- Float.Array.get t.matrix_world 13;
  out.z <- Float.Array.get t.matrix_world 14;
  out

let world_quaternion ?into t =
  let out = match into with Some q -> q | None -> Quaternion.identity () in
  update_world_matrix ~parents:true ~children:false t;
  let rec ancestors node acc =
    match node.parent with
    | Some p -> ancestors p (node :: acc)
    | None -> node :: acc
  in
  let chain = ancestors t [] in
  Quaternion.set out 0.0 0.0 0.0 1.0;
  List.iter (fun node -> Quaternion.postmultiply out node.quaternion) chain;
  out

let transpose_rotation_block m =
  (* Matrix4.look_at writes the view convention (world-to-camera), whose
     rotation block is the transpose of the camera's own orientation.
     three.js Object3D.lookAt feeds an orientation matrix straight into
     setFromRotationMatrix, so flip the 3x3 back before extraction. *)
  for c = 0 to 2 do
    for r = c + 1 to 2 do
      let i = (c * 4) + r and j = (r * 4) + c in
      let tmp = Float.Array.get m i in
      Float.Array.set m i (Float.Array.get m j);
      Float.Array.set m j tmp
    done
  done

let look_at ~(target : Vector3.t) t =
  (* Bring euler-driven changes into the quaternion first so the method
     observes the same orientation a render would. *)
  sync_rotation t;
  let scratch_m = Matrix4.create () in
  let eye = world_position ~into:(Vector3.create ()) t in
  (match t.kind with
  | Perspective_camera _ | Directional_light _ ->
      Matrix4.look_at ~up:t.up ~eye ~target scratch_m
  | Group | Scene_root | Mesh _ | Ambient_light _ | Point_light _ ->
      Matrix4.look_at ~up:t.up ~eye:target ~target:eye scratch_m);
  transpose_rotation_block scratch_m;
  let q = Quaternion.from_euler_matrix scratch_m in
  Quaternion.copy t.quaternion q;
  match t.parent with
  | Some p ->
      Matrix4.extract_rotation scratch_m p.matrix_world;
      let parent_q = Quaternion.from_euler_matrix scratch_m in
      ignore (Quaternion.invert parent_q);
      Quaternion.premultiply t.quaternion ~a:parent_q
  | None -> ()

let rotate_on_axis ~(axis : Vector3.t) ~angle t =
  (* Pure local-space rotation: post-multiply only, symmetric with
     translate_on_axis. three.js r177 compensates through the parent world
     quaternion here; we deliberately do not - see the mli note. *)
  sync_rotation t;
  let q = Quaternion.from_axis_angle ~axis ~angle in
  Quaternion.postmultiply t.quaternion q

let rotate_x t angle = rotate_on_axis ~axis:(Vector3.create ~x:1.0 ()) ~angle t

let rotate_y t angle = rotate_on_axis ~axis:(Vector3.create ~y:1.0 ()) ~angle t

let rotate_z t angle = rotate_on_axis ~axis:(Vector3.create ~z:1.0 ()) ~angle t

let translate_on_axis ~(axis : Vector3.t) ~distance t =
  (* three.js translateOnAxis assumes a normalized axis and applies the
     local rotation before stepping along it; the rotation math is inlined
     here because the math modules must stay dependency-acyclic. Pending
     euler changes sync first so the step follows the visible orientation. *)
  sync_rotation t;
  let step = Vector3.clone axis in
  let x = step.x and y = step.y and z = step.z in
  let q = t.quaternion in
  let qx = q.x and qy = q.y and qz = q.z and qw = q.w in
  let ix = (qw *. x) +. (qy *. z) -. (qz *. y) in
  let iy = (qw *. y) +. (qz *. x) -. (qx *. z) in
  let iz = (qw *. z) +. (qx *. y) -. (qy *. x) in
  let iw = (qx *. x) +. (qy *. y) +. (qz *. z) in
  step.x <- (ix *. qw) -. (iw *. qx) -. (iy *. qz) +. (iz *. qy);
  step.y <- (iy *. qw) -. (iw *. qy) -. (iz *. qx) +. (ix *. qz);
  step.z <- (iz *. qw) -. (iw *. qz) -. (ix *. qy) +. (iy *. qx);
  Vector3.multiply_scalar step distance;
  Vector3.add t.position step

let translate_x t distance =
  translate_on_axis ~axis:(Vector3.create ~x:1.0 ()) ~distance t

let translate_y t distance =
  translate_on_axis ~axis:(Vector3.create ~y:1.0 ()) ~distance t

let translate_z t distance =
  translate_on_axis ~axis:(Vector3.create ~z:1.0 ()) ~distance t
